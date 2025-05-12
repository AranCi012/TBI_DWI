# README - Pipeline DWI Processing

## Descrizione Generale
Questa pipeline automatizza il preprocessing delle immagini di **Diffusion-Weighted Imaging (DWI)** per l'analisi della diffusione cerebrale. L'obiettivo principale è la correzione degli artefatti, la registrazione in spazio standard e la generazione di modelli di diffusione utili per la **tractografia probabilistica**.

Le immagini DWI sono sequenze di immagini **4D** (x, y, z, tempo), in cui il primo volume (**b0**) è un'immagine senza diffusione pesata, utilizzata come riferimento per la registrazione agli atlanti standard.

---

## Requisiti
### **Software Necessario**
- **MRtrix3** per il preprocessing e la tractografia
- **FSL** per la registrazione e la gestione degli atlanti
- **CUDA** per l'accelerazione del preprocessing su GPU (opzionale, ma consigliato)

Per installare l'ambiente corretto, consulta il [README dell'installazione](0-setup/setup.md).

### **Dati di Input**
- Immagini DWI in formato **NIfTI (`*.nii.gz`)**
- File di gradienti di diffusione **(`*.bvec` e `*.bval`)**
- Un **atlante cerebrale** per la registrazione spaziale

---

## 🚀 **Fasi della Pipeline**

### **1. Preprocessing DWI**

#### 1.1 Estrazione del primo volume (b0)
Il volume **b0** è utilizzato per la registrazione su spazio standard:
```bash
$MRTRIX_BIN/mrconvert "$DWI" "$OUT_PATIENT_DIR/preprocessing/dwi_b0.nii.gz" -coord 3 0
```

#### 1.2 Registrazione su spazio standard
Il volume b0 viene registrato sull'atlas fornito in input:
```bash
flirt -in "$OUT_PATIENT_DIR/preprocessing/dwi_b0.nii.gz" -ref "$ATLAS" \
      -out "$OUT_PATIENT_DIR/preprocessing/dwi_b0_registered.nii.gz" \
      -omat "$OUT_PATIENT_DIR/preprocessing/dwi2atlas.mat" -dof 12
```
Poi si applica la trasformazione all'intera DWI 4D:
```bash
applywarp --ref="$ATLAS" \
         --in="$DWI" \
         --out="$OUT_PATIENT_DIR/preprocessing/dwi_registered.nii.gz" \
         --premat="$OUT_PATIENT_DIR/preprocessing/dwi2atlas.mat"
```

#### 1.3 Correzione degli artefatti
```bash
CUDA_VISIBLE_DEVICES=0 $MRTRIX_BIN/dwifslpreproc \
  "$OUT_PATIENT_DIR/preprocessing/dwi_registered.nii.gz" \
  "$OUT_PATIENT_DIR/preprocessing/dwi_preprocessed.mif" \
  -fslgrad "$BVEC" "$BVAL" -pe_dir AP -rpe_none -eddy_options "'--repol'"
```

### **2. Modellizzazione della Diffusione**

#### 2.1 Calcolo del tensore e delle metriche
```bash
$MRTRIX_BIN/dwi2tensor "$OUT_PATIENT_DIR/preprocessing/dwi_preprocessed.mif" \
  "$OUT_PATIENT_DIR/dti_metrics/dti.mif"
$MRTRIX_BIN/tensor2metric "$OUT_PATIENT_DIR/dti_metrics/dti.mif" \
  -fa "$OUT_PATIENT_DIR/dti_metrics/fa.mif" \
  -adc "$OUT_PATIENT_DIR/dti_metrics/md.mif"
```

### **3. Trattografia probabilistica con iFOD2**
Le FOD (Fiber Orientation Distributions) sono stime della distribuzione delle direzioni delle fibre in ogni voxel di un'immagine di diffusione. Il modo in cui vengono calcolate dipende dal numero di shell nella sequenza di diffusione utilizzata.

