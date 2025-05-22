#!/bin/bash

set -euo pipefail

MRTRIX_BIN="/lustrehome/alacalamita/.conda/envs/fsl_env/bin"
PROCESSED_DIR="/lustrehome/alacalamita/Test_Imm/Proc_Im"
ATLAS_COMPLETE="/lustrehome/alacalamita/Test_Imm/HarvardOxford-cort.nii"

export HOME="$(mktemp -d)"
export FSLDIR=/lustrehome/alacalamita/fsl        # o dov’è il tuo FSL
source $FSLDIR/etc/fslconf/fsl.sh
export PATH=$FSLDIR/bin:$PATH


for TRACT_FILE in $(find "$PROCESSED_DIR" -name "tracts.tck"); do

    PATIENT_DIR=$(dirname "$(dirname "$TRACT_FILE")")
    PATIENT_ID=$(basename "$PATIENT_DIR")
    echo "🔁 [$PATIENT_ID] Processing..."

    # Ora OUTDIR è specifico per ogni paziente
    OUTDIR="/lustrehome/alacalamita/Test_Imm/block_connectome/final/${PATIENT_ID}"
    mkdir -p "$OUTDIR"

    echo "🧭 Conversione atlante nello spazio tract..."
    REFERENCE="$PATIENT_DIR/preprocessing/dwi_preprocessed.mif"

    "$MRTRIX_BIN/mrconvert" "$ATLAS_COMPLETE" \
        -datatype uint32 -force "$OUTDIR/atlas_130_tmp.mif"

    "$MRTRIX_BIN/mrtransform" "$OUTDIR/atlas_130_tmp.mif" \
        -template "$REFERENCE" -interp nearest -force "$OUTDIR/atlas_130_aligned.mif"

    rm "$OUTDIR/atlas_130_tmp.mif"

    echo "📊 Generazione matrice 130x130 (conteggio streamline, diagonale a 0)..."
    "$MRTRIX_BIN/tck2connectome" "$TRACT_FILE" "$OUTDIR/atlas_130_aligned.mif" \
        "$OUTDIR/connectivity_matrix_complete.csv" \
        -zero_diagonal \
        -out_assignments "$OUTDIR/assignments.csv" \
        -force

    
    echo "✅ [$PATIENT_ID] COMPLETATO"
done

echo "🏁 Tutti i pazienti processati correttamente."
