# jkang, 4/17/2025

RED='\033[0;31m'
YLW='\033[0;33m'
BLU='\033[0;34m'
GRN='\033[0;32m'
BCY='\033[1;36m'
CYA='\033[0;36m'
NCL='\033[0m' 

LC_CTYPE=C

alias gdl='tail -n 1 /var/log/habana_logs/qual/*.log  | grep -v == | grep .'
alias oam='hl-smi -L | grep "CPLD Version" -B 15 | grep -P "accel|Serial|SPI|CPLD"'
alias spi='hl-smi -q | grep SPI'
alias cpld='hl-smi -q| grep "CPLD Ver"'
alias erom='hl-smi --fw-version | grep erom -A 1 | grep  gaudi'
alias apth='apt list --installed | grep haba'
alias oopt="cat /sys/class/accel/accel*/device/status"
alias pcnt='hl-smi -Q bus_id -f csv,noheader | xargs -I % hl-smi -i % -n link | grep UP | wc -l'
alias erom='hl-smi --fw-version | grep erom -A 1 | grep  gaudi'
alias gck='/opt/habanalabs/qual/gaudi2/bin/manage_network_ifs.sh --status'
alias hccx='HCCL_COMM_ID=127.0.0.1:5555 python3 run_hccl_demo.py --nranks 8 --node_id 0 --size 1g  --test all_reduce --loop 100000 --ranks_per_node 8'
alias hccl="HCCL_COMM_ID=127.0.0.1:5555 python3 run_hccl_demo.py --nranks 8 --node_id 0 --size 32m --test all_reduce --loop 1000   --ranks_per_node 8"
alias ll='ls -alF'
alias ipp='ifconfig | grep '\''inet '\'' | grep -v 127.0 | awk '\''{print $2}'\'''
alias itb='strings /lib/firmware/habanalabs/gaudi*/gaudi*-agent-fw_loader-fit.itb | grep -i "Ppboot.*version " | head -n 1'

export GREP_COLORS='ms=01;33'
export __python_cmd=python3
GAUD=gaudx
TIME=240
PCIE=gen4
DMON=" -dis_mon"
DRYR="no"
DRYT="no"
SNSR=""
SPIN=("—" "\\" "|" "/")

function server_type(){
	lspci | grep --color -P "accelerators.*(1020|Gaudi2)" &>/dev/null
	[[ $? == 0 ]] && echo 'gaudi2'  || echo 'gaudi3'
}

spinner() {
	local frameRef
	local commd="${1}"
	local label="${2-  exec} "
	local spinnerRef="${3-SPIN}"
	local spinnerFrames=$(eval "echo \${!${spinnerRef}[@]}")

	spinnerRun() {
		while true; do
		  for frame in ${spinnerFrames[@]}; do
			frameRef="${spinnerRef}[${frame}]"
			echo "${label}${!frameRef}"
			tput cuu1 
			sleep 0.2
		  done
		done
		echo -e "\r"
	}

	spinnerRun &
	local spinnerPid=$!
	echo ${commd}

	pcnt=$(hl-smi -Q bus_id -f csv,noheader | xargs -I % hl-smi -i % -n link | grep UP | wc -l)
	#if [[ ${commd} =~ " -Tw" ]] && [[ ${pcnt} -lt 168 ]]; then
	if [[ ${pcnt} -lt 168 ]]; then
		#GAUD=$(server_type)
		#/opt/habanalabs/qual/${GAUD}/bin/manage_network_ifs.sh --down &>/dev/null
		#/opt/habanalabs/qual/${GAUD}/bin/manage_network_ifs.sh --up   &>/dev/null
		#sleep 40
		echo -e "  ${YLW}some internal ports down${NCL}"
	fi

	${commd} &>/dev/null
	kill -9 "${spinnerPid}" 
	wait $!  2>/dev/null
}

function delta(){
	date1_seconds=$(date -d "$1" +"%s")
	date2_seconds=$(date -d "$2" +"%s")
	duration=$(( $date2_seconds - $date1_seconds ))

	if [[ $3 == "-h" ]]; then
		printf "%02d hr %02d min %02d sec" $(($duration/3600)) $(($duration %3600 / 60)) $(($duration % 60))
	else 	
		printf "%02d:%02d" $(($duration %3600 / 60)) $(($duration % 60))
	fi
}

