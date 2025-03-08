# **Installazione di FSL e MRtrix3 su un Server Remoto**

Questa guida descrive i passaggi per installare **FSL** e **MRtrix3** in un ambiente **Conda** su un server remoto.

## **Prerequisiti**
- Accesso SSH al server
- `conda` installato sul sistema
- Connessione internet stabile
- Permessi di scrittura sulla home directory
---

## **1️⃣ Connessione al Server**
Apri un terminale e connettiti al server remoto con il seguente comando:

```bash
ssh username@indirizzo_del_server
```

⚠️ **Nota:** Usa `-X` per abilitare il forwarding X11 se devi eseguire applicazioni grafiche come `fsleyes` o `mrview`.

ovvero

```bash
ssh -X username@indirizzo_del_server 
```

---

## **2️⃣ Creazione di un Nuovo Ambiente Conda**
MRTRIX USA PYTHON 3.10!
Crea un nuovo ambiente Conda con Python 3.10.13:

```bash
conda create -n fsl_env -c conda-forge python=3.10.13  
```

Attiva l'ambiente appena creato:

```bash
conda activate fsl_env
```

---

## **3️⃣ Installazione di FSL**
Scarica l'installer aggiornato di **FSL** dal mio repo ( fslinstaller.py ) .

Esegui l'installer con il supporto per Conda:

```bash
python fslinstaller.py --conda
```

Accetta i termini di utilizzo e lascia il percorso predefinito per l'installazione.

---

## **4️⃣ Configurazione delle Variabili d'Ambiente**
Aggiungi le variabili d'ambiente necessarie al file `~/.bashrc`:

```bash
echo 'export FSLDIR=$HOME/fsl' >> ~/.bashrc
echo 'export PATH=$FSLDIR/bin:$PATH' >> ~/.bashrc
echo 'export FSLOUTPUTTYPE=NIFTI_GZ' >> ~/.bashrc
echo 'export FSLMULTIFILEQUIT=TRUE' >> ~/.bashrc
echo 'export DISPLAY=""' >> ~/.bashrc
echo 'alias fslversion="cat $FSLDIR/etc/fslversion"' >> ~/.bashrc
echo 'source $FSLDIR/etc/fslconf/fsl.sh' >> ~/.bashrc
```

Ricarica il file `.bashrc` con:

```bash
source ~/.bashrc
```

Verifica che FSL sia stato installato correttamente:

```bash
flirt -version   # Dovrebbe restituire "FLIRT version 6.0"
fslversion       # Dovrebbe restituire "6.0.7.17" o una versione simile
```

Se hai bisogno di interfacce grafiche, verifica con:

```bash
fsleyes
```

⚠️ **Se ricevi errori su `$DISPLAY`, prova a connetterti con `ssh -X`.**

---

## **5️⃣ Installazione di MRtrix3**
Ora installa **MRtrix3** con Conda:

```bash
conda install -c mrtrix3 mrtrix3
```

Verifica l'installazione con:

```bash
mrinfo --version   # Controlla se MRtrix3 è installato
mrview             # Verifica l'interfaccia grafica (usa SSH -X se necessario)
```

---

## **Test Finale dell'Installazione**
Dopo aver seguito tutti i passaggi, puoi testare FSL e MRtrix3 con questi comandi:

```bash
fslversion         # Controlla la versione di FSL
flirt -version     # Controlla se FLIRT è disponibile
mrinfo --version   # Controlla se MRtrix3 è installato
```

Se tutti i comandi funzionano senza errori, l'installazione è completa! ✅

---


## **Debug di MRtrix3**

Se l'installazione di **MRtrix3** è stata effettuata tramite **Conda**, è importante verificare il percorso corretto della directory contenente i binari di MRtrix3.  
L'utente può ottenere questo percorso eseguendo il seguente comando:

```bash
echo $(dirname $(which mrconvert))
```

Spiegazione del comando:
which mrconvert → Trova il percorso esatto del comando mrconvert, uno degli strumenti principali di MRtrix3.
dirname → Estrae solo la directory che contiene il file eseguibile.
echo → Stampa il percorso risultante.

Esempio di output:
```bash
/lustrehome/utente/.conda/envs/tbi_dwi_py310/bin
```

A questo punto, l'utente dovrà aggiornare il valore della variabile MRTRIX_BIN nello script  [`1 - Processing/dwi_processing_cicle.sh`](1%20-%20Processing/dwi_processing_cicle.sh), sostituendo il percorso corretto

MRTRIX_BIN=""

con l'output del comando precedente.


## **Conclusione**
Ora hai **FSL** e **MRtrix3** installati e pronti all'uso nel tuo ambiente Conda. 🎉

Se hai bisogno di usare `fsleyes` o `mrview`, ricordati di attivare X11 con `ssh -X`.

🚀 **Buon lavoro con l'analisi delle immagini!**

## ** Curiosità Random **

**Le anatre non fanno eco (o almeno così si dice). C'è una leggenda che dice che il "quack" delle anatre non produce eco. In realtà è falso, ma il loro verso è talmente diffuso e confuso che spesso l'eco non si percepisce bene**