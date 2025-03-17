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
ATLAS_CORTICAL="/lustrehome/emanueleamato/fsl/data/atlases/HarvardOxford/HarvardOxford-cort-maxprob-thr0-1mm.nii.gz"
ATLAS_SUBCORTICAL="/lustrehome/emanueleamato/fsl/data/atlases/HarvardOxford/HarvardOxford-sub-maxprob-thr0-1mm.nii.gz"
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
    for file in "$DWI" "$BVEC" "$BVAL"; do
        if [ ! -f "$file" ]; then
            echo "Errore: File $file non trovato per il paziente $PATIENT_ID!" >&2
            exit 1
        fi
    done

    # Creazione delle directory specifiche per ogni paziente
    OUT_PATIENT_DIR="$OUTPUT_DIR/$PATIENT_ID"
    mkdir -p "$OUT_PATIENT_DIR"/{preprocessing,dti_metrics,tractography,reports,ROIs}

# ===============================================================================================================================

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

# ===============================================================================================================================

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

# ===============================================================================================================================

    # ==========================
    # 3. Modellizzazione della diffusione
    # ==========================
    echo "[Step 3] Calcolo del tensore di diffusione per $PATIENT_ID"
    "$MRTRIX_BIN/dwi2tensor" "$OUT_PATIENT_DIR/preprocessing/dwi_preprocessed.mif" "$OUT_PATIENT_DIR/dti_metrics/dti.mif"
    "$MRTRIX_BIN/tensor2metric" "$OUT_PATIENT_DIR/dti_metrics/dti.mif" -fa "$OUT_PATIENT_DIR/dti_metrics/fa.mif" -adc        "$OUT_PATIENT_DIR/dti_metrics/md.mif"

# ===============================================================================================================================

    # ==========================
    # 4. Trattografia basata su FODs (CSD/MSMT-CSD)
    # ==========================
    echo "[Step 4] Trattografia basata su FODs per $PATIENT_ID"
    
    SHELL_COUNT=$("$MRTRIX_BIN/mrinfo" "$OUT_PATIENT_DIR/preprocessing/dwi_preprocessed.mif" \
    -shell_bvalues | tr ' ' '\n' | awk '$1>=50' | sort -n | uniq | wc -l)
    
    echo "Shell count robusto (escluso b=0): $SHELL_COUNT"
    
    if [ "$SHELL_COUNT" -ge 2 ]; then
        echo "Usando il metodo Dhollander per la risposta multi-shell..."
        "$MRTRIX_BIN/dwi2response" dhollander "$OUT_PATIENT_DIR/preprocessing/dwi_preprocessed.mif" \
            "$OUT_PATIENT_DIR/tractography/response_wm_fod.txt" \
            "$OUT_PATIENT_DIR/tractography/response_gm_fod.txt" \
            "$OUT_PATIENT_DIR/tractography/response_csf_fod.txt" -force
    else
        echo "Usando il metodo Tournier per la risposta single-shell..."
        "$MRTRIX_BIN/dwi2response" tournier "$OUT_PATIENT_DIR/preprocessing/dwi_preprocessed.mif" \
            "$OUT_PATIENT_DIR/tractography/response_fod.txt" -force
    fi
    
    # 🔹 Creazione della maschera cerebrale per FODs
    echo "Creazione della maschera cerebrale per FODs..."
    "$MRTRIX_BIN/dwi2mask" "$OUT_PATIENT_DIR/preprocessing/dwi_preprocessed.mif" "$OUT_PATIENT_DIR/preprocessing/mask_fod.mif" -force
    
    # 🔹 Ricostruzione dei FODs
    if [ "$SHELL_COUNT" -ge 2 ]; then
        echo "Ricostruzione MSMT-CSD per più tessuti..."
        CUDA_VISIBLE_DEVICES=0 "$MRTRIX_BIN/dwi2fod" msmt_csd "$OUT_PATIENT_DIR/preprocessing/dwi_preprocessed.mif" \
            "$OUT_PATIENT_DIR/tractography/response_wm_fod.txt" "$OUT_PATIENT_DIR/tractography/fod_wm.mif" \
            "$OUT_PATIENT_DIR/tractography/response_gm_fod.txt" "$OUT_PATIENT_DIR/tractography/fod_gm.mif" \
            "$OUT_PATIENT_DIR/tractography/response_csf_fod.txt" "$OUT_PATIENT_DIR/tractography/fod_csf.mif" -force
        FOD_FILE="$OUT_PATIENT_DIR/tractography/fod_wm.mif"
    else
        echo "Ricostruzione CSD standard per single-shell..."
        CUDA_VISIBLE_DEVICES=0 "$MRTRIX_BIN/dwi2fod" csd "$OUT_PATIENT_DIR/preprocessing/dwi_preprocessed.mif" \
            "$OUT_PATIENT_DIR/tractography/response_fod.txt" "$OUT_PATIENT_DIR/tractography/fod.mif" -force
        FOD_FILE="$OUT_PATIENT_DIR/tractography/fod.mif"
    fi
    
    # 🔹 Generazione della trattografia probabilistica con iFOD2
    echo "Generazione della trattografia probabilistica con iFOD2..."
    "$MRTRIX_BIN/tckgen" "$FOD_FILE" "$OUT_PATIENT_DIR/tractography/tracts_fod.tck" \
        -seed_dynamic "$FOD_FILE" \
        -mask "$OUT_PATIENT_DIR/preprocessing/mask_fod.mif" \
        -select 1000000 -algorithm iFOD2 -force

