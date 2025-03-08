# Definizione dei path
DWI="/Users/emanueleamato/Downloads/AnalisiDTI-GNN/images_DTI/nifti/ADNI_003_S_0908_MR_Axial_DTI__br_raw_20140113094434427_1_S210038_I404532.nii.gz"
BVEC="/Users/emanueleamato/Downloads/AnalisiDTI-GNN/images_DTI/ADNI_003_S_0908_MR_Axial_DTI__br_raw_20140113094434427_1_S210038_I404532.bvec"
BVAL="/Users/emanueleamato/Downloads/AnalisiDTI-GNN/images_DTI/ADNI_003_S_0908_MR_Axial_DTI__br_raw_20140113094434427_1_S210038_I404532.bval"

# Directory di output principale
OUT_DIR="/Users/emanueleamato/Downloads/AnalisiDTI-GNN/S_1074_axial_DTI_Test/OUT"
mkdir -p "${OUT_DIR}"

# File Atlas Harvard-Oxford
ATLAS_CORTICAL="/Users/emanueleamato/fsl/data/atlases/HarvardOxford/HarvardOxford-cort-maxprob-thr25-1mm.nii.gz"
ATLAS_SUBCORTICAL="/Users/emanueleamato/fsl/data/atlases/HarvardOxford/HarvardOxford-sub-maxprob-thr25-1mm.nii.gz"

# Verifica che i file di input esistano
for file in "$DWI" "$BVEC" "$BVAL" "$ATLAS_CORTICAL" "$ATLAS_SUBCORTICAL"; do
    if [ ! -f "$file" ]; then
        echo "Errore: Il file $file non esiste!" >&2
        exit 1
    fi
done

# Step 1: Registrazione di DWI allo spazio MNI152
echo "Step 1: Registrazione di DWI allo spazio MNI152"
flirt -in "${DWI}" -ref "/Users/emanueleamato/fsl/data/standard/MNI152_T1_1mm.nii.gz" \
      -out "${OUT_DIR}/dwi_mni152.nii.gz" -omat "${OUT_DIR}/dwi2mni.mat" -dof 12

# Step 2: Correzione delle distorsioni
echo "Step 2: Correzione delle distorsioni"
eddy_correct "${OUT_DIR}/dwi_mni152.nii.gz" "${OUT_DIR}/data_corr.nii.gz" 0

# Step 3: Estrazione del cervello
echo "Step 3: Estrazione del cervello"
bet "${OUT_DIR}/data_corr.nii.gz" "${OUT_DIR}/nodif_brain.nii.gz" -f 0.3 -g 0 -m
BRAIN_MASK="${OUT_DIR}/nodif_brain_mask.nii.gz"

# Step 4: Fit del modello di diffusione con BEDPOSTX
echo "Step 4: Fit del modello di diffusione con BEDPOSTX"
BEDPOSTX_DIR="${OUT_DIR}/BEDPOSTX"
mkdir -p "${BEDPOSTX_DIR}"
cp "${OUT_DIR}/data_corr.nii.gz" "${BEDPOSTX_DIR}/data.nii.gz"
cp "${BVEC}" "${BEDPOSTX_DIR}/bvecs"
cp "${BVAL}" "${BEDPOSTX_DIR}/bvals"
cp "${BRAIN_MASK}" "${BEDPOSTX_DIR}/nodif_brain_mask.nii.gz"
bedpostx "${BEDPOSTX_DIR}"

# Step 5: Creazione delle ROI
echo "Step 5: Creazione delle ROI dagli atlanti"
ROI_DIR="${OUT_DIR}/ROIs"
mkdir -p "${ROI_DIR}"

for ((i=1; i<=48; i++)); do 
    fslmaths "${ATLAS_CORTICAL}" -thr $i -uthr $i -bin "${ROI_DIR}/Cortical_${i}.nii.gz" 
done 

for ((i=1; i<=21; i++)); do 
    fslmaths "${ATLAS_SUBCORTICAL}" -thr $i -uthr $i -bin "${ROI_DIR}/Subcortical_${i}.nii.gz" 
done 

echo "ROI salvate in ${ROI_DIR}"

# Step 6: Trattografia probabilistica
echo "Step 6: Esecuzione della trattografia probabilistica"
PROBTRACKX_OUT="${OUT_DIR}/Tractography"
mkdir -p "${PROBTRACKX_OUT}"

TARGETS_FILE="${OUT_DIR}/target_list.txt"
> "${TARGETS_FILE}"

for TARGET in "${ROI_DIR}"/*.nii.gz; do
    if [ -f "$TARGET" ]; then  
        echo "${TARGET}" >> "${TARGETS_FILE}" 
    fi
done

for SEED_ROI in "${ROI_DIR}"/*.nii.gz; do 
    SEED_NAME=$(basename "${SEED_ROI}" .nii.gz) 
    SEED_OUT_DIR="${PROBTRACKX_OUT}/${SEED_NAME}" 
    mkdir -p "${SEED_OUT_DIR}" 

    echo "Trattografia da seed: ${SEED_NAME}" 

    probtrackx2 \
        -x "${SEED_ROI}" \
        --seedref "${OUT_DIR}/nodif_brain.nii.gz" \
        -l --onewaycondition \
        -c 0.2 \
        -S 2000 \
        --steplength=0.5 \
        -P 5000 \
        --fibthresh=0.01 \
        --distthresh=0.0 \
        --sampvox=0.0 \
        --forcedir \
        --opd \
        -s "${BEDPOSTX_DIR}.bedpostX/merged" \
        -m "${BRAIN_MASK}" \
        --targetmasks="${TARGETS_FILE}" \
        --dir="${SEED_OUT_DIR}" 

    echo "Trattografia completata per ${SEED_NAME}" 
done

echo "Pipeline completata con successo!"
