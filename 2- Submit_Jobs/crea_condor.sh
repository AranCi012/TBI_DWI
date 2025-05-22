#!/bin/bash


for i in `ls -1 /lustrehome/alacalamita/Test_Imm/Script/*`

do
arg_clean=`basename $i `
arg_file=`echo ${arg_clean} | sed 's/.sh//g'`

echo -e "universe = vanilla\n">run_condor_${arg_file}
echo -e 'environment = "JOBID=$(Cluster).$(Process)"\n'>>run_condor_${arg_file}

#echo -e "getenv = True\n">>run_condor_${arg_file}

echo -e "executable = /lustrehome/alacalamita/Test_Imm/Script/${arg_clean}\n">>run_condor_${arg_file}

echo -e "log = /lustrehome/alacalamita/Test_Imm/log/log_${arg_file}_nout\n">>run_condor_${arg_file}
echo -e "error = /lustrehome/alacalamita/Test_Imm/log/err_${arg_file}_nout\n">>run_condor_${arg_file}
echo -e "output = /lustrehome/alacalamita/Test_Imm/log/out_${arg_file}_nout\n">>run_condor_${arg_file}

echo -e "request_cpus = 16\n">>run_condor_${arg_file}
echo -e "request_memory = 20G\n" >>run_condor_${arg_file}
echo -e "request_gpus = 1\n" >>run_condor_${arg_file}
echo -e "queue">>run_condor_${arg_file}

done
