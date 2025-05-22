#!/bin/bash

# ==========================
# Pipeline DWI - Versione 2025 - Refactored per uso di un solo atlante
# ==========================

# echo "Partito!" >> /lustrehome/alacalamita/Test_Imm/Log.txt

set -euo pipefail  # Esci subito in caso di errore

# Definizione del path assoluto di MRtrix3
MRTRIX_BIN="/lustrehome/alacalamita/.conda/envs/fsl_env/bin"

# Threads per il MultiThreading 
export MRTRIX_NTHREADS=16 
echo "Numero di CPU disponibili: $(nproc)"

# Verifica che MRtrix3 sia accessibile
if [ ! -x "$MRTRIX_BIN/dwifslpreproc" ]; then
    echo "Errore: MRtrix3 non trovato nell'ambiente specificato ($MRTRIX_BIN)!" >&2
    exit 1
fi

echo "Usando MRtrix3 da: $MRTRIX_BIN"

# Controllo parametri
if [ "$#" -ne 3 ]; then
    echo "Uso: $0 <input_directory> <output_directory> <atlas_file>" >&2
    exit 1
fi

INPUT_DIR="$1"
OUTPUT_DIR="$2"
ATLAS="$3"

# Controlla che la directory di input esista
if [ ! -d "$INPUT_DIR" ]; then
    echo "Errore: La directory di input $INPUT_DIR non esiste!" >&2
    exit 1
fi

# Controlla che l'atlas esista
if [ ! -f "$ATLAS" ]; then
    echo "Errore: L'atlas $ATLAS non esiste!" >&2
    exit 1
fi

mkdir -p "$OUTPUT_DIR" || { echo "Errore: Impossibile creare la directory di output $OUTPUT_DIR"; exit 1; }
export HOME="$(mktemp -d)"

export FSLDIR=/lustrehome/alacalamita/fsl        # o dov’è il tuo FSL
source $FSLDIR/etc/fslconf/fsl.sh
export PATH=$FSLDIR/bin:$PATH


