MAIN_DIR="../../.."
TAG=24Jan8Res

for year in 2016APV
do
    python -u postprocessing.py --control-plots --year $year --resonant --HEM2d \
    --data-dir "${MAIN_DIR}/../data/skimmer/Feb24" \
    --signal-data-dirs "${MAIN_DIR}/../data/skimmer/Jun10" "${MAIN_DIR}/../data/skimmer/23Aug22_5xhy" \
    --sig-samples  'HHbbVV' 'VBFHHbbVV' 'NMSSM_XToYHTo2W2BTo4Q2B_MX-900_MY-80' 'NMSSM_XToYHTo2W2BTo4Q2B_MX-1200_MY-190' 'NMSSM_XToYHTo2W2BTo4Q2B_MX-2000_MY-125' 'NMSSM_XToYHTo2W2BTo4Q2B_MX-3000_MY-250' 'NMSSM_XToYHTo2W2BTo4Q2B_MX-4000_MY-150' \
    --plot-dir "${MAIN_DIR}/plots/PostProcessing/$TAG"
done