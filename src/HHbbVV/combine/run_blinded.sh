#!/bin/bash

####################################################################################################
# Script for fits
# 
# 1) Combines cards and makes a workspace (--workspace / -w)
# 2) Background-only fit (--bfit / -b)
# 3) Expected asymptotic limits (--limits / -l)
# 4) Expected significance (--significance / -s)
# 5) Fit diagnostics (--dfit / -d)
# 6) GoF on data (--gofdata / -g)
# 7) GoF on toys (--goftoys / -t),
# 8) Impacts: initial fit (--impactsinit / -i), per-nuisance fits (--impactsfits), collect (--impactscollect)
#    specify seed with --seed (default 42) and number of toys with --numtoys (default 100)
# 9) Bias test: run a bias test on toys (using post-fit nuisances) with expected signal strength 
#    given by --bias X.
# 
# Specify resonant with --resonant / -r, otherwise does nonresonant
#
# Usage ./run_blinded.sh [-wblsdgt] [--numtoys 100] [--seed 42] 
#
# Author: Raghav Kansal
####################################################################################################


####################################################################################################
# Read options
####################################################################################################

workspace=0
bfit=0
limits=0
significance=0
dfit=0
resonant=0
gofdata=0
goftoys=0
impactsinit=0
impactsfits=0
impactscollect=0
seed=42
numtoys=100
bias=-1

options=$(getopt -o "wblsdrgti" --long "workspace,bfit,limits,significance,dfit,resonant,gofdata,goftoys,impactsinit,impactsfits,impactscollect,seed:,numtoys:,bias:" -- "$@")
eval set -- "$options"

while true; do
    case "$1" in
        -w|--workspace)
            workspace=1
            ;;
        -b|--bfit)
            bfit=1
            ;;
        -l|--limits)
            limits=1
            ;;
        -s|--significance)
            significance=1
            ;;
        -d|--dfit)
            dfit=1
            ;;
        -r|--resonant)
            resonant=1
            ;;
        -g|--gofdata)
            gofdata=1
            ;;
        -t|--goftoys)
            goftoys=1
            ;;
        -i|--impactsinit)
            impactsinit=1
            ;;
        --impactsfits)
            impactsfits=1
            ;;
        --impactscollect)
            impactscollect=1
            ;;
        --seed)
            shift
            seed=$1
            ;;
        --numtoys)
            shift
            numtoys=$1
            ;;
        --bias)
            shift
            bias=$1
            ;;
        --)
            shift
            break;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            exit 1
            ;;
        :)
            echo "Option -$OPTARG requires an argument." >&2
            exit 1
            ;;
    esac
    shift
done

echo "Arguments: resonant=$resonant workspace=$workspace bfit=$bfit limits=$limits \
significance=$significance dfit=$dfit gofdata=$gofdata goftoys=$goftoys \
seed=$seed numtoys=$numtoys"


####################################################################################################
# Set up fit arguments
# 
# We use channel masking to "mask" the blinded and "unblinded" regions in the same workspace. 
# (mask = 1 means the channel is masked off) 
####################################################################################################

dataset=data_obs
cards_dir="./"
ws=${cards_dir}/combined
wsm=${ws}_withmasks
wsm_snapshot=higgsCombineSnapshot.MultiDimFit.mH125
CMS_PARAMS_LABEL="CMS_bbWW_hadronic"

outsdir=${cards_dir}/outs
mkdir -p $outsdir

if [ $resonant = 0 ]; then
    if [ -f "mXbin0pass.txt" ]; then
        echo -e "\nWARNING: This is doing nonresonant fits - did you mean to pass -r|--resonant?\n"
    fi

    # nonresonant args
    ccargs="fail=${cards_dir}/fail.txt failBlinded=${cards_dir}/failBlinded.txt pass=${cards_dir}/pass.txt passBlinded=${cards_dir}/passBlinded.txt"
    maskunblindedargs="mask_pass=1,mask_fail=1,mask_passBlinded=0,mask_failBlinded=0"
    maskblindedargs="mask_pass=0,mask_fail=0,mask_passBlinded=1,mask_failBlinded=1"

    # freeze qcd params in blinded bins
    setparamsblinded=""
    freezeparamsblinded=""
    for bin in {5..9}
    do
        setparamsblinded+="${CMS_PARAMS_LABEL}_tf_dataResidual_Bin${bin}=0,"
        freezeparamsblinded+="${CMS_PARAMS_LABEL}_tf_dataResidual_Bin${bin},"
    done

    # remove last comma
    setparamsblinded=${setparamsblinded%,}
    freezeparamsblinded=${freezeparamsblinded%,}

    unblindedparams="--setParameters $maskblindedargs"

    excludeimpactparams='rgx{.*tf_dataResidual_Bin.*}'