# Loop su ogni paziente
# for PATIENT_DIR in "$INPUT_DIR"/*/; do
    PATIENT_DIR="$1"
    PATIENT_ID=$(basename "$PATIENT_DIR")
    echo "Processing patient: $PATIENT_ID"

    DWI=$(find "$PATIENT_DIR" -maxdepth 1 -type f -name "*.nii.gz" | head -n 1)
    BVEC=$(find "$PATIENT_DIR" -maxdepth 1 -type f -name "*.bvec" | head -n 1)
    BVAL=$(find "$PATIENT_DIR" -maxdepth 1 -type f -name "*.bval" | head -n 1)

    for file in "$DWI" "$BVEC" "$BVAL"; do
        if [ ! -f "$file" ]; then
            echo "Errore: File $file non trovato per il paziente $PATIENT_ID!" >&2
            exit 1
        fi
    done

    OUT_PATIENT_DIR="$OUTPUT_DIR/$PATIENT_ID"
    mkdir -p "$OUT_PATIENT_DIR"/{preprocessing,dti_metrics,tractography,reports,ROIs}


    # ===============================================================================================================================

    # ==========================
    # 1. Estrazione primo volume (b0) e Registrazione su MNI152
    # ==========================

    echo "[Step 1] Estrazione del b0 e registrazione su atlas per $PATIENT_ID"
    "$MRTRIX_BIN/mrconvert" "$DWI" "$OUT_PATIENT_DIR/preprocessing/dwi_b0.nii.gz" -coord 3 0

    flirt -in "$OUT_PATIENT_DIR/preprocessing/dwi_b0.nii.gz" -ref "$ATLAS" \
        -out "$OUT_PATIENT_DIR/preprocessing/dwi_b0_registered.nii.gz" -omat "$OUT_PATIENT_DIR/preprocessing/dwi2atlas.mat" -dof 12

    applywarp --ref="$ATLAS" \
        --in="$DWI" \
        --out="$OUT_PATIENT_DIR/preprocessing/dwi_registered.nii.gz" \
        --premat="$OUT_PATIENT_DIR/preprocessing/dwi2atlas.mat"

     # ===============================================================================================================================


    # ==========================
    # 2. Preprocessing DWI
    # ==========================
    
    echo "[Step 2] Preprocessing con dwifslpreproc per $PATIENT_ID"
    if ! CUDA_VISIBLE_DEVICES=0 "$MRTRIX_BIN/dwifslpreproc" "$OUT_PATIENT_DIR/preprocessing/dwi_registered.nii.gz" \
            "$OUT_PATIENT_DIR/preprocessing/dwi_preprocessed.mif" -fslgrad "$BVEC" "$BVAL" -pe_dir AP -rpe_none \
            -eddy_options "'--repol'"; then
        echo "Errore: dwifslpreproc fallito per $PATIENT_ID!" >&2
        exit 1
    fi

    # ===============================================================================================================================

    # ==========================
    # 3. Modellizzazione della diffusione
    # ==========================

    echo "[Step 3] Modellizzazione della diffusione per $PATIENT_ID"
    "$MRTRIX_BIN/dwi2tensor" "$OUT_PATIENT_DIR/preprocessing/dwi_preprocessed.mif" "$OUT_PATIENT_DIR/dti_metrics/dti.mif"
    "$MRTRIX_BIN/tensor2metric" "$OUT_PATIENT_DIR/dti_metrics/dti.mif" -fa "$OUT_PATIENT_DIR/dti_metrics/fa.mif" -adc "$OUT_PATIENT_DIR/dti_metrics/md.mif"

    # ===============================================================================================================================



    echo "[Step 4] Trattografia con FODs per $PATIENT_ID"
    SHELL_COUNT=$("$MRTRIX_BIN/mrinfo" "$OUT_PATIENT_DIR/preprocessing/dwi_preprocessed.mif" -shell_bvalues | tr ' ' '\n' | awk '$1>=50' | sort -n | uniq | wc -l)

    if [ "$SHELL_COUNT" -ge 2 ]; then
        "$MRTRIX_BIN/dwi2response" dhollander "$OUT_PATIENT_DIR/preprocessing/dwi_preprocessed.mif" \
            "$OUT_PATIENT_DIR/tractography/response_wm.txt" \
            "$OUT_PATIENT_DIR/tractography/response_gm.txt" \
            "$OUT_PATIENT_DIR/tractography/response_csf.txt" -force
    else
        "$MRTRIX_BIN/dwi2response" tournier "$OUT_PATIENT_DIR/preprocessing/dwi_preprocessed.mif" \
            "$OUT_PATIENT_DIR/tractography/response.txt" -force
    fi

    "$MRTRIX_BIN/dwi2mask" "$OUT_PATIENT_DIR/preprocessing/dwi_preprocessed.mif" "$OUT_PATIENT_DIR/preprocessing/mask.mif" -force

    if [ "$SHELL_COUNT" -ge 2 ]; then
        CUDA_VISIBLE_DEVICES=0 "$MRTRIX_BIN/dwi2fod" msmt_csd "$OUT_PATIENT_DIR/preprocessing/dwi_preprocessed.mif" \
            "$OUT_PATIENT_DIR/tractography/response_wm.txt" "$OUT_PATIENT_DIR/tractography/fod_wm.mif" \
            "$OUT_PATIENT_DIR/tractography/response_gm.txt" "$OUT_PATIENT_DIR/tractography/fod_gm.mif" \
            "$OUT_PATIENT_DIR/tractography/response_csf.txt" "$OUT_PATIENT_DIR/tractography/fod_csf.mif" -force
        FOD_FILE="$OUT_PATIENT_DIR/tractography/fod_wm.mif"
    else
        CUDA_VISIBLE_DEVICES=0 "$MRTRIX_BIN/dwi2fod" csd "$OUT_PATIENT_DIR/preprocessing/dwi_preprocessed.mif" \
            "$OUT_PATIENT_DIR/tractography/response.txt" "$OUT_PATIENT_DIR/tractography/fod.mif" -force
        FOD_FILE="$OUT_PATIENT_DIR/tractography/fod.mif"
    fi

    "$MRTRIX_BIN/tckgen" "$FOD_FILE" "$OUT_PATIENT_DIR/tractography/tracts.tck" \
        -seed_dynamic "$FOD_FILE" \
        -mask "$OUT_PATIENT_DIR/preprocessing/mask.mif" \
        -select 1000000 -algorithm iFOD2 -force


    

    REPORT_FILE="$OUT_PATIENT_DIR/reports/pipeline_report.txt"
    {
        echo "========================================="
        echo "   PIPELINE DWI - REPORT FINALE"
        echo "========================================="
        echo "Paziente: $PATIENT_ID"
        echo "Data elaborazione: $(date)"
        echo ""
        echo "➤ Step 1: Registrazione su atlas completata."
        echo "➤ Step 2: Preprocessing eseguito."
        echo "➤ Step 3: DTI completato."
        echo "➤ Step 4: Trattografia generata."
        echo "✅ Elaborazione completata per $PATIENT_ID!"
    } > "$REPORT_FILE"

    echo "📄 Report salvato in: $REPORT_FILE"
# done

# echo "✅ Processo completato per tutti i soggetti!"

chmod -R a+x "$OUTPUT_DIR"
