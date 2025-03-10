# README - Pipeline DWI Processing

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
- Atlanti **HarvardOxford** per la segmentazione cerebrale

### **Configurazione dei Path degli Atlanti**
Nel file `dwi_processing_pipeline.sh`, i path agli atlanti e alle immagini di riferimento sono preconfigurati. Se usi la pipeline su un'altra macchina, devi modificare i seguenti path:

```bash
# Definizione degli atlanti e riferimenti
ATLAS="/lustrehome/emanueleamato/fsl/data/standard/MNI152_T1_1mm.nii.gz"
ATLAS_CORTICAL="/lustrehome/emanueleamato/fsl/data/atlases/HarvardOxford/HarvardOxford-cort-maxprob-thr25-1mm.nii.gz"
ATLAS_SUBCORTICAL="/lustrehome/emanueleamato/fsl/data/atlases/HarvardOxford/HarvardOxford-sub-maxprob-thr25-1mm.nii.gz"
MNI_REF="/lustrehome/emanueleamato/fsl/data/standard/MNI152_T1_1mm.nii.gz"
```
Per verificare la posizione degli atlanti, esegui:
```bash
echo $FSLDIR
ls $FSLDIR/data/atlases/HarvardOxford/
```

---

## 🚀 **Fasi della Pipeline**

### **1️⃣ Preprocessing DWI**

#### **1.1 Estrazione del primo volume (b0)**
Il volume **b0** è utilizzato per la registrazione su spazio standard. Viene estratto con:
```bash
$MRTRIX_BIN/mrconvert "$DWI" "$OUT_PATIENT_DIR/preprocessing/dwi_b0.nii.gz" -coord 3 0
```

#### **1.2 Registrazione su spazio MNI152**
Viene usato **FLIRT** (FSL) per allineare il volume b0 allo spazio standard:
```bash
flirt -in "$OUT_PATIENT_DIR/preprocessing/dwi_b0.nii.gz" -ref "$MNI_REF" \
      -out "$OUT_PATIENT_DIR/preprocessing/dwi_b0_mni.nii.gz" \
      -omat "$OUT_PATIENT_DIR/preprocessing/dwi2mni.mat" -dof 12
```
La trasformazione viene applicata all'intera immagine 4D:
```bash
applywarp --ref="$MNI_REF" \
         --in="$DWI" \
         --out="$OUT_PATIENT_DIR/preprocessing/dwi_mni152.nii.gz" \
         --premat="$OUT_PATIENT_DIR/preprocessing/dwi2mni.mat"
```

#### **1.3 Correzione degli artefatti (dwifslpreproc)**
`dwifslpreproc` corregge i movimenti del paziente e distorsioni da suscettibilità magnetica:
```bash
CUDA_VISIBLE_DEVICES=0 "$MRTRIX_BIN/dwifslpreproc" "$OUT_PATIENT_DIR/preprocessing/dwi_mni152.nii.gz" \
    "$OUT_PATIENT_DIR/preprocessing/dwi_preprocessed.mif" -fslgrad "$BVEC" "$BVAL" \
    -pe_dir AP -rpe_none -eddy_options "'--repol'"
```

---

### **2️⃣ Modellizzazione della Diffusione**

#### **2.1 Calcolo del Tensore di Diffusione**
```bash
$MRTRIX_BIN/dwi2tensor "$OUT_PATIENT_DIR/preprocessing/dwi_preprocessed.mif" "$OUT_PATIENT_DIR/dti_metrics/dti.mif"
$MRTRIX_BIN/tensor2metric "$OUT_PATIENT_DIR/dti_metrics/dti.mif" \
    -fa "$OUT_PATIENT_DIR/dti_metrics/fa.mif" -adc "$OUT_PATIENT_DIR/dti_metrics/md.mif"
```

---

### **3️⃣ Trattografia probabilistica con iFOD2**

Le FOD (Fiber Orientation Distributions) sono stime della distribuzione delle direzioni delle fibre in ogni voxel di un'immagine di diffusione. Il modo in cui vengono calcolate dipende dal numero di shell nella sequenza di diffusione utilizzata.

