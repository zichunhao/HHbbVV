#!/bin/bash
# shellcheck disable=SC2086,SC2043,SC2206

####################################################################################################
# Script for creating nonresonant templates scanning over variables
# Author: Raghav Kansal
####################################################################################################

years=("2016APV" "2016" "2017" "2018")

MAIN_DIR="../../.."
data_dir="$MAIN_DIR/../data/skimmer/24Mar14UpdateData"
bdt_preds_dir="$data_dir/24_04_05_k2v0_training_eqsig_vbf_vars_rm_deta/inferences"
sig_samples="HHbbVV"
# sig_samples="qqHH_CV_1_C2V_0_kl_1_HHbbVV"
TAG=""
lepton_veto=""
txbb_cut=""
bdt_cut=""

options=$(getopt -o "" --long "lveto,bdt,txbb,year:,tag:" -- "$@")
eval set -- "$options"

while true; do
    case "$1" in
        --lveto)
            lepton_veto="--lepton-veto None Hbb HH"
            ;;
        --bdt)
            bdt_cut="--nonres-ggf-bdt-wp 0.99 0.997 0.998 0.999"
            # bdt_cut="--nonres-bdt-wp 0.99 0.997 0.998 0.999 0.9997 0.9999"
            ;;
        --txbb)
            txbb_cut="--nonres-ggf-txbb-wp MP HP"
            ;;
        --year)
            shift
            years=($1)
            ;;
        --tag)
            shift
            TAG=$1
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

if [[ -z $TAG ]]; then
  echo "Tag required using the --tag option. Exiting"
  exit 1
fi

for year in "${years[@]}"
do
    echo $year
    python -u postprocessing.py --year $year --data-dir "$data_dir" --bdt-preds-dir $bdt_preds_dir \
    --templates --template-dir "templates/$TAG" --no-do-jshifts \
    --plot-dir "${MAIN_DIR}/plots/PostProcessing/$TAG" --no-plot-shifts \
    $lepton_veto $bdt_cut $txbb_cut --sig-samples $sig_samples --nonres-regions "ggf" # --bg-keys "" --no-data
done
