# README - Pipeline DWI Processing

## Descrizione Generale
Questa pipeline automatizza il preprocessing delle immagini di Diffusion-Weighted Imaging (DWI) per l'analisi della diffusione cerebrale. L'obiettivo principale è la correzione degli artefatti, la registrazione in spazio standard e la generazione di modelli di diffusione utili per la tractografia.

Le immagini DWI sono sequenze di immagini 3D acquisite a diversi gradienti di diffusione nel tempo, creando un volume 4D (x, y, z, tempo). Il primo volume (b0) è un'immagine senza diffusione pesata ed è usato come riferimento per la registrazione agli atlanti standard.

## Requisiti
### **Software**

- **MRtrix3** per il preprocessing e la tractografia
- **FSL** per la registrazione e l'estrazione delle ROI

Per creare l'environment corretto e configurato in maniera ottimale, consulta il [README dell'installazione](0-setup/setup.md).

### **Dati di Input**
- Immagini DWI in formato NIfTI (`*.nii.gz`)
- File di gradienti (`*.bvec` e `*.bval`)
- Atlanti HarvardOxford per l'estrazione delle ROI

📌 Modifica del README

Aggiungi questa sezione nel README sotto la parte dei dati di input.

### **Configurazione dei Path degli Atlanti**
Nel file di script, i path degli atlanti e delle immagini di riferimento sono preconfigurati in base all'installazione su un server specifico. **Se usi la pipeline su un'altra macchina**, devi modificare i seguenti path nel file di script `dwi_processing_cicle.sh` per adattarli alla tua installazione:

```bash
# Definizione degli atlanti e riferimenti
ATLAS="/lustrehome/emanueleamato/fsl/data/standard/MNI152_T1_1mm.nii.gz"
ATLAS_CORTICAL="/lustrehome/emanueleamato/fsl/data/atlases/HarvardOxford/HarvardOxford-cort-maxprob-thr25-1mm.nii.gz"
ATLAS_SUBCORTICAL="/lustrehome/emanueleamato/fsl/data/atlases/HarvardOxford/HarvardOxford-sub-maxprob-thr25-1mm.nii.gz"
MNI_REF="/lustrehome/emanueleamato/fsl/data/standard/MNI152_T1_1mm.nii.gz"
```
🔹 Come modificare i path?

Se hai installato FSL e gli atlanti HarvardOxford in una posizione diversa, cambia i path con il tuo percorso.
Per trovare la posizione corretta degli atlanti sul tuo sistema, esegui:
```bash
echo $FSLDIR
```
e naviga dentro la directory 
```bash
$FSLDIR/data/atlases/HarvardOxford/ per verificare dove si trovano i file richiesti.
```

# Pipeline DWI - Trattografia probabilistica con MRtrix3

## 📚 Introduzione

Questa pipeline è progettata per elaborare **immagini DWI (Diffusion-Weighted Imaging)** ed estrarre **trattografie probabilistiche** utilizzando **MRtrix3**.  

Le immagini DWI sono dati di **diffusione dell'acqua nel cervello**, registrati in una griglia **4D**:
- **Le prime tre dimensioni** rappresentano lo spazio (X, Y, Z).
- **La quarta dimensione** corrisponde alle direzioni di diffusione registrate (gradienti di diffusione).  
Ad esempio, un'immagine con dimensioni `128 × 128 × 78 × 65` contiene **65 volumi** di diffusione acquisiti.

La **trattografia** permette di ricostruire le **connessioni anatomiche della materia bianca**, simulando il percorso delle fibre neurali.

---

## 🚀 **Fasi della Pipeline**

### **1️⃣ Preprocessing DWI**
Prima di generare la trattografia, è fondamentale correggere le distorsioni dell'immagine.

1. **Estrazione del primo volume b=0 (b0)**  
   - Il volume b=0 è il riferimento, privo di contrasto di diffusione.
   - Viene usato per la registrazione su un template standard (MNI152).
   ```bash
   "$MRTRIX_BIN/mrconvert" "$DWI" "$OUT_PATIENT_DIR/preprocessing/dwi_b0.nii.gz" -coord 3 0
   ```

2. **Registrazione su spazio standard (MNI152)**  
   - Viene usato `FLIRT` (FSL) per allineare il b0 all'MNI152.
   ```bash
   flirt -in "$OUT_PATIENT_DIR/preprocessing/dwi_b0.nii.gz" -ref "$MNI_REF" \
         -out "$OUT_PATIENT_DIR/preprocessing/dwi_b0_mni.nii.gz" \
         -omat "$OUT_PATIENT_DIR/preprocessing/dwi2mni.mat" -dof 12
   ```
   
