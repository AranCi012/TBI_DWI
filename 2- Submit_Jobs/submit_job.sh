#!/bin/bash

#lancia (a condor) tutti i file che stanno nella cartella in cui lo esegui

for i in `ls -1 run*`; do
condor_submit $i;
# sleep 30
done
