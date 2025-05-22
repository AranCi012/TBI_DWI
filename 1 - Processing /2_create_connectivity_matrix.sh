#!/bin/bash

set -euo pipefail


MRTRIX_BIN=""
PROCESSED_DIR=""
ATLAS_COMPLETE=""

for TRACT_FILE in $(find "$PROCESSED_DIR" -name "tracts.tck"); do
    PATIENT_DIR=$(dirname "$(dirname "$TRACT_FILE")")
    PATIENT_ID=$(basename "$PATIENT_DIR")
    echo "[$PATIENT_ID] Processing..."

    OUTDIR="/lustrehome/emanueleamato/TBI_DWI/test/$PATIENT_ID"
    mkdir -p "$OUTDIR"

    echo "Conversione atlante nello spazio tract..."
    REFERENCE="$PATIENT_DIR/preprocessing/dwi_preprocessed.mif"

    "$MRTRIX_BIN/mrconvert" "$ATLAS_COMPLETE" \
        -datatype uint32 -force "$OUTDIR/atlas_tmp.mif"

    "$MRTRIX_BIN/mrtransform" "$OUTDIR/atlas_tmp.mif" \
        -template "$REFERENCE" -interp nearest -force "$OUTDIR/atlas_aligned.mif"

    rm "$OUTDIR/atlas_tmp.mif"

    echo "Generazione matrice di connettività (zero diagonale)..."
    "$MRTRIX_BIN/tck2connectome" "$TRACT_FILE" "$OUTDIR/atlas_aligned.mif" \
        "$OUTDIR/connectivity_matrix.csv" \
        -zero_diagonal \
        -out_assignments "$OUTDIR/assignments.csv" \
        -force
done


    
    # =========================================================
    # NOTE PER FUTURE MODIFICHE:
    #
    # Se vuoi rigenerare matrici con altre opzioni:
    #
    # 1. Normalizzare rispetto al volume dei nodi:
    #    ➔ aggiungi:    -scale_invnodevol
    #
    #    Questo normalizza il valore delle connessioni per il volume delle regioni connesse.
    #
    # 2. Specificare come aggregare gli streamline:
    #    ➔ puoi aggiungere (SOLO UNO alla volta):
    #
    #    -stat_edge sum     # somma dei valori lungo gli streamline 
    #    -stat_edge mean    # media dei valori lungo gli streamline
    #    -stat_edge min     # minimo valore lungo gli streamline
    #    -stat_edge max     # massimo valore lungo gli streamline
    #
    #    ⚠️ Nelle versioni standard di MRtrix3 **NON esiste -stat_edge count**.
    #    Se lasci senza -stat_edge, MRtrix conta direttamente il numero di streamline.
    #
    # 3. Esempio combinato:
    #    "$MRTRIX_BIN/tck2connectome" ... \
    #        -scale_invnodevol -stat_edge mean -zero_diagonal ...
    #
    # =========================================================

    echo "[$PATIENT_ID] COMPLETATO"
done

echo "🏁 Tutti i pazienti processati correttamente."
