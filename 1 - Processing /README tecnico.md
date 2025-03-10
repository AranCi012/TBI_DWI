# README Tecnico - Pipeline di Elaborazione DWI

## Struttura delle Cartelle

### Struttura della Cartella di Input
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

## Esecuzione della Pipeline
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

## Ottimizzazione Computazionale
La pipeline supporta il **multithreading** e l'uso automatico della **GPU**. 

- **Multithreading:** Se il numero di CPU disponibili lo consente, la pipeline sfrutta il parallelismo per velocizzare le operazioni computazionali pesanti.
- **GPU Support:** Se disponibile, la GPU viene utilizzata automaticamente per accelerare il calcolo.
- **Fallback Mode:** Se né il multithreading né la GPU sono disponibili, la pipeline esegue le operazioni in modalità single-threaded.

Le impostazioni per il numero di thread utilizzati possono essere configurate modificando la variabile `NUM_THREADS` nel file `config.sh`:
```bash
NUM_THREADS=$(nproc)  # Usa il numero massimo di CPU disponibili
```

Se si desidera forzare l'uso di un numero specifico di thread:
```bash
NUM_THREADS=8  # Imposta a 8 il numero massimo di thread
```

## Debugging e Problemi Comuni
1. **Errori di registrazione:** verificare che le immagini siano effettivamente in formato 4D e che il primo volume sia ben estratto.
2. **Dimension mismatch:** controllare che i file `bvec` e `bval` corrispondano al numero di volumi DWI.
3. **Problemi di permessi:** assicurarsi che le directory di output siano scrivibili.
4. **GPU non rilevata:** verificare con `nvidia-smi` che la GPU sia attiva e che i driver siano aggiornati.

## Autore
**Emanuele Amato**  
emanuele.amato@uniba.it  
eamato@ethz.ch  

---

## Curiosità sui Modi di Dire Giapponesi

In Giappone si usa il detto **「猿も木から落ちる」 (Saru mo ki kara ochiru)**, che significa *"Anche le scimmie cadono dagli alberi"*. Questo proverbio viene usato per ricordare che anche i più esperti possono commettere errori, e che sbagliare è umano! 🐵🍃

---