#!/usr/bin/python

"""
Runs coffea processors on the LPC via either condor or dask.

Author(s): Cristina Mantilla Suarez, Raghav Kansal
"""

import pickle
import os
import json
import argparse
import warnings

import numpy as np
import uproot

from coffea import nanoevents
from coffea import processor

from distributed.diagnostics.plugin import WorkerPlugin


def fxn():
    warnings.warn("userwarning", UserWarning)


with warnings.catch_warnings():
    warnings.simplefilter("ignore")
    fxn()


def add_bool_arg(parser, name, help, default=False, no_name=None):
    """Add a boolean command line argument for argparse"""
    varname = "_".join(name.split("-"))  # change hyphens to underscores
    group = parser.add_mutually_exclusive_group(required=False)
    group.add_argument("--" + name, dest=varname, action="store_true", help=help)
    if no_name is None:
        no_name = "no-" + name
        no_help = "don't " + help
    else:
        no_help = help
    group.add_argument("--" + no_name, dest=varname, action="store_false", help=no_help)
    parser.set_defaults(**{varname: default})


def add_mixins(nanoevents):
    # for running on condor
    nanoevents.PFNanoAODSchema.nested_index_items["FatJetAK15_pFCandsIdxG"] = (
        "FatJetAK15_nConstituents",
        "JetPFCandsAK15",
    )
    nanoevents.PFNanoAODSchema.mixins["FatJetAK15"] = "FatJet"
    nanoevents.PFNanoAODSchema.mixins["FatJetAK15SubJet"] = "FatJet"
    nanoevents.PFNanoAODSchema.mixins["SubJet"] = "FatJet"
    nanoevents.PFNanoAODSchema.mixins["PFCands"] = "PFCand"
    nanoevents.PFNanoAODSchema.mixins["SV"] = "PFCand"


# for Dask executor
class NanoeventsSchemaPlugin(WorkerPlugin):
    def __init__(self):
        pass

    def setup(self, worker):
        from coffea import nanoevents

        add_mixins(nanoevents)


def get_fileset(processor: str, year: int, samples: list, subsamples: list, starti: int, endi: int):
    if processor == "trigger":
        index_file = f"data/singlemuon_pfnanoindex_{year}.json"
        samples = [f"SingleMu{year}"]
    else:
        index_file = f"data/pfnanoindex_{year}.json"

    with open(index_file, "r") as f:
        full_fileset = json.load(f)

    fileset = {}

    for sample in samples:
        sample_set = full_fileset[year][sample]
        set_subsamples = list(sample_set.keys())

        # check if any subsamples for this sample have been specified
        get_subsamples = set(set_subsamples).intersection(subsamples)

        # if so keep only that subset
        if len(get_subsamples):
            sample_set = {subsample: sample_set[subsample] for subsample in get_subsamples}

        sample_fileset = {}

        for subsample, fnames in sample_set.items():
            fnames = fnames[starti:] if endi < 0 else fnames[starti:endi]
            sample_fileset[f"{year}_{subsample}"] = [
                "root://cmsxrootd.fnal.gov//" + fname for fname in fnames
            ]

        fileset = {**fileset, **sample_fileset}

    return fileset


def get_xsecs():
    with open("data/xsecs.json") as f:
        xsecs = json.load(f)

    for key, value in xsecs.items():
        if type(value) == str:
            xsecs[key] = eval(value)

    return xsecs


