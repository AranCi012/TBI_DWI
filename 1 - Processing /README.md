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

## Struttura della Pipeline

### **1. Estrarre il primo volume (b0) e registrarlo allo spazio MNI152**
Poiché le immagini DWI sono 4D (3D + tempo), il primo volume (b0) viene estratto per essere utilizzato come riferimento per la registrazione. Il comando `mrconvert` viene utilizzato per selezionare il primo volume temporale e convertirlo in formato NIfTI-1. Successivamente, viene effettuata la registrazione dell'immagine b0 allo spazio MNI152 utilizzando il software FSL (`flirt`).

### **2. Creazione delle ROI corticali e subcorticali**
Si utilizzano gli atlanti HarvardOxford per estrarre regioni di interesse (ROI) corticali e subcorticali, necessarie per studi di connettività cerebrale. Ogni regione viene binarizzata e salvata separatamente per successive analisi.

### **3. Correzione degli artefatti con MRtrix3 (dwifslpreproc)**
Le immagini DWI contengono distorsioni dovute a movimenti e imperfezioni della macchina di risonanza magnetica. Questo passaggio utilizza `dwifslpreproc` per correggere distorsioni geometriche e motion artifacts.

### **4. Creazione della maschera cerebrale**
Una maschera binaria del cervello viene generata con `dwi2mask`, necessaria per escludere le regioni non cerebrali nell'elaborazione successiva.

### **5. Modellizzazione della diffusione**
Le immagini DWI vengono elaborate per calcolare il tensore di diffusione, che rappresenta le direzioni principali di diffusione dell'acqua nei tessuti. Questo passaggio genera:
- **FA (Fractional Anisotropy):** misura del grado di anisotropia della diffusione.
- **MD (Mean Diffusivity):** misura della media della diffusione nelle direzioni principali.

### **6. Tractografia probabilistica con iFOD2**
La tractografia è il processo di ricostruzione delle fibre della materia bianca. Il modello di diffusione viene convertito in un campo di orientamento dei fasci (FOD), e da questo vengono estratte le traccianti delle fibre cerebrali con `tckgen`.

### **7. Generazione del report finale**
Un file `pipeline_summary.txt` viene generato per ogni paziente per riepilogare l'esecuzione della pipeline e facilitare il monitoraggio dei risultati.

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

## ** Curiosità Random **

**Lo sapevi che in giappone non si regalano i pettini alle ragazze che porta male?**

🚀

---



