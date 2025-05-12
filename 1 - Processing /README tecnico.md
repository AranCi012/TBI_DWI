# README Tecnico - Pipeline di Elaborazione DWI 

## Struttura delle Cartelle

### Struttura della Cartella di Input
La cartella di input deve essere organizzata nel seguente modo:
```
raw_DWI/
|-- sub-0001/
|   |-- sub-0001_dwi.nii.gz  (Immagine DWI 4D)
|   |-- sub-0001_dwi.bvec     (File dei gradienti di diffusione)
|   |-- sub-0001_dwi.bval     (Valori dei gradienti di diffusione)
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
|   |   |-- dwi_registered.nii.gz      (DWI registrata sull'atlas)
|   |   |-- dwi_preprocessed.mif      (DWI preprocessata)
|   |   |-- mask.mif                  (maschera cerebrale)
|   |-- dti_metrics/
|   |   |-- fa.mif                    (Fractional Anisotropy)
|   |   |-- md.mif                    (Mean Diffusivity)
|   |-- tractography/
|   |   |-- fod.mif o fod_wm.mif      (Field of Orientation Distributions)
|   |   |-- tracts.tck                (Tractografia)
|   |-- reports/
|   |   |-- pipeline_report.txt       (Report finale)
```

## Esecuzione della Pipeline
Per eseguire la pipeline:
```bash
./dwi_processing_pipeline.sh <input_dir> <output_dir> <atlas_file>
```
Esempio:
```bash
./dwi_processing_pipeline.sh raw_DWI processed_DWI /path/to/MNI152_T1_1mm.nii.gz
```
Dove:
- `raw_DWI` è la directory con le immagini originali
- `processed_DWI` è la directory di output con i dati preprocessati
- `/path/to/MNI152_T1_1mm.nii.gz` è il file NIfTI dell’atlas di riferimento

## Ottimizzazione Computazionale
La pipeline supporta il **multithreading** e l'uso automatico della **GPU**.

- **Multithreading:** Impostato tramite la variabile `MRTRIX_NTHREADS`, sfrutta tutte le CPU disponibili.
- **GPU Support:** Se presente, la GPU viene utilizzata per le operazioni CUDA-based (es. dwifslpreproc, dwi2fod).
- **Fallback Mode:** Se la GPU non è disponibile, le operazioni vengono comunque eseguite in CPU.

### Esempio di impostazione dei thread
Nel file:
```bash
export MRTRIX_NTHREADS=128
```
Oppure:
```bash
export MRTRIX_NTHREADS=$(nproc)  # Usa tutte le CPU disponibili
```

## Debugging e Problemi Comuni
1. **File mancanti:** assicurarsi che ogni cartella contenga `.nii.gz`, `.bvec` e `.bval`.
2. **Errore di registrazione:** controllare che l’immagine abbia almeno un volume b=0 valido.
3. **Mismatch tra volumi e gradienti:** `bvec` e `bval` devono avere dimensioni compatibili col numero di volumi del DWI.
4. **GPU non rilevata:** usare `nvidia-smi` per verificare che sia attiva.
5. **Permission denied:** accertarsi che le directory siano scrivibili.

## Autore
**Emanuele Amato**  
emanuele.amato@uniba.it  
eamato@ethz.ch  

---

## Curiosità sui Modi di Dire Giapponesi

In Giappone si usa il detto **「猿も木から落ちる」 (Saru mo ki kara ochiru)**, che significa *"Anche le scimmie cadono dagli alberi"*. Questo proverbio viene usato per ricordare che anche i più esperti possono commettere errori, e che sbagliare è umano! 🐵🍃