function check_hl_qual_log(){
	SUMMARY=''
	ls /var/log/habana_logs/qual/*.log &>/dev/null
	[[ $? != 0 ]] && return

	for f in $(ls /var/log/habana_logs/qual/*.log); do
		RESULT=$(grep "hl qual report" $f -A 1 | tail -n 1)

		COMMDQ=$(grep -P ^\.\/hl_qual $f)

		# start time
		h_sts=$(grep -i "starting config function" $f | sort -n | head -n 1 | awk -F'[' '{print $2}' | awk -F']' '{print $1}' )
		[[ -z $h_sts ]] && h_sts=$(grep -i "Start running plugin" $f | sort -n | head -n 1 | awk -F'[' '{print $2}' | awk -F']' '{print $1}' )

		# finish time
		h_ets=$(grep -i "Finish running plugin with" $f | sort -n | tail -n 1)
		h_ets=$([[ $h_ets =~ \[([0-9]{2}.*)\] ]] && echo ${BASH_REMATCH[1]})

		h_sts=$(echo $h_sts | sed "s/ //g")
		h_ets=$(echo $h_ets | sed "s/ //g")

		etime=$(delta $h_sts $h_ets)
		
		echo -e "$RESULT    $etime    $COMMDQ"
		if [[ $RESULT =~ "FAILED" ]]; then
			SUMMARY+="retest    ${f}    $COMMDQ\n"
		fi
	done
	[[ -n $SUMMARY ]] && echo -e "\n"${SUMMARY}
}

function exec_cmd(){
	local start=$SECONDS
	[[ $DRYR =~ "yes" ]] && echo "$1" || eval "$1"
	local end=$SECONDS
	local duration=$((end - start))
	[[ $DRYR =~ "no" ]] && printf "  exec: %s s %s\n" $duration "$1"
}

# --------------------- main
CDIR=$(pwd)
TYPE=$(server_type)

if [[ ! -f /opt/habanalabs/src/hl-thunk/tests/arc/arc/scheduler.bin ]]; then
	mkdir -p /opt/habanalabs/src/hl-thunk/tests/arc/arc
	ln -s /opt/habanalabs/src/hl-thunk/tests/arc/scheduler.bin /opt/habanalabs/src/hl-thunk/tests/arc/arc/scheduler.bin
	ln -s /opt/habanalabs/src/hl-thunk/tests/arc/engine.bin    /opt/habanalabs/src/hl-thunk/tests/arc/arc/engine.bin
fi

if [[ "$1" =~ "log" ]]; then
	check_hl_qual_log
	exit 0
elif [[ "$1" =~ "mv" ]]; then
	SNM=$(ipmitool fru | grep "Board Serial" | awk -F': ' '{print $2}')
	BID=$(hl-smi -L | grep accel0 | awk -F':' '{print $2}')
	SNO=$(hl-smi -L | grep accel0 -A 15 | grep "Serial Number" | awk -F': ' '{print $2}')
	SPI=$(hl-smi -L | grep accel0 -A 15 | grep SPI | awk -F'-' '{print $3}')
	CPL=$(hl-smi -L | grep accel0 -A 15 | grep CPLD | awk '{print $7}')
	FWV=$(hl-smi --version | awk -F'-' '{print $3}')
	KNV=$(uname -r | awk -F'-' '{print $1}')
	DAT=$(date '+%Y-%m-%d')
	LBL=${SNM}_${KNV}_${BID}_${SNO}_${SPI}_${FWV}_${CPL}_${DAT}

	mkdir -p /var/log/habana_logs/qual/$LBL
	mkdir -p /var/log/habana_logs/qual/$LBL/sysinfo
	mv /var/log/habana_logs/qual/*.log /var/log/habana_logs/qual/$LBL/
	echo "logs moved"

	cd /var/log/habana_logs/qual/$LBL/sysinfo; \
	dmesg  > _dmesg.l;\
	ps -ef > _ps.l; \
	pstree > _ps.t; \
	hl-smi -L > _hl-smi.l; \
	hl-smi    > _hl-smi.0; \
	apt list --installed | tee _apt.l &>/dev/null; \
	uname -a  > _uname.l;  \
	ipmitool sdr > _sdr.1; \
	ipmitool fru > _fru.1; \
	ipmitool sel elist > _elist.1;  \
	ipmitool sensor    > _sensor.1; \
	ipmitool raw 0x30 0x70 0xEF 0x02 0xEC 0x43 0x0C 0x9E 0x01 0x01 >  _ubb.1; \
	ipmitool raw 0x30 0x70 0xef 0x02 0xec 0x42 0x0c 0x68 0x01 0x01 >> _ubb.1; \
	systemctl --type=service --state=running > _service.l; \
	cat /etc/os-release > _os.1; \
	hl-smi -L | grep "CPLD Version" -B 15 | grep -P "accel|Serial|SPI|CPLD" > _oam.1; \
	hl-smi -q | grep "CPLD Ver" > _cpld.1; \
	hl-smi -q | grep SPI        > _spi.1;  \
	tar czf ts-spm.tgz /var/log/syslog /var/log/kern.log /var/log/habana_logs _dmesg.l _ps.l _ps.t _service.l _hl-smi.l _hl-smi.0 _apt.l _uname.l _elist.1 _sdr.1 _fru.1 _sensor.1 _ubb.1 _os.1 _oam.1 _cpld.1 _spi.1 &>/dev/null; \
	cd - &>/dev/null

	ping -W 1 -c 1 172.30.195.148 &>/dev/null
	[[ $? == 0 ]] && \
	sshpass -p 'smc123' rsync -avi -e "ssh -o StrictHostKeyChecking=no" /var/log/habana_logs/qual/$LBL spm@172.30.195.148:/home/spm/hl_qual_test_results

	exit 0
fi

[[ $* =~ "dry" ]] && DRYR="yes"
[[ $* =~ "dis" ]] && DMON=" -dis_mon"   || DMON=""

PORTCHECK=''
[[ "$*" =~ port.*check ]] && PORTCHECK="-enable_ports_check int"

RELAODDRV=''
[[ "$*" =~ reload.* ]] && RELAODDRV="reload driver"

SECONDS=0
if [[ $TYPE == 'gaudi2' ]]; then
    PCIE=gen4
	echo "  reload driver with timeout_locked=0"

	if [[ $DRYR =~ "no" ]] && [[ ! -z $RELAODDRV ]]; then
		rmmod habanalabs &>/dev/null
		modprobe habanalabs timeout_locked=0 &>/dev/null
	fi
	echo "  reload done in ${SECONDS} s"
	echo
	GAUD=gaudi2
	SNSR="-sensors 10"
else
	SNSR=""
    PCIE=gen5
	GAUD=gaudi3
fi
echo -e "\n  hl_qual tests on ${GAUD}"

cd /opt/habanalabs/qual/${GAUD}/bin
./manage_network_ifs.sh --up &>/dev/null

HLQ[1]="./hl_qual -${GAUD} ${DMON} -rmod parallel -c all -t ${TIME} -f2 -l extreme -serdes int"
HLQ[2]="./hl_qual -${GAUD} ${DMON} -rmod parallel -c all -t ${TIME} -f2 -l extreme"
HLQ[3]="./hl_qual -${GAUD} ${DMON} -rmod parallel -c all -t ${TIME} -f2 -l high"
HLQ[4]="./hl_qual -${GAUD} ${DMON} -rmod parallel -c all -t ${TIME} -f2"
HLQ[5]="./hl_qual -${GAUD} ${DMON} -rmod parallel -c all -t ${TIME} -s ${PORTCHECK} -toggle"
HLQ[6]="./hl_qual -${GAUD} ${DMON} -rmod parallel -c all -t ${TIME} -p -b -gen ${PCIE}"
HLQ[7]="./hl_qual -${GAUD} ${DMON} -rmod serial   -c all -t 20 -p -b"

HLQ[8]="./hl_qual -${GAUD} ${DMON} -rmod parallel -c all -t ${TIME} -e2e_concurrency ${PORTCHECK} -toggle"
HLQ[9]="./hl_qual -${GAUD} ${DMON} -rmod parallel -c all -mb -memOnly"
HLQ[10]="./hl_qual -${GAUD} ${DMON} -rmod parallel -c all -ser"
HLQ[11]="./hl_qual -${GAUD} ${DMON} -rmod parallel -c all -i 3 -full_hbm_data_check_test"
HLQ[12]="./hl_qual -${GAUD} ${DMON} -rmod parallel -c all -i 3 -hbm_dma_stress"
HLQ[13]="./hl_qual -${GAUD} ${DMON} -rmod parallel -c all -i 3 -hbm_tpc_stress"

HLQ[14]="./hl_qual -${GAUD} ${DMON} -rmod parallel -c all -t ${TIME} -e -Tw 1 -Ts 2 -sync ${PORTCHECK}"
HLQ[15]="./hl_qual -${GAUD} ${DMON} -rmod parallel -c all -nic_base ${PORTCHECK} -i 100 ${SNSR} -ep 50 -sz 134217728 -test_type allreduce"
HLQ[16]="./hl_qual -${GAUD} ${DMON} -rmod parallel -c all -nic_base ${PORTCHECK} -i 100 ${SNSR} -ep 50 -sz 134217728 -test_type allgather"

HLQ[17]="./hl_qual -${GAUD} ${DMON} -rmod parallel -c all -nic_base ${PORTCHECK} -i 100 ${SNSR} -sz 134217728 -toggle -test_type pairs"
HLQ[18]="./hl_qual -${GAUD} ${DMON} -rmod parallel -c all -nic_base ${PORTCHECK} -i 100 ${SNSR} -sz 134217728 -toggle -test_type allreduce"
HLQ[19]="./hl_qual -${GAUD} ${DMON} -rmod parallel -c all -nic_base ${PORTCHECK} -i 100 ${SNSR} -sz 134217728 -toggle -test_type allgather"
HLQ[20]="./hl_qual -${GAUD} ${DMON} -rmod parallel -c all -nic_base ${PORTCHECK} -i 100 ${SNSR} -sz 134217728 -toggle -test_type bandwidth"
HLQ[21]="./hl_qual -${GAUD} ${DMON} -rmod parallel -c all -nic_base ${PORTCHECK} -i 100 ${SNSR} -sz 134217728 -toggle -test_type dir_bw"
HLQ[22]="./hl_qual -${GAUD} ${DMON} -rmod parallel -c all -nic_base ${PORTCHECK} -i 100 ${SNSR} -sz 134217728 -toggle -test_type loopback"

FROM=1
TOTO=${#HLQ[@]}
if [[ "$*" =~ "from" ]]; then
	FROM=$(echo $* | awk -F 'from' '{print $2}' | awk '{print $1}')
	TOTO=$(echo $* | awk -F 'to'   '{print $2}' | awk '{print $1}')
fi

DRYT=$DRYR
DRYR='yes'
for (( i=${FROM}; i <= ${TOTO}; i++ )); do
	printf "  %2s " $i
	exec_cmd "${HLQ[$i]}"
done
[[ $DRYT =~ "yes" ]] && exit

echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor &>/dev/null
echo 1 | tee /sys/devices/system/cpu/cpu*/cpuidle/state2/disable &>/dev/null

echo -e "$YLW"
read -r -p "  confirm to run hl_qual tests ${FROM} to ${TOTO} (y/n)?" response
response=${response,,}
echo -e "$NCL"
if [[ $response =~ ^(y| ) ]] || [[ -z $response ]]; then
    echo "  continue ..."
else
    exit
fi

# start test
DRYR=$DRYT
for (( i=$FROM; i <= $TOTO; i++ )); do
	printf "  %-2s " $i
	spinner "${HLQ[$i]}"
	#${CDIR}/spincmdln ${HLQ[$i]}
done

cd - &>/dev/null

check_hl_qual_log
echo -e "\n  hl_qual tested in ${BCY}$SECONDS ${NCL}seconds"
