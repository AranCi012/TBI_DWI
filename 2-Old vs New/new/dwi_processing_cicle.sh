#!/bin/bash

# ==========================
# Pipeline DWI - Versione 2025 - Refactory update 07/03/2025
# ==========================

# Attivazione di MRtrix3 nell'ambiente Conda
CONDA_ENV="tbi_dwi_py312"
conda activate "$CONDA_ENV"
#source "/lustrehome/emanueleamato/.conda/etc/profile.d/conda.sh"

# Verifica che MRtrix3 sia accessibile
echo "Usando MRtrix3 da: $(which dwifslpreproc)"

# Directory principale contenente i dati grezzi dei pazienti
INPUT_DIR="$1"  # Es: "/path/to/directory"
OUTPUT_DIR="$2" # Es: "/path/to/directory_processed"

# Definizione degli atlanti e riferimenti
ATLAS="/lustrehome/emanueleamato/fsl/data/standard/MNI152_T1_1mm.nii.gz"  
ATLAS_CORTICAL="/lustrehome/emanueleamato/fsl/data/atlases/HarvardOxford/HarvardOxford-cort-maxprob-thr25-1mm.nii.gz"
ATLAS_SUBCORTICAL="/lustrehome/emanueleamato/fsl/data/atlases/HarvardOxford/HarvardOxford-sub-maxprob-thr25-1mm.nii.gz"
MNI_REF="/lustrehome/emanueleamato/fsl/data/standard/MNI152_T1_1mm.nii.gz"

# Creazione della directory di output principale
mkdir -p "$OUTPUT_DIR"

# Loop su ogni paziente presente nella directory di input
for PATIENT_DIR in "$INPUT_DIR"/*/; do
    PATIENT_ID=$(basename "$PATIENT_DIR")  # Estrai ID del paziente
    echo "Processing patient: $PATIENT_ID"

    # Definizione dei file di input
    DWI=$(find "$PATIENT_DIR" -maxdepth 1 -type f -name "*.nii.gz" | head -n 1)
    BVEC=$(find "$PATIENT_DIR" -maxdepth 1 -type f -name "*.bvec" | head -n 1)
    BVAL=$(find "$PATIENT_DIR" -maxdepth 1 -type f -name "*.bval" | head -n 1)


    # Definizione della cartella di output per il paziente
    OUT_PATIENT_DIR="$OUTPUT_DIR/$PATIENT_ID"

    # Creazione delle sottocartelle di output
    mkdir -p "$OUT_PATIENT_DIR/preprocessing"
    mkdir -p "$OUT_PATIENT_DIR/dti_metrics"
    mkdir -p "$OUT_PATIENT_DIR/tractography"
    mkdir -p "$OUT_PATIENT_DIR/reports"
    mkdir -p "$OUT_PATIENT_DIR/ROIs"

    # Verifica dell'esistenza dei file di input
    for file in "$DWI" "$BVEC" "$BVAL" "$ATLAS" "$ATLAS_CORTICAL" "$ATLAS_SUBCORTICAL" "$MNI_REF"; do
        if [ ! -f "$file" ]; then
            echo "Errore: File $file non trovato per il paziente $PATIENT_ID!" >&2
            continue  # Passa al prossimo paziente
        fi
    done

    # ==========================
    # 1. Registrazione in MNI152
    # ==========================
    echo "[Step 1] Registrazione di DWI allo spazio MNI152 per $PATIENT_ID"
    flirt -in "$DWI" -ref "$MNI_REF" \
          -out "$OUT_PATIENT_DIR/preprocessing/dwi_mni152.nii.gz" -omat "$OUT_PATIENT_DIR/preprocessing/dwi2mni.mat" -dof 12

    # ==========================
    # 2. Generazione delle ROI
    # ==========================
    echo "[Step 2] Creazione delle ROI corticali e subcorticali per $PATIENT_ID"
    ROI_DIR="$OUT_PATIENT_DIR/ROIs"

    for ((i=1; i<=48; i++)); do 
        fslmaths "$ATLAS_CORTICAL" -thr $i -uthr $i -bin "$ROI_DIR/Cortical_${i}.nii.gz" 
    done 

    for ((i=1; i<=21; i++)); do 
        fslmaths "$ATLAS_SUBCORTICAL" -thr $i -uthr $i -bin "$ROI_DIR/Subcortical_${i}.nii.gz" 
    done 

    # ==========================
    # 3. Preprocessing DWI
    # ==========================
    echo "[Step 3] Correzione artefatti con MRtrix3 (dwifslpreproc) per $PATIENT_ID"
    dwifslpreproc "$OUT_PATIENT_DIR/preprocessing/dwi_mni152.nii.gz" "$OUT_PATIENT_DIR/preprocessing/dwi_preprocessed.mif" \
        -fslgrad "$BVEC" "$BVAL" -pe_dir AP -rpe_none -cuda -eddy_options "--repol"

    # Creazione maschera cerebrale
    echo "[Step 4] Creazione della maschera cerebrale per $PATIENT_ID"
    dwi2mask "$OUT_PATIENT_DIR/preprocessing/dwi_preprocessed.mif" "$OUT_PATIENT_DIR/preprocessing/mask.mif"

    # ==========================
    # 4. Modellizzazione della diffusione
    # ==========================
    echo "[Step 5] Calcolo del tensore di diffusione per $PATIENT_ID"
    dwi2tensor "$OUT_PATIENT_DIR/preprocessing/dwi_preprocessed.mif" "$OUT_PATIENT_DIR/dti_metrics/dti.mif"
    tensor2metric "$OUT_PATIENT_DIR/dti_metrics/dti.mif" -fa "$OUT_PATIENT_DIR/dti_metrics/fa.mif" -adc "$OUT_PATIENT_DIR/dti_metrics/md.mif"

    # ==========================
    # 5. Trattografia
    # ==========================
    echo "[Step 6] Tractografia probabilistica con iFOD2 per $PATIENT_ID"
    dwi2response tournier "$OUT_PATIENT_DIR/preprocessing/dwi_preprocessed.mif" "$OUT_PATIENT_DIR/tractography/response.txt"
    dwi2fod msmt_csd "$OUT_PATIENT_DIR/preprocessing/dwi_preprocessed.mif" "$OUT_PATIENT_DIR/tractography/response.txt" "$OUT_PATIENT_DIR/tractography/fod.mif"
    tckgen "$OUT_PATIENT_DIR/tractography/fod.mif" "$OUT_PATIENT_DIR/tractography/tracts.tck" -act "$OUT_PATIENT_DIR/preprocessing/mask.mif" -seed_dynamic "$OUT_PATIENT_DIR/tractography/fod.mif" -select 1000000 -algorithm iFOD2

    # ==========================
    # 6. Report Finale
    # ==========================
    echo "[Step 7] Generazione report finale per $PATIENT_ID"
    touch "$OUT_PATIENT_DIR/reports/pipeline_summary.txt"
    echo "Pipeline DWI completata con successo per $PATIENT_ID! I risultati si trovano in $OUT_PATIENT_DIR"

done

echo "Tutti i pazienti sono stati processati con successo!"
