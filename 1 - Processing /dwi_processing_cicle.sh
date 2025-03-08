#!/bin/bash

# ==========================
# Pipeline DWI - Versione 2025 - Refactory update
# ==========================

set -euo pipefail  # Esci subito in caso di errore

# Definizione del path assoluto di MRtrix3
MRTRIX_BIN="/lustrehome/emanueleamato/.conda/envs/tbi_dwi_py310/bin"

# Verifica che MRtrix3 sia accessibile
if [ ! -x "$MRTRIX_BIN/dwifslpreproc" ]; then
    echo "Errore: MRtrix3 non trovato nell'ambiente specificato ($MRTRIX_BIN)!" >&2
    exit 1
fi

echo "Usando MRtrix3 da: $MRTRIX_BIN"

# Controllo parametri
if [ "$#" -ne 2 ]; then
    echo "Uso: $0 <input_directory> <output_directory>" >&2
    exit 1
fi

INPUT_DIR="$1"
OUTPUT_DIR="$2"

# Controlla che la directory di input esista
if [ ! -d "$INPUT_DIR" ]; then
    echo "Errore: La directory di input $INPUT_DIR non esiste!" >&2
    exit 1
fi

# Crea la directory di output se non esiste
mkdir -p "$OUTPUT_DIR" || { echo "Errore: Impossibile creare la directory di output $OUTPUT_DIR"; exit 1; }

# Definizione degli atlanti e riferimenti
ATLAS="/lustrehome/emanueleamato/fsl/data/standard/MNI152_T1_1mm.nii.gz"
ATLAS_CORTICAL="/lustrehome/emanueleamato/fsl/data/atlases/HarvardOxford/HarvardOxford-cort-maxprob-thr25-1mm.nii.gz"
ATLAS_SUBCORTICAL="/lustrehome/emanueleamato/fsl/data/atlases/HarvardOxford/HarvardOxford-sub-maxprob-thr25-1mm.nii.gz"
MNI_REF="/lustrehome/emanueleamato/fsl/data/standard/MNI152_T1_1mm.nii.gz"

# Loop su ogni paziente
for PATIENT_DIR in "$INPUT_DIR"/*/; do
    PATIENT_ID=$(basename "$PATIENT_DIR")
    echo "Processing patient: $PATIENT_ID"

    # Definizione dei file di input
    DWI=$(find "$PATIENT_DIR" -maxdepth 1 -type f -name "*.nii.gz" | head -n 1)
    BVEC=$(find "$PATIENT_DIR" -maxdepth 1 -type f -name "*.bvec" | head -n 1)
    BVAL=$(find "$PATIENT_DIR" -maxdepth 1 -type f -name "*.bval" | head -n 1)

    # Controlla se i file esistono
    for file in "$DWI" "$BVEC" "$BVAL" "$ATLAS" "$ATLAS_CORTICAL" "$ATLAS_SUBCORTICAL" "$MNI_REF"; do
        if [ ! -f "$file" ]; then
            echo "Errore: File $file non trovato per il paziente $PATIENT_ID!" >&2
            exit 1
        fi
    done

    # Creazione cartelle di output
    OUT_PATIENT_DIR="$OUTPUT_DIR/$PATIENT_ID"
    mkdir -p "$OUT_PATIENT_DIR"/{preprocessing,dti_metrics,tractography,reports,ROIs}

    # ==========================
    # 1. Estrazione primo volume (b0) e Registrazione su MNI152
    # ==========================
    echo "[Step 1] Estrazione del primo volume (b0) e registrazione su MNI152 per $PATIENT_ID"

    # Barra di progresso per estrazione b0
	echo "  → Estrazione primo volume (b0)..."
	"$MRTRIX_BIN/mrconvert" "$DWI" "$OUT_PATIENT_DIR/preprocessing/dwi_b0.nii.gz" -coord 3 0

	echo "  → Registrazione con FLIRT..."
	flirt -in "$OUT_PATIENT_DIR/preprocessing/dwi_b0.nii.gz" -ref "$MNI_REF" \
       -out "$OUT_PATIENT_DIR/preprocessing/dwi_b0_mni.nii.gz" -omat "$OUT_PATIENT_DIR/preprocessing/dwi2mni.mat" -dof 12

	echo "  → Applicazione trasformazione all'intera immagine 4D..."
	applywarp --ref="$MNI_REF" \
       		  --in="$DWI" \
                  --out="$OUT_PATIENT_DIR/preprocessing/dwi_mni152.nii.gz" \
                  --premat="$OUT_PATIENT_DIR/preprocessing/dwi2mni.mat"

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
    if ! "$MRTRIX_BIN/dwifslpreproc" "$OUT_PATIENT_DIR/preprocessing/dwi_mni152.nii.gz" "$OUT_PATIENT_DIR/preprocessing/dwi_preprocessed.mif" \
        -fslgrad "$BVEC" "$BVAL" -pe_dir AP -rpe_none -eddy_options \"--repol\"; then
        echo "Errore: dwifslpreproc fallito per $PATIENT_ID!" >&2
        exit 1
    fi

    # ==========================
    # 4. Modellizzazione della diffusione
    # ==========================
    echo "[Step 4] Calcolo del tensore di diffusione per $PATIENT_ID"
    "$MRTRIX_BIN/dwi2tensor" "$OUT_PATIENT_DIR/preprocessing/dwi_preprocessed.mif" "$OUT_PATIENT_DIR/dti_metrics/dti.mif"
    "$MRTRIX_BIN/tensor2metric" "$OUT_PATIENT_DIR/dti_metrics/dti.mif" -fa "$OUT_PATIENT_DIR/dti_metrics/fa.mif" -adc "$OUT_PATIENT_DIR/dti_metrics/md.mif"

    # ==========================
    # 5. Trattografia
    # ==========================
    echo "[Step 5] Tractografia probabilistica con iFOD2 per $PATIENT_ID"
    "$MRTRIX_BIN/dwi2response" tournier "$OUT_PATIENT_DIR/preprocessing/dwi_preprocessed.mif" "$OUT_PATIENT_DIR/tractography/response.txt"
    "$MRTRIX_BIN/dwi2fod" msmt_csd "$OUT_PATIENT_DIR/preprocessing/dwi_preprocessed.mif" "$OUT_PATIENT_DIR/tractography/response.txt" "$OUT_PATIENT_DIR/tractography/fod.mif"
    "$MRTRIX_BIN/tckgen" "$OUT_PATIENT_DIR/tractography/fod.mif" "$OUT_PATIENT_DIR/tractography/tracts.tck" \
        -act "$OUT_PATIENT_DIR/preprocessing/mask.mif" -seed_dynamic "$OUT_PATIENT_DIR/tractography/fod.mif" -select 1000000 -algorithm iFOD2

    echo "Pipeline DWI completata con successo per $PATIENT_ID!"

done

echo "Tutti i pazienti sono stati processati con successo!"