else
    # resonant args
    ccargs=""
    maskunblindedargs=""
    maskblindedargs=""

    for bin in {0..9}
    do
        for channel in fail failBlinded pass passBlinded;
        do
            ccargs+="mXbin${bin}${channel}=${cards_dir}/mXbin${bin}${channel}.txt "
        done

        for channel in fail pass;
        do
            maskunblindedargs+="mask_mXbin${bin}${channel}=1,mask_mXbin${bin}${channel}Blinded=0,"
            maskblindedargs+="mask_mXbin${bin}${channel}=0,mask_mXbin${bin}${channel}Blinded=1,"
        done
    done

    # remove last comma
    maskunblindedargs=${maskunblindedargs%,}
    maskblindedargs=${maskblindedargs%,}

    setparamsblinded="rgx{pass_.*mcstat.*}=0,rgx{fail_.*mcstat.*}=0"
    freezeparamsblinded="rgx{pass_.*mcstat.*},rgx{fail_.*mcstat.*},rgx{.*xhy_mx.*}"

    setparamsunblinded="rgx{passBlinded_.*mcstat.*}=0,rgx{failBlinded_.*mcstat.*}=0"
    freezeparamsunblinded="rgx{passBlinded_.*mcstat.*},rgx{failBlinded_.*mcstat.*}"

    unblindedparams="--freezeParameters ${freezeparamsunblinded} --setParameters ${maskblindedargs},${setparamsunblinded}"

    excludeimpactparams='rgx{.*qcdparam_mXbin.*},rgx{passBlinded_.*mcstat.*},rgx{failBlinded_.*mcstat.*}'
fi

echo "mask args:"
echo $maskblindedargs

echo "set params:"
echo $setparamsblinded

echo "freeze params:"
echo $freezeparamsblinded

echo "unblinded params:"
echo $unblindedparams

####################################################################################################
# Combine cards, text2workspace, fit, limits, significances, fitdiagnositcs, GoFs
####################################################################################################

# need to run this for large # of nuisances 
# https://cms-talk.web.cern.ch/t/segmentation-fault-in-combine/20735
ulimit -s unlimited

if [ $workspace = 1 ]; then
    echo "Combining cards"
    combineCards.py $ccargs > $ws.txt

    echo "Running text2workspace"
    text2workspace.py -D $dataset $ws.txt --channel-masks -o $wsm.root 2>&1 | tee $outsdir/text2workspace.txt
else
    if [ ! -f "$wsm.root" ]; then
        echo "Workspace doesn't exist! Use the -w|--workspace option to make workspace first"
        exit 1
    fi
fi


if [ $bfit = 1 ]; then
    echo "Blinded background-only fit"
    combine -D $dataset -M MultiDimFit --saveWorkspace -m 125 -d ${wsm}.root -v 9 \
    --cminDefaultMinimizerStrategy 1 \
    --setParameters ${maskunblindedargs},${setparamsblinded},r=0  \
    --freezeParameters r,${freezeparamsblinded} \
    -n Snapshot 2>&1 | tee $outsdir/MultiDimFit.txt
else
    if [ ! -f "higgsCombineSnapshot.MultiDimFit.mH125.root" ]; then
        echo "Background-only fit snapshot doesn't exist! Use the -b|--bfit option to run fit first"
        exit 1
    fi
fi


if [ $limits = 1 ]; then
    echo "Expected limits"

    combine -M AsymptoticLimits -m 125 -n pass -d ${wsm_snapshot}.root --snapshotName MultiDimFit -v 9 \
    --saveWorkspace --saveToys --bypassFrequentistFit \
    ${unblindedparams} \
    --floatParameters r --toysFrequentist --run blind 2>&1 | tee $outsdir/AsymptoticLimits.txt
fi


