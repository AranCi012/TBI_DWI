# **Report sulle Modifiche alla Pipeline DWI – Versione 07/03/2025**

---

## **1. Introduzione**
Questa relazione documenta le modifiche apportate alla **Pipeline DWI**, aggiornata alla versione **7 marzo 2025**. La pipeline automatizza l'elaborazione dei dati **Diffusion-Weighted Imaging (DWI)**, eseguendo fasi cruciali di preprocessing, modellizzazione della diffusione, trattografia e generazione della **matrice di connettività cerebrale**.

L'aggiornamento ha migliorato la robustezza e l'affidabilità del flusso di lavoro, con una particolare enfasi sulla sostituzione di metodi obsoleti con strumenti più avanzati di **MRtrix3**.

---

## **2. Panoramica delle Migliorie**

### **Nuove Funzionalità**
La versione aggiornata della pipeline introduce:
- **Preprocessing avanzato** con `dwifslpreproc` (MRtrix3) invece di `eddy_correct` (FSL), garantendo una correzione più precisa degli artefatti e dei movimenti.
- **Migliore modellizzazione della diffusione** utilizzando `dwi2tensor` e `dwi2fod` (MRtrix3) al posto di **BEDPOSTX (FSL)**.
- **Trattografia più efficiente** con `tckgen` e il metodo **iFOD2**, riducendo i bias rispetto a `probtrackx2` (FSL).
- **Generazione automatizzata della matrice di connettività**, utilizzando `tck2connectome` per una migliore analisi della connettività cerebrale.
- **Ottimizzazione del formato dei dati** per il Machine Learning e Graph Neural Networks (GNN), mantenendo la compatibilità con `.nii.gz`.
- **Automazione della registrazione delle immagini 4D**, eliminando passaggi manuali superflui.

---

## **3. Dettaglio delle Modifiche**
La tabella seguente confronta la versione precedente della pipeline con la nuova implementazione.

| **Componente**                        | **Versione Vecchia**                         | **Versione 2025**                           | **Vantaggi della Nuova Versione**            |
|--------------------------------------|---------------------------------|---------------------------------|--------------------------------|
| **Atlante**                          | Harvard-Oxford (corteccia e sottocorteccia) | Harvard-Oxford (corteccia e sottocorteccia) | Nessuna modifica |
| **Registrazione in MNI152**           | `flirt` (FSL)                 | `flirt` (FSL)                 | Nessuna modifica |
| **Generazione ROI corticali e subcorticali** | `fslmaths`                     | `fslmaths`                     | Nessuna modifica |
| **Preprocessing DWI**                 | `eddy_correct` (FSL)            | `dwifslpreproc` (MRtrix3)      | Correzione più avanzata degli artefatti |
| **Modellizzazione della diffusione**  | `BEDPOSTX` (FSL)                | `dwi2tensor` e `dwi2fod` (MRtrix3) | Modellizzazione più accurata |
| **Metodo di trattografia**            | `probtrackx2` (FSL)             | `tckgen` con `iFOD2` (MRtrix3)  | iFOD2 è più efficiente e meno biasato |
| **Generazione matrice di connettività** | Non presente                     | `tck2connectome` (MRtrix3)       | Analisi avanzata delle connessioni cerebrali |
| **Formato output per ML/GNN**         | `.nii.gz` per metriche         | `.nii.gz` per metriche         | Nessuna modifica |
| **Organizzazione directory output**   | Struttura semplice              | Struttura migliorata            | Maggiore leggibilità dei risultati |

---

## **4. Struttura della Pipeline Aggiornata**

### **1. Registrazione nello spazio MNI152**
- Il primo volume (b0) della sequenza 4D viene estratto con `mrconvert`.
- La registrazione in MNI152 viene effettuata con `flirt` (FSL).

### **2. Generazione delle ROI corticali e subcorticali**
- Utilizza gli atlanti Harvard-Oxford per creare regioni di interesse binarizzate.

### **3. Preprocessing DWI**
- Utilizzo di `dwifslpreproc` (MRtrix3) per correggere artefatti da movimento e distorsioni geometriche.

### **4. Modellizzazione della diffusione**
- Calcolo di **Fractional Anisotropy (FA)** e **Mean Diffusivity (MD)** con `dwi2tensor`.
- Generazione dei **Field of Orientation Distributions (FOD)** con `dwi2fod`.

### **5. Trattografia probabilistica**
- Creazione del modello di risposta con `dwi2response`.
- Ricostruzione delle fibre con `tckgen` utilizzando il metodo **iFOD2**.

### **6. Generazione della Matrice di Connettività**
- Registrazione dell'atlante nello spazio delle immagini DWI.
- Creazione della matrice di connettività con `tck2connectome`.

### **7. Esportazione dati per Machine Learning/GNN**
- I risultati sono organizzati in `.nii.gz` per un’integrazione ottimale in modelli di deep learning.

### **8. Report finale**
- Un file di riepilogo (`pipeline_summary.txt`) è generato per ogni paziente.

---

## **5. Prestazioni e Tempi di Computazione**
- La computazione per **singolo paziente richiede circa un'ora o poco più** su un sistema con **5 GB di RAM GPU** e **16 CPU multithread**.
- L'uso di GPU e ottimizzazioni con MRtrix3 riduce significativamente i tempi rispetto alle versioni precedenti.

---

## **6. Conclusioni e Vantaggi**
La versione aggiornata della **Pipeline DWI** migliora significativamente l'elaborazione dei dati di diffusione cerebrale:
- **Precisione superiore** nella correzione degli artefatti e nella modellizzazione della diffusione.
- **Maggiore efficienza** nei tempi di esecuzione grazie all’uso di MRtrix3.
- **Analisi avanzata della connettività cerebrale** con la generazione automatizzata della matrice di connettività.
- **Miglior compatibilità** con analisi avanzate, come deep learning e Graph Neural Networks.

Queste migliorie rendono la pipeline più adatta alle esigenze attuali della ricerca in neuroscienze computazionali e imaging medico.

---

## **7. Referenze e Contatti**
Per dettagli e richieste di supporto contattare:
- **Emanuele Amato**  
- **Email:**  
emanuele.amato@uniba.it
eamato@ethz.ch

Per ulteriori informazioni su MRtrix3:  
[https://www.mrtrix.org/](https://www.mrtrix.org/)




## **8. Curiosità Random**

**Lo sapevi lo squalo riesce a girare gli occhi al contrario?**

---
