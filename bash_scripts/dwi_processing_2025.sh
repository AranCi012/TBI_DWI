#!/bin/bash

# ==========================
# Pipeline DWI - Versione 2025 - Refactory update 4/03/2025
# ==========================

# Definizione dei path dinamici (modificabili dall'utente)
DWI="$1"  # Input DWI .nii.gz
BVEC="$2" # File bvec
BVAL="$3" # File bval
OUT_DIR="$4"  # Cartella di output
ATLAS="/lustrehome/emanueleamato/atlases/MNI152NLin2009cAsym.nii.gz"  
ATLAS_CORTICAL="/lustrehome/emanueleamato/atlases/HarvardOxford-cort-maxprob-thr25-1mm.nii.gz"
ATLAS_SUBCORTICAL="/lustrehome/emanueleamato/atlases/HarvardOxford-sub-maxprob-thr25-1mm.nii.gz"
MNI_REF="/lustrehome/emanueleamato/fsl/data/standard/MNI152_T1_1mm.nii.gz"

# Creazione directory output
mkdir -p "$OUT_DIR/preprocessing"
mkdir -p "$OUT_DIR/dti_metrics"
mkdir -p "$OUT_DIR/tractography"
mkdir -p "$OUT_DIR/reports"
mkdir -p "$OUT_DIR/ROIs"

# Verifica esistenza file di input
for file in "$DWI" "$BVEC" "$BVAL" "$ATLAS" "$ATLAS_CORTICAL" "$ATLAS_SUBCORTICAL" "$MNI_REF"; do
    if [ ! -f "$file" ]; then
        echo "Errore: File $file non trovato!" >&2
        exit 1
    fi
done

# ==========================
# 1. Registrazione in MNI152
# ==========================
echo "[Step 1] Registrazione di DWI allo spazio MNI152"
flirt -in "$DWI" -ref "$MNI_REF" \
      -out "$OUT_DIR/preprocessing/dwi_mni152.nii.gz" -omat "$OUT_DIR/preprocessing/dwi2mni.mat" -dof 12

# ==========================
# 2. Generazione delle ROI
# ==========================
echo "[Step 2] Creazione delle ROI corticali e subcorticali"
ROI_DIR="$OUT_DIR/ROIs"

for ((i=1; i<=48; i++)); do 
    fslmaths "$ATLAS_CORTICAL" -thr $i -uthr $i -bin "$ROI_DIR/Cortical_${i}.nii.gz" 
done 

for ((i=1; i<=21; i++)); do 
    fslmaths "$ATLAS_SUBCORTICAL" -thr $i -uthr $i -bin "$ROI_DIR/Subcortical_${i}.nii.gz" 
done 

# ==========================
# 3. Preprocessing DWI
# ==========================
echo "[Step 3] Correzione artefatti con MRtrix3 (dwifslpreproc)"
dwifslpreproc "$OUT_DIR/preprocessing/dwi_mni152.nii.gz" "$OUT_DIR/preprocessing/dwi_preprocessed.mif" \
    -fslgrad "$BVEC" "$BVAL" -pe_dir AP -rpe_none -cuda -eddy_options "--repol"

# Creazione maschera cerebrale
echo "[Step 4] Creazione della maschera cerebrale"
dwi2mask "$OUT_DIR/preprocessing/dwi_preprocessed.mif" "$OUT_DIR/preprocessing/mask.mif"

# ==========================
# 4. Modellizzazione della diffusione
# ==========================
echo "[Step 5] Calcolo del tensore di diffusione"
dwi2tensor "$OUT_DIR/preprocessing/dwi_preprocessed.mif" "$OUT_DIR/dti_metrics/dti.mif"
tensor2metric "$OUT_DIR/dti_metrics/dti.mif" -fa "$OUT_DIR/dti_metrics/fa.mif" -adc "$OUT_DIR/dti_metrics/md.mif"

# ==========================
# 5. Trattografia
# ==========================
echo "[Step 6] Tractografia probabilistica con iFOD2"
dwi2response tournier "$OUT_DIR/preprocessing/dwi_preprocessed.mif" "$OUT_DIR/tractography/response.txt"
dwi2fod msmt_csd "$OUT_DIR/preprocessing/dwi_preprocessed.mif" "$OUT_DIR/tractography/response.txt" "$OUT_DIR/tractography/fod.mif"
tckgen "$OUT_DIR/tractography/fod.mif" "$OUT_DIR/tractography/tracts.tck" -act "$OUT_DIR/preprocessing/mask.mif" -seed_dynamic "$OUT_DIR/tractography/fod.mif" -select 1000000 -algorithm iFOD2

# ==========================
# 6. Report Finale
# ==========================
echo "[Step 7] Generazione report finale"
touch "$OUT_DIR/reports/pipeline_summary.txt"
echo "Pipeline DWI completata con successo! I risultati si trovano in $OUT_DIR"