if [ $significance = 1 ]; then
    echo "Expected significance"
    combine -M Significance -d ${wsm_snapshot}.root --significance -m 125 -n pass --snapshotName MultiDimFit -v 9 \
    -t -1 --expectSignal=1 --saveWorkspace --saveToys --bypassFrequentistFit \
    ${unblindedparams},r=1 \
    --floatParameters r --toysFrequentist 2>&1 | tee $outsdir/Significance.txt
fi


if [ $dfit = 1 ]; then
    echo "Fit Diagnostics"
    combine -M FitDiagnostics -m 125 -d ${wsm}.root \
    --setParameters ${maskunblindedargs},${setparamsblinded} \
    --freezeParameters ${freezeparamsblinded} \
    -n Blinded --ignoreCovWarning -v 9 2>&1 | tee $outsdir/FitDiagnostics.txt
    --saveShapes --saveNormalizations --saveWithUncertainties --saveOverallShapes \

    echo "Fit Shapes"
    PostFitShapesFromWorkspace --dataset $dataset -w ${wsm}.root --output FitShapes.root \
    -m 125 -f fitDiagnosticsBlinded.root:fit_b --postfit --print 2>&1 | tee $outsdir/FitShapes.txt
fi


if [ $gofdata = 1 ]; then
    echo "GoF on data"
    combine -M GoodnessOfFit -d ${wsm_snapshot}.root --algo saturated -m 125 \
    --snapshotName MultiDimFit --bypassFrequentistFit \
    --setParameters ${maskunblindedargs},${setparams},r=0 \
    --freezeParameters ${freezeparams},r \
    -n Data -v 9 2>&1 | tee $outsdir/GoF_data.txt
fi


if [ $goftoys = 1 ]; then
    echo "GoF on toys"
    combine -M GoodnessOfFit -d ${wsm_snapshot}.root --algo saturated -m 125 \
    --snapshotName MultiDimFit --bypassFrequentistFit \
    --setParameters ${maskunblindedargs},${setparams},r=0 \
    --freezeParameters ${freezeparams},r --saveToys \
    -n Toys -v 9 -s $seed -t $numtoys --toysFrequentist 2>&1 | tee $outsdir/GoF_toys.txt
fi


if [ $impactsinit = 1 ]; then
    echo "Initial fit for impacts"
    combineTool.py -M Impacts -t -1 --snapshotName MultiDimFit --bypassFrequentistFit --toysFrequentist --expectSignal 1 \
    -m 125 -n "impacts" -d ${wsm_snapshot}.root --doInitialFit --robustFit 1 \
    ${unblindedparams} \
    --setParameterRanges r=-20,20 --cminDefaultMinimizerStrategy=1 -v 9 2>&1 | tee $outsdir/Impacts_initial.txt
fi


if [ $impactsfits = 1 ]; then
    echo "Submitting jobs for impact scans"
    combineTool.py -M Impacts -t -1 --snapshotName MultiDimFit --bypassFrequentistFit --toysFrequentist --expectSignal 1 \
    -m 125 -n "impacts" -d ${wsm_snapshot}.root --doFits --robustFit 1 \
    --setParameters ${maskblindedargs} \
    --exclude ${excludeimpactparams} \
    --job-mode condor \
    --setParameterRanges r=-20,20 --cminDefaultMinimizerStrategy=1 -v 9 2>&1 | tee $outsdir/Impacts_fits.txt
fi


if [ $impactscollect = 1 ]; then
    echo "Collecting impacts"
    combineTool.py -M Impacts -t -1 --snapshotName MultiDimFit \
    -m 125 -n "impacts" -d ${wsm_snapshot}.root \
    --setParameters ${maskblindedargs} \
    --exclude ${excludeimpactparams} \
    --setParameterRanges r=-20,20 -v 9 -o impacts.json 2>&1 | tee $outsdir/Impacts_collect.txt
fi


if [ $bias != -1 ]; then
    echo "Bias test with bias $bias"
    combineTool.py -M FitDiagnostics --trackParameters r --trackErrors r --justFit \
    -m 125 -n "bias${bias}" -d ${wsm_snapshot}.root --rMin "-20" --rMax 20 \
    --snapshotName MultiDimFit --bypassFrequentistFit --toysFrequentist --expectSignal $bias \
    ${unblindedparams} \
    --robustFit=1 -t $numtoys -s $seed 2>&1 | tee $outsdir/bias${bias}seed${seed}.txt
fi

