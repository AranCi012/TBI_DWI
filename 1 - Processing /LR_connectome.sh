#!/bin/bash

# ================================================
# Generazione Matrici di Connettività Emisferiche
# Corticale e Subcorticale - Modalità sequenziale
# ================================================

set -euo pipefail

# Path base
PROCESSED_DIR="processed_DWI"
MRTRIX_BIN="/lustrehome/emanueleamato/.conda/envs/tbi_dwi_py310/bin"
ATLAS_CORTICAL="/lustrehome/emanueleamato/fsl/data/atlases/HarvardOxford/HarvardOxford-cort-maxprob-thr0-1mm.nii.gz"
ATLAS_SUBCORTICAL="/lustrehome/emanueleamato/fsl/data/atlases/HarvardOxford/HarvardOxford-sub-maxprob-thr0-1mm.nii.gz"

# Funzione che elabora un paziente
process_patient() {
    local TRACT_FILE="$1"

    if [ ! -f "$TRACT_FILE" ]; then
        echo "❌ File .tck non trovato: $TRACT_FILE"
        return 1
    fi

    local PATIENT_DIR
    PATIENT_DIR=$(dirname "$(dirname "$TRACT_FILE")")
    local PATIENT_ID
    PATIENT_ID=$(basename "$PATIENT_DIR")

    echo "🔍 Processing $PATIENT_ID"

    local PREPROC="$PATIENT_DIR/preprocessing"
    local HEMI_DIR="$PATIENT_DIR/hemisphere_connectomes"
    mkdir -p "$HEMI_DIR"

    for ATLAS_TYPE in cortical subcortical; do
        if [ "$ATLAS_TYPE" == "cortical" ]; then
            ATLAS="$ATLAS_CORTICAL"
        else
            ATLAS="$ATLAS_SUBCORTICAL"
        fi

        if [ ! -f "$ATLAS" ]; then
            echo "⚠️  Atlante $ATLAS_TYPE non trovato: $ATLAS"
            continue
        fi

        # Calcolo dimensione X e punto centrale
        DIM_X=$(fslhd "$ATLAS" | awk '/^dim1/ {print int($2)}')
        HALF_X=$((DIM_X / 2))

        ROI_MASK_LEFT="$HEMI_DIR/left_${ATLAS_TYPE}_mask.nii.gz"
        ROI_MASK_RIGHT="$HEMI_DIR/right_${ATLAS_TYPE}_mask.nii.gz"
        ROI_ATLAS_LEFT="$HEMI_DIR/atlas_${ATLAS_TYPE}_left.nii.gz"
        ROI_ATLAS_RIGHT="$HEMI_DIR/atlas_${ATLAS_TYPE}_right.nii.gz"

        echo " → [$PATIENT_ID] Creazione maschere emisferiche ($ATLAS_TYPE)..."
        fslmaths "$ATLAS" -roi 0 $HALF_X 0 -1 0 -1 0 -1 "$ROI_MASK_LEFT"
        fslmaths "$ATLAS" -roi $HALF_X -1 0 -1 0 -1 0 -1 "$ROI_MASK_RIGHT"

        echo " → [$PATIENT_ID] Mascheramento atlante $ATLAS_TYPE..."
        fslmaths "$ATLAS" -mas "$ROI_MASK_LEFT" "$ROI_ATLAS_LEFT"
        fslmaths "$ATLAS" -mas "$ROI_MASK_RIGHT" "$ROI_ATLAS_RIGHT"

        echo " → [$PATIENT_ID] Generazione connettività $ATLAS_TYPE emisferica..."
        "$MRTRIX_BIN/tck2connectome" "$TRACT_FILE" "$ROI_ATLAS_LEFT" "$HEMI_DIR/connectivity_matrix_${ATLAS_TYPE}_left.csv" \
            -symmetric -scale_invnodevol -stat_edge mean -force

        "$MRTRIX_BIN/tck2connectome" "$TRACT_FILE" "$ROI_ATLAS_RIGHT" "$HEMI_DIR/connectivity_matrix_${ATLAS_TYPE}_right.csv" \
            -symmetric -scale_invnodevol -stat_edge mean -force
    done

    echo "✅ [$PATIENT_ID] Matrici emisferiche salvate in $HEMI_DIR"
}

# Loop sui pazienti
echo "📁 Scansione dei soggetti in $PROCESSED_DIR"
TCK_FILES=$(find "$PROCESSED_DIR" -type f -name "tracts_fod.tck")

if [ -z "$TCK_FILES" ]; then
    echo "❌ Nessun file tracts_fod.tck trovato!"
    exit 1
fi

for TCK_FILE in $TCK_FILES; do
    process_patient "$TCK_FILE"
done

echo "🏁 Completato per tutti i pazienti!"