3. **Correzione di movimento ed effetti di suscettibilità magnetica**  
   - `dwifslpreproc` corregge i movimenti del paziente e distorsioni indotte dal campo magnetico.
   ```bash
   "$MRTRIX_BIN/dwifslpreproc" "$OUT_PATIENT_DIR/preprocessing/dwi_mni152.nii.gz" \
        "$OUT_PATIENT_DIR/preprocessing/dwi_preprocessed.mif" -fslgrad "$BVEC" "$BVAL" \
        -pe_dir AP -rpe_none -eddy_options "'--repol'"
   ```

---

### **2️⃣ Calcolo del tensore di diffusione**
Una volta corretti gli artefatti, si calcola il **tensore di diffusione**, che descrive come l'acqua si muove nei tessuti:

```bash
"$MRTRIX_BIN/dwi2tensor" "$OUT_PATIENT_DIR/preprocessing/dwi_preprocessed.mif" "$OUT_PATIENT_DIR/dti_metrics/dti.mif"
"$MRTRIX_BIN/tensor2metric" "$OUT_PATIENT_DIR/dti_metrics/dti.mif" \
   -fa "$OUT_PATIENT_DIR/dti_metrics/fa.mif" -adc "$OUT_PATIENT_DIR/dti_metrics/md.mif"
```
- **FA (Fractional Anisotropy)**: Misura l'anisotropia della diffusione.
- **MD (Mean Diffusivity)**: Misura la diffusione media in tutte le direzioni.

---

### **3️⃣ Ricostruzione della funzione di orientamento della diffusione (FOD)**
La **FOD (Fiber Orientation Distribution)** permette di modellare la direzione delle fibre nei voxel cerebrali.  
Si determina in base al tipo di acquisizione:

- **Multi-shell (più valori di b-value)** → `dwi2response dhollander` (modello avanzato multi-tessuto).  
- **Single-shell (un solo b-value)** → `dwi2response tournier` (modello standard).

```bash
"$MRTRIX_BIN/dwi2response" tournier "$OUT_PATIENT_DIR/preprocessing/dwi_preprocessed.mif" \
    "$OUT_PATIENT_DIR/tractography/response.txt"
```

Le risposte vengono usate per calcolare la **ricostruzione CSD (Constrained Spherical Deconvolution)**:

```bash
"$MRTRIX_BIN/dwi2fod" csd "$OUT_PATIENT_DIR/preprocessing/dwi_preprocessed.mif" \
   "$OUT_PATIENT_DIR/tractography/response.txt" "$OUT_PATIENT_DIR/tractography/fod.mif"
```

---

### **4️⃣ Creazione della maschera cerebrale**
Per evitare di generare tratti al di fuori del cervello, creiamo una **maschera binaria**:

```bash
"$MRTRIX_BIN/dwi2mask" "$OUT_PATIENT_DIR/preprocessing/dwi_preprocessed.mif" \
    "$OUT_PATIENT_DIR/preprocessing/mask.mif"
```

---

### **5️⃣ Generazione della trattografia probabilistica con iFOD2**
Ora possiamo generare i tratti delle fibre nervose utilizzando un algoritmo probabilistico (`iFOD2`):

```bash
"$MRTRIX_BIN/tckgen" "$OUT_PATIENT_DIR/tractography/fod.mif" "$OUT_PATIENT_DIR/tractography/tracts.tck" \
    -seed_dynamic "$OUT_PATIENT_DIR/tractography/fod.mif" \
    -mask "$OUT_PATIENT_DIR/preprocessing/mask.mif" \
    -select 1000000 -algorithm iFOD2
```

---

## 📊 **Risultati finali**
Dopo l'esecuzione della pipeline, otterrai:
- **`tracts.tck`** → File che contiene la **trattografia probabilistica**.
- **`fa.mif` / `md.mif`** → Indici di diffusione.
- **`fod.mif`** → Funzione di orientamento della diffusione.

Puoi visualizzare i risultati con `MRView`:

```bash
"$MRTRIX_BIN/mrview" "$OUT_PATIENT_DIR/preprocessing/dwi_preprocessed.mif" -tractography.load "$OUT_PATIENT_DIR/tractography/tracts.tck"
```

---

## 🔍 **Conclusione**
Questa pipeline guida il processo **dalla DWI grezza alla ricostruzione delle fibre cerebrali**.  
Anche senza immagini T1, possiamo eseguire una **trattografia affidabile** basata sulla diffusione. 🚀


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