Cosa significa "in base al numero di shell"?
Il numero di shell si riferisce ai diversi livelli di b-value usati nell'acquisizione dell'immagine di diffusione (DWI) [Si controllino i valori all'interno dei file bvec e bval]. I b-value definiscono l'intensità della diffusione misurata, e le acquisizioni possono essere:

- Single-shell (una sola b-value, ad esempio b = 1000 s/mm²)
- Multi-shell (più b-value, ad esempio b = 1000 e 3000 s/mm²)
- DENSE (diffusion spectrum imaging, DSI) con un ampio range di b-value

A seconda del numero di shell, vengono utilizzati modelli di ricostruzione diversi per ottenere le FOD:

Single-shell → Generalmente si utilizza il modello CSD (Constrained Spherical Deconvolution) classico.
Multi-shell → Si usa MSMT-CSD (Multi-Shell Multi-Tissue Constrained Spherical Deconvolution), che permette di distinguere più componenti, come la materia bianca, la materia grigia e il liquido cerebrospinale (CSF).
DENSE (DSI, Q-space methods) → Tecniche più avanzate come Q-ball imaging o diffusion spectrum imaging.

#### **3.1 Creazione della maschera cerebrale**
```bash
$MRTRIX_BIN/dwi2mask "$OUT_PATIENT_DIR/preprocessing/dwi_preprocessed.mif" \
    "$OUT_PATIENT_DIR/preprocessing/mask.mif"
```

#### **3.2 Ricostruzione della Funzione di Orientamento della Diffusione (FOD)**
La FOD viene calcolata in base al numero di shell:
```bash
SHELL_COUNT=$("$MRTRIX_BIN/mrinfo" "$OUT_PATIENT_DIR/preprocessing/dwi_preprocessed.mif" -shell_bvalues | wc -w)
if [ "$SHELL_COUNT" -gt 1 ]; then
    "$MRTRIX_BIN/dwi2response" dhollander "$OUT_PATIENT_DIR/preprocessing/dwi_preprocessed.mif" \
        "$OUT_PATIENT_DIR/tractography/response_wm.txt" \
        "$OUT_PATIENT_DIR/tractography/response_gm.txt" \
        "$OUT_PATIENT_DIR/tractography/response_csf.txt"
else
    "$MRTRIX_BIN/dwi2response" tournier "$OUT_PATIENT_DIR/preprocessing/dwi_preprocessed.mif" \
        "$OUT_PATIENT_DIR/tractography/response.txt"
fi
```

#### **3.3 Generazione della trattografia probabilistica con iFOD2**
```bash
$MRTRIX_BIN/tckgen "$OUT_PATIENT_DIR/tractography/fod_wm.mif" "$OUT_PATIENT_DIR/tractography/tracts.tck" \
    -seed_dynamic "$OUT_PATIENT_DIR/tractography/fod_wm.mif" \
    -mask "$OUT_PATIENT_DIR/preprocessing/mask.mif" \
    -select 1000000 -algorithm iFOD2
```

---

## 📊 **Output della Pipeline**
Dopo l'esecuzione della pipeline, otterrai:
- **`tracts.tck`** → Trattografia probabilistica
- **`fa.mif` / `md.mif`** → Indici di diffusione
- **`fod.mif`** → Funzione di orientamento della diffusione

Puoi visualizzare i risultati con:
```bash
$MRTRIX_BIN/mrview "$OUT_PATIENT_DIR/preprocessing/dwi_preprocessed.mif" -tractography.load "$OUT_PATIENT_DIR/tractography/tracts.tck"
```

---

## **Autore**
**Emanuele Amato**  
emanuele.amato@uniba.it  
eamato@ethz.ch  

🚀




## Struttura delle Cartelle

## Struttura della Cartella di Input
La cartella di input deve essere organizzata nel seguente modo:
```
raw_DWI/
|-- sub-0001/
|   |-- sub-0001_dwi.nii.gz  (Immagine DWI 4D)
|   |-- sub-0001_dwi.bvec  (File dei gradienti di diffusione)
|   |-- sub-0001_dwi.bval  (Valori dei gradienti di diffusione)
|-- sub-0002/
|   |-- sub-0002_dwi.nii.gz
|   |-- sub-0002_dwi.bvec
|   |-- sub-0002_dwi.bval
```

Dopo l'elaborazione, la pipeline organizza i dati secondo la seguente struttura:
```
processed_DWI/
|-- sub-0001/
|   |-- preprocessing/
|   |   |-- dwi_mni152.nii.gz  (DWI registrata)
|   |   |-- dwi_preprocessed.mif  (DWI preprocessata)
|   |   |-- mask.mif  (maschera cerebrale)
|   |-- dti_metrics/
|   |   |-- fa.mif  (Fractional Anisotropy)
|   |   |-- md.mif  (Mean Diffusivity)
|   |-- tractography/
|   |   |-- fod.mif  (Field of Orientation Distributions)
|   |   |-- tracts.tck  (Tractografia)
|   |-- reports/
|   |   |-- pipeline_summary.txt  (Report finale)
```


## Esecuzione
Per eseguire la pipeline:
```bash
./dwi_processing_pipeline.sh <input_dir> <output_dir>
```
Esempio:
```bash
./dwi_processing_pipeline.sh raw_DWI processed_DWI
```
Dove:
- `raw_DWI` è la directory con le immagini originali
- `processed_DWI` è la directory di output con i dati preprocessati

## Debugging e Problemi Comuni
1. **Errori di registrazione:** verificare che le immagini siano effettivamente in formato 4D e che il primo volume sia ben estratto.
2. **Dimension mismatch:** controllare che i file `bvec` e `bval` corrispondano al numero di volumi DWI.
3. **Problemi di permessi:** assicurarsi che le directory di output siano scrivibili.

---

## Autore
**Emanuele Amato**  
emanuele.amato@uniba.it
eamato@ethz.ch

---

## Curiosità Random 

**Lo sapevi che in giappone non si regalano i pettini alle ragazze che porta male?**

🚀

---



