#!/bin/bash
#jk @ 7/2024

RED='\033[0;31m'
YLW='\033[0;33m'
BLU='\033[0;34m'
GRN='\033[0;32m'
BCY='\033[1;36m'
CYA='\033[0;36m'
NCL='\033[0m' 

RET=_result-mnist.log

function check_result(){
	local r1=$1
	local r2=$2

	if [[ $r1 < 98.5 ]]
	then
		echo -e "avgtrain acc : ${GRN}PASS${NCL} $r1"
	else
		echo -e "avgtrain acc : ${RED}FAIL${NCL} $r1"
	fi

	if [[ $r2 < 0.077 ]] # 0.054 for 1 gpu
	then
		echo -e "avgtrain loss: ${GRN}PASS${NCL} $r2"
	else
		echo -e "avgtrain loss: ${RED}FAIL${NCL} $r2"
	fi
}

python mnist.py --batch-size=64 --epochs=1 --lr=1.0 --gamma=0.7 --hpu --autocast --save-model --data-path . | tee -a $RET

ret=$(tail -n 1 $RET | awk '{print $4, $7}')
r1=`echo $ret | awk '{print $1}'`
r2=`echo $ret | awk '{print $2}'`

mpirun -n 8 --bind-to core --map-by slot:PE=6 \
	--rank-by core --report-bindings \
	--allow-run-as-root \
	python mnist.py \
	--batch-size=64  \
	--epochs=1 \
	--lr=1.0 --gamma=0.7 \
	--hpu --autocast \
	--save-model \
	--data-path . | tee -a $RET

ret=$(tail -n 1 $RET | awk '{print $4, $7}')
r3=`echo $ret | awk '{print $1}'`
r4=`echo $ret | awk '{print $2}'`

date | tee -a $RET
echo
echo "check 1 GPU test result: "
check_result $r1, $r2
echo 

echo "check 8 GPU test result: "
check_result $r3, $r4

rm -rf __pycache__ .graph_dumps
