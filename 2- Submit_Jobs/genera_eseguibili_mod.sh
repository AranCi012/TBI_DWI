#!/bin/bash

# for i in `ls -1 /lustrehome/alacalamita/Test_Imm/Images/*/`
for dir in /lustrehome/alacalamita/Test_Imm/Images/*/; do
# do
#m=250
#let "t=$i*$m"

#echo $t
arg_clean=${dir%/}
# arg_file=`echo ${arg_clean} | sed 's/.R//g'`
# echo ${arg_clean}
# echo "${arg_clean##*/}"
arg_file="${arg_clean##*/}"

a=#
b=!
c=/bin/bash

echo -e "$a$b$c\n" > /lustrehome/alacalamita/Test_Imm/Script/${arg_file}.sh

echo -e "export PBS_JOBID=\$JOBID\n" >>/lustrehome/alacalamita/Test_Imm/Script/${arg_file}.sh

echo -e "mkdir \$PBS_JOBID\n">>/lustrehome/alacalamita/Test_Imm/Script/${arg_file}.sh
echo -e "cd \$PBS_JOBID\n">>/lustrehome/alacalamita/Test_Imm/Script/${arg_file}.sh

echo -e "/lustrehome/alacalamita/Test_Imm/1_dwi_processing_tractography_AL.sh ${arg_clean} /lustrehome/alacalamita/Test_Imm/Proc_Im /lustrehome/alacalamita/Test_Imm/HarvardOxford-cort.nii" >> /lustrehome/alacalamita/Test_Imm/Script/${arg_file}.sh

done

chmod +x *