def main(args):

    # define processor
    if args.processor == "trigger":
        from HHbbVV.processors import JetHTTriggerEfficienciesProcessor

        p = JetHTTriggerEfficienciesProcessor()
    elif args.processor == "skimmer":
        from HHbbVV.processors import bbVVSkimmer

        p = bbVVSkimmer(xsecs=get_xsecs(), save_ak15=args.save_ak15)
    elif args.processor == "input":
        from HHbbVV.processors import TaggerInputSkimmer

        p = TaggerInputSkimmer(args.label, args.njets)

    fileset = (
        get_fileset(
            args.processor, args.year, args.samples, args.subsamples, args.starti, args.endi
        )
        if not len(args.files)
        else {f"{args.year}_{args.files_name}": args.files}
    )

    # lpcjobqueue
    if args.executor == "dask":
        import time
        from distributed import Client
        from lpcjobqueue import LPCCondorCluster

        tic = time.time()
        cluster = LPCCondorCluster(
            ship_env=True,
            transfer_input_files="src/HHbbVV",
        )
        client = Client(cluster)
        nanoevents_plugin = NanoeventsSchemaPlugin()
        client.register_worker_plugin(nanoevents_plugin)
        cluster.adapt(minimum=1, maximum=30)

        print("Waiting for at least one worker")
        client.wait_for_workers(1)

        # does treereduction help?
        executor = processor.DaskExecutor(status=True, client=client)
        run = processor.Runner(
            executor=executor,
            savemetrics=True,
            schema=nanoevents.PFNanoAODSchema,
            chunksize=args.chunksize,
        )
        hists, metrics = run(
            {key: fileset[key] for key in args.samples}, "Events", processor_instance=p
        )

        elapsed = time.time() - tic
        print(f"hists: {hists}")
        print(f"Metrics: {metrics}")
        print(f"Finished in {elapsed:.1f}s")

        with open("hists.pkl", "wb") as f:
            pickle.dump(hists, f)

    # plain condor
    else:
        add_mixins(nanoevents)
        local_dir = os.path.abspath(".")
        local_parquet_dir = os.path.abspath(os.path.join(".", "outparquet"))

        if os.path.isdir(local_parquet_dir):
            os.system(f"rm -rf {local_parquet_dir}")

        os.system(f"mkdir {local_parquet_dir}")

        uproot.open.defaults["xrootd_handler"] = uproot.source.xrootd.MultithreadedXRootDSource

        if args.executor == "futures":
            executor = processor.FuturesExecutor(status=True)
        else:
            executor = processor.IterativeExecutor(status=True)

        run = processor.Runner(
            executor=executor,
            savemetrics=True,
            schema=nanoevents.PFNanoAODSchema,
            chunksize=args.chunksize,
            maxchunks=None if args.maxchunks == 0 else args.maxchunks,
        )

        out, metrics = run(fileset, "Events", processor_instance=p)

        filehandler = open(f"outfiles/{args.starti}-{args.endi}.pkl", "wb")
        pickle.dump(out, filehandler)
        filehandler.close()

        if args.processor == "skimmer" or args.processor == "input":
            import pandas as pd
            import pyarrow.parquet as pq
            import pyarrow as pa

            pddf = pd.read_parquet(local_parquet_dir)

            if args.processor == "skimmer":
                # need to write with pyarrow as pd.to_parquet doesn't support different types in
                # multi-index column names
                table = pa.Table.from_pandas(pddf)
                pq.write_table(table, f"{local_dir}/{args.starti}-{args.endi}.parquet")

            if args.processor == "input":
                # save as root files for input skimmer

                import awkward as ak

                with uproot.recreate(
                    f"{local_dir}/nano_skim_{args.starti}-{args.endi}.root",
                    compression=uproot.LZ4(4),
                ) as rfile:
                    rfile["Events"] = ak.Array(
                        # take only top-level column names in multiindex df
                        {key: np.squeeze(pddf[key].values) for key in pddf.columns.levels[0]}
                    )


if __name__ == "__main__":
    # e.g.
    # inside a condor job: python run.py --year 2017 --processor trigger --condor --starti 0 --endi 1
    # inside a dask job:  python run.py --year 2017 --processor trigger --dask

    parser = argparse.ArgumentParser()
    parser.add_argument("--year", default="2017", help="year", type=str)
    parser.add_argument("--starti", default=0, help="start index of files", type=int)
    parser.add_argument("--endi", default=-1, help="end index of files", type=int)
    parser.add_argument(
        "--processor",
        default="trigger",
        help="Trigger processor",
        type=str,
        choices=["trigger", "skimmer", "input"],
    )
    parser.add_argument(
        "--executor",
        type=str,
        default="iterative",
        choices=["futures", "iterative", "dask"],
        help="type of processor executor",
    )
    parser.add_argument("--samples", default=[], help="samples", nargs="*")
    parser.add_argument("--subsamples", default=[], help="subsamples", nargs="*")
    parser.add_argument(
        "--files", default=[], help="set of files to run on instead of samples", nargs="*"
    )
    parser.add_argument(
        "--files-name",
        type=str,
        default="files",
        help="sample name of files being run on, if --files option used",
    )
    parser.add_argument("--chunksize", type=int, default=10000, help="chunk size in processor")
    parser.add_argument("--label", default="AK15_H_VV", help="label", type=str)
    parser.add_argument("--njets", default=2, help="njets", type=int)
    parser.add_argument("--maxchunks", default=0, help="max chunks", type=int)

    add_bool_arg(parser, "save-ak15", default=False, help="run inference for and save ak15 jets")

    args = parser.parse_args()

    main(args)
