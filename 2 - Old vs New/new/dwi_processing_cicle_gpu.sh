#!/bin/bash

# ==========================
# Pipeline DWI - Versione 2025 - Refactory update
# ==========================

set -euo pipefail  # Esci subito in caso di errore

# Definizione del path assoluto di MRtrix3
MRTRIX_BIN="/lustrehome/emanueleamato/.conda/envs/tbi_dwi_py310/bin"

# Threads per il MultiThreading 
export MRTRIX_NTHREADS=128 
echo "Numero di CPU disponibili: $(nproc)"

# Verifica che MRtrix3 sia accessibile
if [ ! -x "$MRTRIX_BIN/dwifslpreproc" ]; then
    echo "Errore: MRtrix3 non trovato nell'ambiente specificato ($MRTRIX_BIN)!" >&2
    exit 1
fi

echo "Usando MRtrix3 da: $MRTRIX_BIN"

# Imposta il numero di threads per MRtrix3
export MRTRIX_NTHREADS=128  # Puoi aumentare se hai più CPU
echo "Numero di CPU disponibili: $(nproc)"

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

# Creazione dinamica della directory di output
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
    export MRTRIX_NTHREADS=64

    # Definizione dei file di input
    DWI=$(find "$PATIENT_DIR" -maxdepth 1 -type f -name "*.nii.gz" | head -n 1)
    BVEC=$(find "$PATIENT_DIR" -maxdepth 1 -type f -name "*.bvec" | head -n 1)
    BVAL=$(find "$PATIENT_DIR" -maxdepth 1 -type f -name "*.bval" | head -n 1)

    # Controlla se i file esistono
    for file in "$DWI" "$BVEC" "$BVAL"; do
        if [ ! -f "$file" ]; then
            echo "Errore: File $file non trovato per il paziente $PATIENT_ID!" >&2
            exit 1
        fi
    done

    # Creazione delle directory specifiche per ogni paziente
    OUT_PATIENT_DIR="$OUTPUT_DIR/$PATIENT_ID"
    mkdir -p "$OUT_PATIENT_DIR"/{preprocessing,dti_metrics,tractography,reports,ROIs}

    # ==========================
    # 1. Estrazione primo volume (b0) e Registrazione su MNI152
    # ==========================
    echo "[Step 1] Estrazione del primo volume (b0) e registrazione su MNI152 per $PATIENT_ID"

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
    # 2. Preprocessing DWI
    # ==========================
    echo "[Step 2] Correzione artefatti con MRtrix3 (dwifslpreproc) per $PATIENT_ID"
    if ! CUDA_VISIBLE_DEVICES=0 "$MRTRIX_BIN/dwifslpreproc" "$OUT_PATIENT_DIR/preprocessing/dwi_mni152.nii.gz" \
            "$OUT_PATIENT_DIR/preprocessing/dwi_preprocessed.mif" -fslgrad "$BVEC" "$BVAL" -pe_dir AP -rpe_none \
            -eddy_options "'--repol'"; then
        echo "Errore: dwifslpreproc fallito per $PATIENT_ID!" >&2
        exit 1
    fi

    # ==========================
    # 3. Modellizzazione della diffusione
    # ==========================
    echo "[Step 3] Calcolo del tensore di diffusione per $PATIENT_ID"
    "$MRTRIX_BIN/dwi2tensor" "$OUT_PATIENT_DIR/preprocessing/dwi_preprocessed.mif" "$OUT_PATIENT_DIR/dti_metrics/dti.mif"
    "$MRTRIX_BIN/tensor2metric" "$OUT_PATIENT_DIR/dti_metrics/dti.mif" -fa "$OUT_PATIENT_DIR/dti_metrics/fa.mif" -adc     "$OUT_PATIENT_DIR/dti_metrics/md.mif"

    # ==========================
    # 4. Trattografia
    # ==========================
    echo "[Step 4] Trattografia probabilistica con iFOD2 per $PATIENT_ID"
    
    # 🔹 Determina se l'acquisizione è single-shell o multi-shell
    SHELL_COUNT=$("$MRTRIX_BIN/mrinfo" "$OUT_PATIENT_DIR/preprocessing/dwi_preprocessed.mif" -shell_bvalues | wc -w)
    
    if [ "$SHELL_COUNT" -gt 1 ]; then
        echo "Usando il metodo Dhollander per la risposta multi-shell..."
        "$MRTRIX_BIN/dwi2response" dhollander "$OUT_PATIENT_DIR/preprocessing/dwi_preprocessed.mif" \
            "$OUT_PATIENT_DIR/tractography/response_wm.txt" \
            "$OUT_PATIENT_DIR/tractography/response_gm.txt" \
            "$OUT_PATIENT_DIR/tractography/response_csf.txt"
    else
        echo "Usando il metodo Tournier per la risposta single-shell..."
        "$MRTRIX_BIN/dwi2response" tournier "$OUT_PATIENT_DIR/preprocessing/dwi_preprocessed.mif" \
            "$OUT_PATIENT_DIR/tractography/response.txt"
    fi
    
    # 🔹 Creazione della maschera cerebrale (per la trattografia)
    echo "[Step 5.1] Creazione della maschera cerebrale per $PATIENT_ID"
    "$MRTRIX_BIN/dwi2mask" "$OUT_PATIENT_DIR/preprocessing/dwi_preprocessed.mif" \
        "$OUT_PATIENT_DIR/preprocessing/mask.mif"
    
    # 🔹 Ricostruzione dei FODs (senza ACT, ma con maschera)
    if [ "$SHELL_COUNT" -gt 1 ]; then
        echo "Ricostruzione MSMT-CSD per più tessuti..."
        CUDA_VISIBLE_DEVICES=0 "$MRTRIX_BIN/dwi2fod" msmt_csd "$OUT_PATIENT_DIR/preprocessing/dwi_preprocessed.mif" \
            "$OUT_PATIENT_DIR/tractography/response_wm.txt" "$OUT_PATIENT_DIR/tractography/fod_wm.mif" \
            "$OUT_PATIENT_DIR/tractography/response_gm.txt" "$OUT_PATIENT_DIR/tractography/fod_gm.mif" \
            "$OUT_PATIENT_DIR/tractography/response_csf.txt" "$OUT_PATIENT_DIR/tractography/fod_csf.mif"
    else
        echo "Ricostruzione CSD standard per single-shell..."
        CUDA_VISIBLE_DEVICES=0 "$MRTRIX_BIN/dwi2fod" csd "$OUT_PATIENT_DIR/preprocessing/dwi_preprocessed.mif" \
            "$OUT_PATIENT_DIR/tractography/response.txt" "$OUT_PATIENT_DIR/tractography/fod.mif"
    fi
    
    # 🔹 Generazione della trattografia probabilistica con iFOD2 (senza ACT, con maschera)
    echo "[Step 5.2] Generazione dei tratti con iFOD2 per $PATIENT_ID"
    "$MRTRIX_BIN/tckgen" "$OUT_PATIENT_DIR/tractography/fod_wm.mif" "$OUT_PATIENT_DIR/tractography/tracts.tck" \
        -seed_dynamic "$OUT_PATIENT_DIR/tractography/fod_wm.mif" \
        -mask "$OUT_PATIENT_DIR/preprocessing/mask.mif" \
        -select 1000000 -algorithm iFOD2
    done

echo "Tutti i pazienti sono stati processati con successo!"