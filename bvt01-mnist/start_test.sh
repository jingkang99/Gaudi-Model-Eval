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
		echo -e "avgtrain acc : ${GRN}PASS${NCL} $r1" | tee -a $RET
	else
		echo -e "avgtrain acc : ${RED}FAIL${NCL} $r1" | tee -a $RET
	fi

	if [[ $r2 < 0.077 ]] # 0.054 for 1 gpu
	then
		echo -e "avgtrain loss: ${GRN}PASS${NCL} $r2" | tee -a $RET
	else
		echo -e "avgtrain loss: ${RED}FAIL${NCL} $r2" | tee -a $RET
	fi
}

SECONDS=0
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

mkdir -p checkpoints &>/dev/null
python example.py | tee -a $RET

# Training
ret=$(tail -n 2 $RET | head -n 1 | awk '{print $4, $9}')
r5=`echo $ret | awk '{print $1}'`
r6=`echo $ret | awk '{print $2}'`

# Testing 
ret=$(tail -n 1 $RET | awk '{print $4, $9}')
r7=`echo $ret | awk '{print $1}'`
r8=`echo $ret | awk '{print $2}'`

echo -e "test result on "$(date) | tee -a $RET
echo
echo "check 1 GPU test result: "
check_result $r1, $r2
echo 

echo "check 8 GPU test result: "
check_result $r3, $r4
echo

echo "lazy mode train & test: "

if [[ $r5 < 0.056 && $r6 > 98.50 ]] # Training
then
	echo -e "training acc : ${GRN}PASS${NCL} $r6" | tee -a $RET
else
	echo -e "training acc : ${RED}FAIL${NCL} $r6" | tee -a $RET
fi

if [[ $r7 < 0.079 && $r8 > 97.5 ]] # Training
then
	echo -e "testing  acc : ${GRN}PASS${NCL} $r8" | tee -a $RET
else
	echo -e "testing  acc : ${RED}FAIL${NCL} $r8" | tee -a $RET
fi

rm -rf __pycache__ .graph_dumps checkpoints

echo -e "test compeleted in $SECONDS" | tee -a $RET
