# jkang, 4/17/2025

RED='\033[0;31m'
YLW='\033[0;33m'
BLU='\033[0;34m'
GRN='\033[0;32m'
BCY='\033[1;36m'
CYA='\033[0;36m'
NCL='\033[0m' 

alias gdl='tail -n 1 /var/log/habana_logs/qual/*.log  | grep -v == | grep .'

export GREP_COLORS='ms=01;33'
export __python_cmd=python3
GAUD=gaudi2
TIME=240
PCIE=gen4
DMON=" -dis_mon"
DRYR="no"
DRYT="no"

function check_hl_qual_log(){
	SUMMARY=''
	ls /var/log/habana_logs/qual/*.log &>/dev/null
	[[ $? != 0 ]] && return
	
	for f in $(ls /var/log/habana_logs/qual/*.log); do
		RESULT=$(tail -n 1   $f)
		COMMDQ=$(grep \.\/hl $f)
		echo -e "$RESULT    $COMMDQ"
		if [[ $RESULT =~ "FAILED" ]]; then
			SUMMARY+="retest    ${f}    $COMMDQ\n"
		fi
	done
	echo -e "\n"${SUMMARY}
}

function server_type(){
	# GD2 or GD3
	lspci | grep --color -P "accelerators.*1020" &>/dev/null
	if [[ $? != 0 ]]; then
		lspci | grep --color -P "accelerators.*Gaudi2" &>/dev/null
	fi
	[[ $? == 0 ]] && echo 'gd2' || echo 'gd3'	
}

function exec_cmd(){
	local start=$SECONDS
	[[ $DRYR =~ "yes" ]] && echo "$1" || eval "$1"
	local end=$SECONDS
	local duration=$((end - start))
	[[ $DRYR =~ "no" ]] && printf "  exec: %s s %s\n" $duration "$1"
}

# --------------------- main

if [[ "$1" =~ "log" ]]; then
	check_hl_qual_log
	exit 0
elif [[ "$1" =~ "mv" ]]; then
	LOGD=$(date '+%Y-%m-%d')
	mkdir -p /var/log/habana_logs/qual/$LOGD
	mv /var/log/habana_logs/qual/*.log /var/log/habana_logs/qual/$LOGD/
	exit 0
fi

[[ $* =~ "dry" ]] && DRYR="yes"
[[ $* =~ "dis" ]] && DMON=" -dis_mon" || DMON=""

SECONDS=0
echo -e "\n  hl_qual tests on ${GAUD}"

TYPE=$(server_type)
if [[ $TYPE == 'gd2' ]]; then
    PCIE=gen4
	echo "  reload driver with timeout_locked=0"

	if [[ $DRYR =~ "no" ]]; then
		rmmod habanalabs
		modprobe habanalabs timeout_locked=0
		echo
	fi
	echo "  reload done in ${SECONDS} s"
else
    PCIE=gen5
	GAUD=gaudi3
fi

cd /opt/habanalabs/qual/${GAUD}/bin
./manage_network_ifs.sh --up &>/dev/null
#./manage_network_ifs.sh --status

HLQ[1]="./hl_qual -${GAUD} ${DMON} -rmod parallel -c all -t ${TIME} -f2 -l extreme -serdes int"
HLQ[2]="./hl_qual -${GAUD} ${DMON} -rmod parallel -c all -t ${TIME} -f2 -l extreme"
HLQ[3]="./hl_qual -${GAUD} ${DMON} -rmod parallel -c all -t ${TIME} -f2 -l high"
HLQ[4]="./hl_qual -${GAUD} ${DMON} -rmod parallel -c all -t ${TIME} -f2"
HLQ[5]="./hl_qual -${GAUD} ${DMON} -rmod parallel -c all -t ${TIME} -s"
HLQ[6]="./hl_qual -${GAUD} ${DMON} -rmod parallel -c all -t ${TIME} -s -enable_ports_check int -l extreme -toggle"
HLQ[7]="./hl_qual -${GAUD} ${DMON} -rmod parallel -c all -t ${TIME} -p -b -gen ${PCIE}"
HLQ[8]="./hl_qual -${GAUD} ${DMON} -rmod parallel -c all -t ${TIME} -e2e_concurrency -enable_ports_check int -toggle"
HLQ[9]="./hl_qual -${GAUD} ${DMON} -rmod parallel -c all -mb -memOnly"
HLQ[10]="./hl_qual -${GAUD} ${DMON} -rmod parallel -c all -ser"
HLQ[11]="./hl_qual -${GAUD} ${DMON} -rmod parallel -c all -i 3 -full_hbm_data_check_test"
HLQ[12]="./hl_qual -${GAUD} ${DMON} -rmod parallel -c all -i 3 -hbm_dma_stress"
HLQ[13]="./hl_qual -${GAUD} ${DMON} -rmod parallel -c all -i 3 -hbm_tpc_stress"

HLQ[14]="./hl_qual -${GAUD} ${DMON} -rmod parallel -c all -t ${TIME} -e -Tw 1 -Ts 2 -sync -enable_ports_check int"
HLQ[15]="./hl_qual -${GAUD} ${DMON} -rmod parallel -c all -nic_base -enable_ports_check int -i 100 -sensors 10 -ep 50 -sz 134217728 -test_type allreduce"
HLQ[16]="./hl_qual -${GAUD} ${DMON} -rmod parallel -c all -nic_base -enable_ports_check int -i 100 -sensors 10 -ep 50 -sz 134217728 -test_type allgather"

HLQ[17]="./hl_qual -${GAUD} ${DMON} -rmod parallel -c all -nic_base -enable_ports_check int -i 100 -sensors 10 -sz 134217728 -toggle -test_type pairs"
HLQ[18]="./hl_qual -${GAUD} ${DMON} -rmod parallel -c all -nic_base -enable_ports_check int -i 100 -sensors 10 -sz 134217728 -toggle -test_type allreduce"
HLQ[19]="./hl_qual -${GAUD} ${DMON} -rmod parallel -c all -nic_base -enable_ports_check int -i 100 -sensors 10 -sz 134217728 -toggle -test_type allgather"
HLQ[20]="./hl_qual -${GAUD} ${DMON} -rmod parallel -c all -nic_base -enable_ports_check int -i 100 -sensors 10 -sz 134217728 -toggle -test_type bandwidth"
HLQ[21]="./hl_qual -${GAUD} ${DMON} -rmod parallel -c all -nic_base -enable_ports_check int -i 100 -sensors 10 -sz 134217728 -toggle -test_type dir_bw"
HLQ[22]="./hl_qual -${GAUD} ${DMON} -rmod parallel -c all -nic_base -enable_ports_check int -i 100 -sensors 10 -sz 134217728 -toggle -test_type loopback"

DRYT=$DRYR
DRYR='yes'	# list only
for (( i=1; i < 23; i++ )); do
	printf "  %2s " $i
	exec_cmd "${HLQ[$i]}"
done

echo -e "$YLW"
read -r -p "  confirm to run hl_qual tests (y/n)?" response
response=${response,,}
echo -e "$NCL"
if [[ $response =~ ^(y| ) ]] || [[ -z $response ]]; then
    echo "  continue ..."
else
    exit
fi

DRYR=$DRYT
for (( i=1; i < 23; i++ )); do
	printf "  %2s " $i
	exec_cmd "${HLQ[$i]}"
done

cd - &>/dev/null

check_hl_qual_log
echo -e "\n  tested in $SECONDS seconds"
