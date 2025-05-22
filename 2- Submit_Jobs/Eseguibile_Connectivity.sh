#!/bin/bash

export PBS_JOBID=$JOBID

mkdir $PBS_JOBID

cd $PBS_JOBID

/lustrehome/alacalamita/Test_Imm/2_create_connectivity_matrix_AL.sh