Cosa significa "in base al numero di shell"?
Il numero di shell si riferisce ai diversi livelli di b-value usati nell'acquisizione dell'immagine di diffusione (DWI) [Si controllino i valori all'interno dei file bvec e bval]. I b-value definiscono l'intensità della diffusione misurata, e le acquisizioni possono essere:

- Single-shell (una sola b-value, ad esempio b = 1000 s/mm²)
- Multi-shell (più b-value, ad esempio b = 1000 e 3000 s/mm²)
- DENSE (diffusion spectrum imaging, DSI) con un ampio range di b-value

A seconda del numero di shell, vengono utilizzati modelli di ricostruzione diversi per ottenere le FOD:

1. Single-shell → Generalmente si utilizza il modello CSD (Constrained Spherical Deconvolution) classico.
2. Multi-shell → Si usa MSMT-CSD (Multi-Shell Multi-Tissue Constrained Spherical Deconvolution), che permette di distinguere più componenti, come la materia bianca, la materia grigia e il liquido cerebrospinale (CSF).
3. DENSE (DSI, Q-space methods) → Tecniche più avanzate come Q-ball imaging o diffusion spectrum imaging.

#### 3.1 Creazione della maschera cerebrale
```bash
$MRTRIX_BIN/dwi2mask "$OUT_PATIENT_DIR/preprocessing/dwi_preprocessed.mif" \
  "$OUT_PATIENT_DIR/preprocessing/mask.mif"
```

#### 3.2 Ricostruzione delle FOD
Il tipo di ricostruzione dipende dal numero di shell nei dati DWI (b-value multipli):
```bash
SHELL_COUNT=$($MRTRIX_BIN/mrinfo "$OUT_PATIENT_DIR/preprocessing/dwi_preprocessed.mif" -shell_bvalues | wc -w)
```
- Se multi-shell: usa MSMT-CSD
- Se single-shell: usa CSD

#### 3.3 Generazione della trattografia con iFOD2
```bash
$MRTRIX_BIN/tckgen "$FOD_FILE" "$OUT_PATIENT_DIR/tractography/tracts.tck" \
  -seed_dynamic "$FOD_FILE" \
  -mask "$OUT_PATIENT_DIR/preprocessing/mask.mif" \
  -select 1000000 -algorithm iFOD2
```

---

## 📊 Output della Pipeline
```
processed_DWI/
|-- sub-XXXX/
|   |-- preprocessing/
|   |   |-- dwi_registered.nii.gz
|   |   |-- dwi_preprocessed.mif
|   |   |-- mask.mif
|   |-- dti_metrics/
|   |   |-- fa.mif
|   |   |-- md.mif
|   |-- tractography/
|   |   |-- fod_wm.mif (o fod.mif)
|   |   |-- tracts.tck
|   |-- reports/
|   |   |-- pipeline_report.txt
```

## Esecuzione
```bash
./dwi_processing_pipeline.sh <input_dir> <output_dir> <atlas_file>
```
Esempio:
```bash
./dwi_processing_pipeline.sh raw_DWI processed_DWI /path/to/MNI152_T1_1mm.nii.gz
```

---

## Debugging e Problemi Comuni
- **File mancanti** → `.nii.gz`, `.bvec`, `.bval` obbligatori
- **Errore di registrazione** → b0 assente o non corretto
- **Mismatch tra gradienti e volumi** → verifica `bvec`, `bval`
- **GPU non rilevata** → controlla con `nvidia-smi`
- **Permission denied** → directory non scrivibile

---

## Autore
**Emanuele Amato**  
emanuele.amato@uniba.it  
eamato@ethz.ch  

---

## Curiosità

**Lo sapevi che in Giappone non si regalano i pettini alle ragazze perché porta sfortuna?**  
Il kanji per "pettine" (櫛, *kushi*) contiene suoni simili a quelli per "morte" (死, *shi*) e "sofferenza" (苦, *ku*).  
Meglio evitare regali ambigui! ✨