# ===============================================================================================================================
    # ==========================
    # 5 Registrazione delle ROI 
    # ==========================
    
    echo "[Step 5] Registrazione degli atlanti per $PATIENT_ID"

    NUM_CORTICAL=$(fslstats "$ATLAS_CORTICAL" -R | awk '{print int($2)}')
    NUM_SUBCORTICAL=$(fslstats "$ATLAS_SUBCORTICAL" -R | awk '{print int($2)}')
    
    echo "Numero di ROI Corticali: $NUM_CORTICAL"
    echo "Numero di ROI Subcorticali: $NUM_SUBCORTICAL"

    echo "[Step 5] Registrazione degli atlanti per $PATIENT_ID"
    
    ROI_DIR="${OUT_PATIENT_DIR%/}/ROIs"
    mkdir -p "$ROI_DIR/cortical" "$ROI_DIR/subcortical"
    
    # Creazione ROI separate per l'atlante corticale
    for ((i=1; i<=NUM_CORTICAL; i++)); do 
        "$MRTRIX_BIN/mrcalc" "$ATLAS_CORTICAL" $i -eq "$ROI_DIR/cortical/Cortical_${i}.nii.gz" -force
    done 
    
    # Creazione ROI separate per l'atlante subcorticale
    for ((i=1; i<=NUM_SUBCORTICAL; i++)); do 
        "$MRTRIX_BIN/mrcalc" "$ATLAS_SUBCORTICAL" $i -eq "$ROI_DIR/subcortical/Subcortical_${i}.nii.gz" -force
    done 
    
    echo "ROI separate create per $PATIENT_ID"

#===============================================================================================================================

    # ==========================
    # 6 Generazione delle Matrici di Connettività Separate
    # ==========================
    
    echo "[Step 6] Generazione della matrice di connettività per $PATIENT_ID"
    
    MATRIX_CORTICAL="$OUT_PATIENT_DIR/connectivity_matrix_cortical.csv"
    MATRIX_SUBCORTICAL="$OUT_PATIENT_DIR/connectivity_matrix_subcortical.csv"
    ASSIGNMENTS_OUTPUT="$OUT_PATIENT_DIR/connectivity_assignments.csv"
    
    # Controllo se la trattografia è stata generata
    TRACT_FILE="$OUT_PATIENT_DIR/tractography/tracts_fod.tck"
    if [ ! -f "$TRACT_FILE" ]; then
        echo "❌ Errore: Il file di trattografia non esiste in $OUT_PATIENT_DIR/tractography! Controlla il preprocessing." >&2
        continue
    fi
    
    # Generazione della matrice di connettività per il corticale
    "$MRTRIX_BIN/tck2connectome" "$TRACT_FILE" "$ATLAS_CORTICAL" "$MATRIX_CORTICAL" \
        -symmetric -scale_invnodevol -stat_edge mean -out_assignments "$ASSIGNMENTS_OUTPUT" -force
    
    # Generazione della matrice di connettività per il subcorticale
    "$MRTRIX_BIN/tck2connectome" "$TRACT_FILE" "$ATLAS_SUBCORTICAL" "$MATRIX_SUBCORTICAL" \
        -symmetric -scale_invnodevol -stat_edge mean -out_assignments "$ASSIGNMENTS_OUTPUT" -force
    
    echo "✅ Matrici di connettività salvate come:"
    echo "   - $MATRIX_CORTICAL"
    echo "   - $MATRIX_SUBCORTICAL"


# ===============================================================================================================================


    # ==========================
    # Generazione del Report Finale per il paziente
    # ===========================
    
    REPORT_FILE="$OUT_PATIENT_DIR/reports/pipeline_report.txt"
    {
        echo "========================================="
        echo "   PIPELINE DWI - REPORT FINALE"
        echo "========================================="
        echo "Paziente: $PATIENT_ID"
        echo "Data elaborazione: $(date)"
        echo ""
        echo "➤ Step 1: Registrazione su MNI152 completata."
        echo "    - Volume b0 estratto e registrato su spazio MNI152."
        echo "    - Matrice di trasformazione salvata."
        echo ""
        echo "➤ Step 2: Preprocessing DWI eseguito con dwifslpreproc."
        echo ""
        echo "➤ Step 3: Calcolo del tensore di diffusione completato."
        echo "    - Mappe FA e MD generate."
        echo ""
        echo "➤ Step 4: Trattografia eseguita con metodo $(if [ "$SHELL_COUNT" -ge 2 ]; then echo 'MSMT-CSD'; else echo 'CSD'; fi)."
        echo "    - ROI mask generata."
        echo "    - Trattografia generata con iFOD2."
        echo ""
        echo "➤ Step 5: Registrazione Atlanti Harvard-Oxford."
        echo "    - Numero ROI corticali: $NUM_CORTICAL"
        echo "    - Numero ROI subcorticali: $NUM_SUBCORTICAL"
        echo "    - ROI segmentate salvate in $ROI_DIR."
        echo ""
        echo "➤ Step 6: Matrici di connettività create."
        echo "    - Matrice corticale: $MATRIX_CORTICAL"
        echo "    - Matrice subcorticale: $MATRIX_SUBCORTICAL"
        echo "    - File di assegnazione: $ASSIGNMENTS_OUTPUT"
        echo ""
        echo "✅ Elaborazione completata per $PATIENT_ID!"
        echo "========================================="
    } > "$REPORT_FILE"

echo "📄 Report salvato in: $REPORT_FILE"

done

#===============================================================================================================================

echo "✅ Processo completato per tutti i soggetti!"

    


