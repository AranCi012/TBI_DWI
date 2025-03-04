#!/bin/bash

# Configurazione
INSTALL_DIR="$HOME/dwi_tools"
export PATH="$INSTALL_DIR/bin:$PATH"
export FSLDIR="$INSTALL_DIR/fsl"
export ANTSPATH="$INSTALL_DIR/ants/bin"
export PATH="$FSLDIR/bin:$ANTSPATH:$PATH"

echo "=== 1. Creazione della cartella di installazione: $INSTALL_DIR ==="
mkdir -p $INSTALL_DIR/bin
mkdir -p $INSTALL_DIR/src
cd $INSTALL_DIR/src

echo "=== 2. Installazione di dipendenze di sistema ==="
sudo apt update && sudo apt install -y git curl wget build-essential cmake python3-pip libgl1-mesa-glx libopenblas-dev liblapack-dev libfftw3-dev

echo "=== 3. Installazione di FSL (senza root) ==="
wget -O fsl.tar.gz https://fsl.fmrib.ox.ac.uk/fsldownloads/fsl-6.0.5.1-centos7_64.tar.gz
tar -xzf fsl.tar.gz -C $INSTALL_DIR
rm fsl.tar.gz
echo "source $FSLDIR/etc/fslconf/fsl.sh" >> ~/.bashrc

echo "=== 4. Installazione di MRtrix3 ==="
git clone https://github.com/MRtrix3/mrtrix3.git
cd mrtrix3
./configure --prefix=$INSTALL_DIR
./build
cp ./bin/* $INSTALL_DIR/bin/
cd ..

echo "=== 5. Installazione di ANTs ==="
wget -O ants.tar.gz https://github.com/ANTsX/ANTs/releases/download/v2.4.3/ants-Linux.tar.gz
tar -xzf ants.tar.gz -C $INSTALL_DIR
rm ants.tar.gz
echo "export PATH=$ANTSPATH:\$PATH" >> ~/.bashrc

echo "=== 6. Installazione di DIPY ==="
pip3 install --upgrade pip --user
pip3 install --user dipy[all]

echo "=== 7. Installazione di AMICO/NODDI ==="
pip3 install --user git+https://github.com/daducci/AMICO.git
pip3 install --user git+https://github.com/daducci/NODDI.git
python3 -c "import amico; amico.setup()"

echo "=== 8. Aggiornamento variabili d'ambiente ==="
echo "export PATH=$INSTALL_DIR/bin:\$PATH" >> ~/.bashrc
echo "export FSLDIR=$INSTALL_DIR/fsl" >> ~/.bashrc
echo "export ANTSPATH=$INSTALL_DIR/ants/bin" >> ~/.bashrc
echo "export PATH=$FSLDIR/bin:$ANTSPATH:\$PATH" >> ~/.bashrc
source ~/.bashrc

echo "=== 9. Installazione completata in $INSTALL_DIR. Riavvia il terminale o esegui 'source ~/.bashrc' ==="

