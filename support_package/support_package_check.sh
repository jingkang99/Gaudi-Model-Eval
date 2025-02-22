#!/usr/bin/bash

# Supermiro Gaudi Support Package
# Jing Kang 8/2024

GD2=1 && GD3=1
GMODEL=`hl-smi -L | head -n 12 | grep Product | awk '{print $4}'`
[[ $GMODEL =~ 'HL-225' ]] && GD2=0 || GD3=0

HLQ=""
[ $GD2 == 0 ] && { GPATH="/opt/habanalabs/qual/gaudi2/bin"; HLQ="-gaudi2"; }
[ $GD3 == 0 ] && { GPATH="/opt/habanalabs/qual/gaudi3/bin"; HLQ="-gaudi3"; }
export PATH=.:$GPATH:$PATH
export __python_cmd=python3

GLOG=/var/log/habana_logs/qual

#HABANALABS_HLTHUNK_TESTS_BIN_PATH=/opt/habanalabs/src/hl-thunk/tests
#HABANA_PLUGINS_LIB_PATH=/usr/lib/habanatools/habana_plugins
#RDMA_CORE_ROOT=/opt/habanalabs/rdma-core/src 
#GC_KERNEL_PATH=/usr/lib/habanalabs/libtpc_kernels.so
#RDMA_CORE_LIB=/opt/habanalabs/rdma-core/src/build/lib

#----

SRC=`readlink -f "${BASH_SOURCE[0]}" 2>/dev/null||echo $0`
CUR=`dirname "${SRC}"`
PAR=`dirname "${CUR}"`

TESTCASE_ID=0
SYSTEM_INFO=0
SUPPORT_PKG=0
L_TESTCASES=0
HABAPYTORCH=0
EXETESTNOTE=""

OUTPUT=./gd-spkg
PDUCHK=-1
TRAINL=$OUTPUT/_traing.log

RED='\033[0;31m'
YLW='\033[0;33m'
BLU='\033[0;34m'
GRN='\033[0;32m'
BCY='\033[1;36m'
CYA='\033[0;36m'
NCL='\033[0m' 

function print_synopsis() {
cat << EOF
NAME
        `basename $0`

SYNOPSIS
        `basename $0` [-t <test-case>] [-p] [-s] [-h]

DESCRIPTION
        Gaudi Server Heath Check and Diagnostic Toolkit

        -l, --list-test-case
            list all test cases' function description

        -t <test-case-id | all>, --test <test-case-id | all>
            run a specified test case or all cases

        -n <"description">, --note <"description"l>
            add a test note to the report

        -p, --print-system-info
            print out system hardware and software infomation

        -s, --sendout-support-package
            run all cases and send out the result along with system ino 

        -h, --help
            print this help message

        -v, --version
            print support_package_check version

EXAMPLES
       `basename $0` -t all

EOF
}

function check_gpu_oam_cpld(){
	[[ $GD2 == 0 ]] && \
	OAM_CPLDS=$(  \
		ipmitool raw 0x30 0x70 0xef 4 0x70 0x40 0xe6 0x40 2 0x4a 1 0x0; \
		ipmitool raw 0x30 0x70 0xef 4 0x70 0x40 0xe6 0x41 2 0x4a 1 0x0; \
		ipmitool raw 0x30 0x70 0xef 4 0x70 0x40 0xe6 0x42 2 0x4a 1 0x0; \
		ipmitool raw 0x30 0x70 0xef 4 0x70 0x40 0xe6 0x43 2 0x4a 1 0x0; \
		ipmitool raw 0x30 0x70 0xef 4 0x70 0x40 0xe6 0x44 2 0x4a 1 0x0; \
		ipmitool raw 0x30 0x70 0xef 4 0x70 0x40 0xe6 0x45 2 0x4a 1 0x0; \
		ipmitool raw 0x30 0x70 0xef 4 0x70 0x40 0xe6 0x46 2 0x4a 1 0x0; \
		ipmitool raw 0x30 0x70 0xef 4 0x70 0x40 0xe6 0x47 2 0x4a 1 0x0  )

	[[ $GD3 == 0 ]] && \
	OAM_CPLDS=$(  \
		ipmitool raw 0x30 0x70 0xEF 0x02 0xEC 0x43 0x0C 0x9E 0x01 0x01; \
		ipmitool raw 0x30 0x70 0xef 2    0xec 0x42 0x0c 0x68 0x1 0x01 )
}

# check Gaudi interal ports 
function check_gpu_int_port(){
	UP_PORTS=$(hl-smi -Q bus_id -f csv,noheader | xargs -I % hl-smi -i % -n link | grep UP | wc -l)
	if [ $UP_PORTS != 168 ]
	then
		echo -e "${RED}ERROR: Gaudi internal ports Not All Up - $UP_PORTS${NCL}"
		echo -e "${GRN}  /opt/habanalabs/qual/gaudi2/bin/manage_network_ifs.sh --up${NCL}"
			echo -e "${GRN}  reboot or reload habana driver${NCL}"
		echo -e "${GRN}  rmmod habanalabs${NCL}"
		echo -e "${GRN}  modprobe habanalabs${NCL}\n"
		echo -e "${GRN}  $(basename $0) --check-ports${NCL}\n"
		exit 1
	fi
}

function parse_args(){

	if [[ -z $1 ]]; then
		TESTCASE_ID=0
		SYSTEM_INFO=1
		SUPPORT_PKG=0
		return
	fi

    while [ -n "$1" ]; do
        case "$1" in
            -t | --test | -e | --exec )
				if [[ -z $2 ]]; then
					print_synopsis
					exit 1
				fi
                TESTCASE_ID=$2
                shift 2
                ;;
            -n | --note )
				if [[ -z $2 ]]; then
					print_synopsis
					exit 1
				fi
                echo "###" > _testnt.txt
				echo "$2" >> _testnt.txt
				EXETESTNOTE=$2
                shift 2
                ;;
			-q | --query )
				if [[ -z $2 ]]; then
					print_synopsis
					exit 1
				fi
				echo -e "  GDCASE GDRESULT GDSUPPORT for Support Package\n"
				qdb=$(printf "%s %s" "select * from" $2)
				echo "$qdb" > qdb.sql
				exec_psql_sql_file qdb.sql
				rm -rf qdb.sql &>/dev/null
				exit 0
				;;
            -l | --list-test-case )
                L_TESTCASES=1
                shift 1
                ;;
            -p | --print-system-info )
                SYSTEM_INFO=1
                shift 1
                ;;
            -s | --sendout-support-package )
                SUPPORT_PKG=1
                shift 1
                ;;
            -cp | --check-ports)
                UP_PORTS=$(hl-smi -Q bus_id -f csv,noheader | xargs -I % hl-smi -i % -n link | grep UP | wc -l)
				echo -e "${YLW}Gaudi internal ports UP count: ${UP_PORTS}${NCL}"
				[ $UP_PORTS == 168 ] && (echo -e "${GRN}OK${NCL}") || (echo -e "${RED}NG${NCL}")
				
				hpage=$(grep HugePages_Total /proc/meminfo | awk '{print $2}') 
				echo -e "\n${YLW}Hugepages  :${NCL} ${GRN}${hpage}${NCL}"

				govnor=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
				echo -e "\n${YLW}CPU Scaling:${NCL} ${GRN}${govnor}${NCL}"
                exit 0 ;;
            -co | --check-oam)
				check_gpu_oam_cpld
				echo -e "${YLW}OAM CPLD Version:${NCL} " $OAM_CPLDS
                exit 0 ;;
			-sh | --set-hugepage)
				echo -e "${YLW}set scaling_governor to performance${NCL}"
				echo -e "${YLW}set vm.nr_hugepages  to 153600${NCL}"
                echo performance | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
				sysctl -w vm.nr_hugepages=153600
                exit 0 ;;
            -rd | --reload-driver)
				reload_hl_drivers
                exit 0 ;;
            -hq | --hl_qual)
				echo -e "${YLW}hl_qual Verification Order${NCL}"
				print_hl_qual_plan
				exit 0 ;;
            -m | --matrix)
				echo -e "${YLW}Latest Support Matrix${NCL}"
				support_matrix
				exit 0 ;;
            -h | --help )
                print_synopsis
                exit 0
                ;;
            -v | --version )
                echo "0.1"
                exit 0
                ;;
			* )
                echo "error: invalid parameter: $1"
                print_synopsis
                exit 1
                ;;
        esac
    done
}

function support_matrix(){
	Support_Matrix=/tmp/Support_Matrix.html
	curl -s  https://docs.habana.ai/en/latest/Support_Matrix/Support_Matrix.html -o $Support_Matrix

	mapfile -t modl < <(grep "SPI Firmware"			$Support_Matrix -B 2 | grep HL |  awk -F'[<|>]' '{print $9}' )
	mapfile -t fwhl < <(grep "Intel Gaudi Software"	$Support_Matrix -A 2 | grep "Build Number" -A 2 | grep 1.1 |  awk -F'[<|>]' '{print $5}' )
	mapfile -t spiv < <(grep "SPI Firmware"			$Support_Matrix -A 1 | grep fw | awk -F'[<|>]' '{print $5}' )
	mapfile -t cpld < <(grep "class.*HL-"			$Support_Matrix -A 8 | grep CPLD -A 1 | awk -F'[<|>]' '{print $5}' | grep . )

	mapfile -t pcie < <(grep "PCIe Retimer"			$Support_Matrix -A 1 | grep -v strong |  awk -F'[<|>]' '{print $5}'  | grep . )
	mapfile -t serd < <(grep "SerDes Retimer"		$Support_Matrix -A 1 | grep -v strong |  awk -F'[<|>]' '{print $5}'  | grep . )

	optimum=`egrep "Optimum for Intel Gaudi.*footnote" $Support_Matrix -A 1 -m 1 | tail -n 1 | awk -F'>' '{print $4}' | awk -F'<' '{print $1}'`
	transformers=`egrep "Transformers" $Support_Matrix -A 2 -m 1 | tail -n 1 | awk -F'>' '{print $4}' | awk -F'<'  '{print $1}'`
	pytorch=`grep "strong.*PyTorch<" $Support_Matrix   -A 1 -m 1 | tail -n 1 | awk -F'>' '{print $3}' | awk -F'- ' '{print $1}'`
	ray=`egrep "strong.*Ray<"        $Support_Matrix   -A 1 -m 1 | tail -n 1 | awk -F'>' '{print $3}' | awk -F'<'  '{print $1}'`
	lightning=`egrep "strong.*PyTorch Lightning<"   $Support_Matrix -A 5 -m 1 | tail -n 1 | awk -F'>' '{print $4}' | awk -F'<' '{print $1}'`
	tgi=`egrep "strong.*Text Generation Inference<" $Support_Matrix -A 2 -m 1 | tail -n 1 | awk -F'>' '{print $4}' | awk -F'<' '{print $1}'`

	printf "Gaudi  %10s %15s %20s %10s %20s %20s\n" "Model" "Software" "SPI Firmware" "CPLD" "PCIE Retimer" "SerDes Retimer" 
	printf "    3  %10s %15s %20s %10s %20s %20s\n" ${modl[0]} ${fwhl[0]} ${spiv[0]} ${cpld[0]} ${pcie[0]} ${serd[0]}
	printf "    2  %10s %15s %20s %10s %20s %20s\n" ${modl[1]} ${fwhl[1]} ${spiv[1]} ${cpld[1]} ${pcie[1]} ${serd[1]}
	echo

	printf "    pytorch      %10s\n" $pytorch
	printf "    optimum      %10s\n" $optimum
	printf "    transformers %10s\n" $transformers
	printf "    lightning    %10s\n" $lightning
	printf "    ray          %10s\n" $ray
	printf "    TGI          %10s\n" $tgi

	#rm -rf $Support_Matrix &>/dev/null
}

function prerun-syscheck(){
	SECONDS=0
	
	wget -q --spider http://google.com &>/dev/null
	[ $? -eq 0 ] && INTERNET=0 || INTERNET=1

	apt install -y ipmitool expect sqlite3 postgresql-client sysstat zip libsigsegv2 git &>/dev/null
	pip3 install numpy  &>/dev/null

	BUSY=$(hl-smi |  grep "N/A   N/A    N/A" | wc -l)
	if [ $BUSY -ne 8 ]
	then
		echo -e "${RED}Warn: Not All 8 GPU Available - $BUSY ${NCL}"
		clean_runner
		BUSY=$(hl-smi |  grep "N/A   N/A    N/A" | wc -l)
		if [[ $BUSY -ne 8 ]]; then
			gcn=$(hl-smi -L | grep "Bus Id" | awk '{print $4}' |  sed 's/0000://')
			mkdir -p $OUTPUT

			check_oam "b3:00.0" 0
			check_oam "19:00.0" 1
			check_oam "1a:00.0" 2
			check_oam "b4:00.0" 3
			check_oam "43:00.0" 4
			check_oam "44:00.0" 5
			check_oam "cc:00.0" 6
			check_oam "cd:00.0" 7
			exit 1
		fi
	fi

	start_time=$(date +%s)
	start_YYYY=$(date '+%Y-%m-%d %H:%M:%S' -d @$start_time)

	check_gpu_int_port

	which ipmitool &>/dev/null
	[ $? != 0 ] && (echo -e "${RED}ERROR: need ipmitool${NCL}"; exit 2)

	which expect &>/dev/null
	[ $? != 0 ] && (echo -e "${RED}ERROR: need expect${NCL}"; exit 2)

	which sqlite3 &>/dev/null
	[ $? != 0 ] && (echo -e "${RED}ERROR: need sqlite3${NCL}"; exit 2)

	which psql &>/dev/null
	[ $? != 0 ] && (echo -e "${RED}ERROR: need psql - postgresql-client${NCL}"; exit 2)

	tmpf=`mktemp`

	echo -e "  ${YLW}Prep Support Package${NCL}" $start_YYYY | tee -a $tmpf
	echo -e "  ${YLW}Gaudi internal ports UP count :${NCL}" ${UP_PORTS} | tee -a $tmpf

	echo -e "  ${YLW}Model    :${NCL}" ${GMODEL} | tee -a $tmpf

	check_gpu_oam_cpld
	echo -e "  ${YLW}OAM CPLD :${NCL}" $OAM_CPLDS | tee -a $tmpf
	fwver=$(hl-smi --version | awk '{print $4}' | head -n 1)
	echo -e "  ${YLW}Firmware :${NCL}" $fwver | tee -a $tmpf

	get_external_ip_info
	echo -e "  ${YLW}Location :${NCL}" $city, $region $postal| tee -a $tmpf

	loip=$(ifconfig | grep broadcast | grep -v 172.17 | awk '{print $2}')
	echo -e "  ${YLW}Local IP :${NCL}" $loip | tee -a $tmpf
	echo -e "  ${YLW}Extnl IP :${NCL}" $exip | tee -a $tmpf

	pip list | grep habana &>/dev/null
	if ! [ $? -eq 0 ]; then
		#echo -e "  ${RED}warn: habana python module not found, skip LLM test${NCL}"
		echo -e "  ${YLW}HL Python:${NCL}" No | tee -a $tmpf
		HABAPYTORCH=-1
	else 
		HABAPYTORCH=0
	fi

	mpiver=$(ls /opt/habanalabs/ | grep openmpi | cut -b 9-)
	export PATH=/opt/python-llm/bin:/opt/habanalabs/openmpi-${mpiver}/bin:${PAR}/tool:$PATH
	export PT_HPU_LAZY_MODE=1
	echo -e "  ${YLW}Env Check:${NCL}" ${SECONDS} | tee -a $tmpf
}

function start_sys_mon(){
	#echo "  start sys mon:" $(date)

	watch -n 10 "ipmitool dcmi power reading | grep Instantaneous | awk '{print \$4}' | tee -a $OUTPUT/_powerr.log" &>/dev/null &
	watch -n 30 "ipmitool sdr   | tee -a $OUTPUT/_im-sdr.log" &>/dev/null &
	watch -n 30 "ipmitool sensor| tee -a $OUTPUT/_im-ssr.log" &>/dev/null &

	hl-smi -Q timestamp,index,serial,bus_id,memory.used,temperature.aip,utilization.aip,power.draw -f csv,noheader -l 10 | tee $OUTPUT/_hl-smi.log &>/dev/null &

	watch -n 30 "S_COLORS=always iostat -xm | grep -v loop | tee -a $OUTPUT/_iostat.log" &>/dev/null &
	watch -n 30 "ps -Ao user,pcpu,pid,command --sort=pcpu | grep python | head -n 50 | tee -a $OUTPUT/_python.log" &>/dev/null &

	mpstat 30 | tee $OUTPUT/_mpstat.log  &>/dev/null & 
	free -g -s 30 | grep Mem | tee $OUTPUT/_memmon.log &>/dev/null &

	# check PDU ip and start monitor
	if [[ $PDUCHK -eq 0 ]]; then
		bash ${CUR}/monitor-pwrdu-status.sh | tee $OUTPUT/_pdulog.log &>/dev/null &
	else
		echo "0 0 0 0 0 0" > $OUTPUT/_pdulog.log
	fi

	cat $tmpf > $TRAINL
	rm  $tmpf

	# save open listening ports
	(sleep 5 && netstat -lntp > $OUTPUT/_openpt.log) &
}

function stop_sys_mon(){
	#echo -e "\n  stop  sys mon: $SECONDS"
	pkill watch
	pkill mpstat
	pkill hl-smi
	pkill free
	pkill tee
}

function get_sys_envdata(){
	end_time=$(date +%s)

	echo ${start_time} > $OUTPUT/_time_s.log
	echo ${end_time}  >> $OUTPUT/_time_s.log

	MLOG=$OUTPUT/_module.log
	
	pip check > $MLOG; pip list | grep -P 'habana|tensor|torch|transformers' >> $MLOG; dpkg-query -W | grep habana >> $MLOG; lsmod | grep habana >> $MLOG
	echo '-------' >> $MLOG

	mapfile -t arr < <( ipmitool fru | grep Board | awk -F ': ' '{print $2}' )
	echo "mfgdat:" ${arr[0]}  >> $MLOG
	echo "mfgvdr:" ${arr[1]}  >> $MLOG
	echo "mboard:" ${arr[2]}  >> $MLOG
	echo "mbseri:" ${arr[3]}  >> $MLOG

	tmpser=$(ipmitool fru | grep "Product Serial" | awk -F': ' '{print $2}' | xargs)		
	pdseri=${tmpser:-'SMCISMCI1500'}
	echo "pdseri:" $pdseri >> $MLOG

	echo "fwvern:" $(ipmitool mc info | grep "Firmware Revision" | awk '{print $4}') >> $MLOG
	echo "fwdate:" $(ipmicfg -summary | grep "Firmware Build" | awk '{print $5}') >> $MLOG

	echo "biosvr:" $(ipmicfg -summary | grep "BIOS Version" |  awk '{print $4}') >> $MLOG
	echo "biosdt:" $(ipmicfg -summary | grep "BIOS Build" |  awk '{print $5}') >> $MLOG

	echo "ipmiip:" $(ipmitool lan print | grep -P "IP Address\s+: " | awk -F ': ' '{print $2}') >> $MLOG
	echo "ipmmac:" $(ipmitool lan print | grep -P "MAC Address\s+: "| awk -F ': ' '{print $2}') >> $MLOG
	echo "ipipv6:" $(ipmicfg -summary | grep "IPv6" |  awk '{print $5}') >> $MLOG
	echo "cpldvr:" $(ipmicfg -summary | grep "CPLD" |  awk '{print $4}') >> $MLOG

	echo "cpumdl:" $(lscpu | grep Xeon | awk -F ')' '{print $3}' | cut -c 2- | sed 's/i u/iu/' ) >> $MLOG
	echo "cpucor:" $(lscpu | grep "^CPU(s):" | awk '{print $2}') >> $MLOG
	echo "pcinfo:" $(dmidecode | grep 'Type.*PCI' | tail -n 1 | awk -F': ' '{print $2}') >> $MLOG

	echo "memcnt:" $(lsmem | grep "online memory" | awk '{print $4}') >> $MLOG
	echo "gpcpld:" $OAM_CPLDS >> $MLOG

	echo "" >> $MLOG
	echo "osintl:" $(stat --format=%w /) >> $MLOG
	echo "machid:" $(cat /etc/machine-id)>> $MLOG

	echo "govnor:" $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor) >> $MLOG
	echo "hgpage:" $(grep HugePages_Total /proc/meminfo | awk '{print $2}') >> $MLOG

	hostip=$(ifconfig | grep broadcast | grep -v 172.17 | awk '{print $2}' | grep -v ^169)
	echo "kernel:" $(uname -r) >> $MLOG
	echo "hostip:" ${hostip}   >> $MLOG
	macadd=$(ifconfig | grep $hostip -A 2 | grep ether |  awk '{print $2}')
	echo "hosmac:" ${macadd}   >> $MLOG

	hosnic=$(lspci | grep Eth | awk -F': ' '{print $2}' | sed 's/Intel Corporation Ethernet//g')
	echo "hosnic:" ${hosnic}   >> $MLOG

	echo "rootsz:" $(lsblk | grep /$ | awk '{print $4}') >> $MLOG
	echo "hdrive:" "$(parted -l | grep Model | tr '\n' ' ' | tr -cd '[:print:]' | sed 's/^[ \t]*//;s/[ \t]*$//' )" >> $MLOG

	echo "uptime:" $(uptime -s) >> $MLOG

	echo "habana:" $(hl-smi -v | grep -P '\s+'| awk -F 'version' '{print $2}') >> $MLOG
	echo "startt:" ${start_time} >> $MLOG
	echo "endtme:" ${end_time}   >> $MLOG
	echo "elapse:" $(($end_time-$start_time)) >> $MLOG
	echo "testts:" $start_YYYY   >> $MLOG

	echo "python:" $( python3 -V | cut -b 8-) >> $MLOG
	echo "osname:" $( grep ^NAME= /etc/os-release | awk -F'=' '{print $2}' | awk -F'"' '{print $2}') >> $MLOG
	echo "osvern:" $( grep ^VERSION_ID= /etc/os-release | awk -F'=' '{print $2}' | awk -F'"' '{print $2}' ) >> $MLOG
	echo "opnmpi:" $( ls /opt/habanalabs/ | grep openmpi | cut -b 9- ) >> $MLOG

	echo "perfsw:" $1 >> $MLOG
	echo "perfvr:" $2 >> $MLOG
	echo "modelt:" $3 >> $MLOG

	echo "fabric:" $( ls /opt/habanalabs/ | grep libfabric | cut -b 11- ) >> $MLOG
	echo "gaudig:" $( hl-smi -Q name -f csv,noheader | head -n 1 ) >> $MLOG
	echo "drivrv:" $( hl-smi -Q driver_version -f csv,noheader | head -n 1 ) >> $MLOG

	echo "" >> $MLOG
	hl-smi -Q timestamp,index,serial,bus_id,memory.used,temperature.aip,utilization.aip,power.draw -f csv,noheader >> $MLOG
	hl-smi | grep HL-225 | awk '{print "gpu busidr- " $2,$6}' >> $MLOG

	ipmitool dcmi power reading >> $MLOG

	lspci -vt > $OUTPUT/_lspciv.log
}

function log2-metabasedb(){
	M0=${OUTPUT}/_module.log
	declare -A pkg
	grep '\-------' -B 36 $M0 | grep -v '\-------' > 1
	while read -r key value; do
		[[ $value =~ "," ]] && value=$(echo "$value" | sed -r 's/,/ /g')
		pkg["$key"]="$value"
	done < 1
	rm -rf 1

	declare -A osi
	grep '\-------' -A 45 $M0 | grep -v '\-------' | grep . > 1
	while IFS=': ' read -r key value; do
		osi["$key"]="$value"
	done < 1
	#echo ${osi[machid]}

	# ------ oam info
	declare -A oam
	awk '{print $7 $8 $9}' ${OUTPUT}/_hl-smi.log | sed 's/,/ /g' | sort | uniq > 1
	while read -r seq srl bus ; do
		oam["$seq,0"]=$srl
		oam["$seq,1"]=$bus
	done < 1
	#echo ${oam[@]}

	#remove color control chars in log
	sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]//g" ${TRAINL} > 1

	# --- training result
	time2trn=$(grep -P "^Time To Train: " 1 | awk '{print $4}')
	maxpower=$(grep -P "^Maximum Power: " 1 | awk '{print $3}')
	avgtstep=$(grep -P "^  average_training_time_step: " 1 | awk '{print $2}')
	e2e_time=$(grep -P "^  e2e_train_time " 1 | awk '{print $3}')
	trainseq=$(grep -P "^  training_sequences" 1 | awk '{print $2}')
	finaloss=$(grep -P "^  final_loss" 1 | awk '{print $3}')
	rawttime=$(grep -P "^  raw_train_time" 1 | awk '{print $3}')
	evaltime=$(grep -P "^  model eval time" 1 | awk '{print $4}')
	energyco=$(grep -P "^  pdu energy used" 1 | awk '{print $4}')

	pwrsread=
	pwrfread=
	read -r -d '' pwrsread pwrfread <<< "$(grep -P '^  pdu energy used' 1 | awk '{print $7, $8}')"

	diff_srv=$(grep -P "^services diff" 1 | awk '{print $3}')
	diff_pro=$(grep -P "^process  diff" 1 | awk '{print $3}')
	avgttime=$(grep -P "^avgtrain time" 1 | awk '{print $3}')
	ttm_rslt=$(grep -P "^time to train" 1 | awk '{print $4}')
	testtime=$(grep -P "^Test Complete" 1 | awk '{print $3}')

	rm -rf 1

	# INSERT INTO table_name (column1, column2, column3, ...)
	# VALUES (value1, value2, value3, ...);

	kk="bmc_mac, test_start, test_end, elapse_time, test_date, \
	bmc_ipv4, bmc_ipv6, bmc_fware_version, bmc_fware_date, \
	bios_version, bios_date, bios_cpld, gpu_cpld, mb_serial, mb_mdate, mb_model, \
	pd_serial, \
	cpu_model, cpu_cores, pcie, memory, \
	os_idate, machid, scaling_governor, huge_page, os_kernel, host_mac, host_ip, \
	host_nic, root_partition_size, hard_drive, host_uptime_since, \
	habanalabs_firmware, optimum_habana, torch, pytorch_lightning, \
	lightning_habana, tensorflow_cpu, transformers, \
	habanalabs, habanalabs_ib, habanalabs_cn, habanalabs_en, ib_uverbs, \
	oam0_serial, oam0_pci, \
	oam1_serial, oam1_pci, \
	oam2_serial, oam2_pci, \
	oam3_serial, oam3_pci, \
	oam4_serial, oam4_pci, \
	oam5_serial, oam5_pci, \
	oam6_serial, oam6_pci, \
	oam7_serial, oam7_pci, \
	gaudi_model, gaudi_driver, python_version, os_name, \
	os_version, openmpi_version, libfabric_version, \
	test_framework, test_fw_version, test_model, \
	energy_consumed, energy_meter_start, energy_meter_end, \
	time_to_train, max_ipmi_power, average_training_time_step, \
	e2e_train_time, training_sequences_per_second, final_loss, raw_train_time, eval_time, \
	test_note, \
	result_service, result_process, result_avg_train_time_step, result_time_to_train "

	# limit string length
	osi[hosnic]=${osi[hosnic]:0:80}
	osi[hdrive]=${osi[hdrive]:0:190}

	# check test note
	test_note=""
	if [ -f _testnt.txt ]; then
		test_note=$(grep \## _testnt.txt -A 1 | grep -v \#)
		test_note=${test_note:0:190}
		cp _testnt.txt $OUTPUT/_testnt.txt
	fi

	ttm_rslt="SPM"

	time2trn=0

	vv="${osi[ipmmac]}, ${osi[startt]}, ${osi[endtme]}, ${osi[elapse]}, ${osi[testts]}, \
	${osi[ipmiip]}, ${osi[i	v6]}, ${osi[fwvern]}, ${osi[fwdate]}, \
	${osi[biosvr]}, ${osi[biosdt]}, ${osi[cpldvr]}, ${osi[gpcpld]}, ${osi[mbseri]}, ${osi[mfgdat]}, ${osi[mboard]}, \
	${osi[pdseri]},\
	${osi[cpumdl]}, ${osi[cpucor]}, ${osi[pcinfo]}, ${osi[memcnt]}, \
	${osi[osintl]}, ${osi[machid]}, ${osi[govnor]}, ${osi[hgpage]}, ${osi[kernel]}, ${osi[hosmac]}, ${osi[hostip]}, \
	${osi[hosnic]}, ${osi[rootsz]}, ${osi[hdrive]}, ${osi[uptime]}, \
	${pkg[habanalabs-firmware]}, ${pkg[optimum-habana]}, ${pkg[torch]}, ${pkg[pytorch-lightning]}, \
	${pkg[lightning-habana]}, ${pkg[tensorflow-cpu]}, ${pkg[transformers]}, \
	${pkg[habanalabs]}, ${pkg[habanalabs_ib]}, ${pkg[habanalabs_cn]}, ${pkg[habanalabs_en]}, ${pkg[ib_uverbs]}, \
	${oam["0,0"]}, ${oam["0,1"]}, ${oam["1,0"]}, ${oam["1,1"]}, ${oam["2,0"]}, ${oam["2,1"]}, ${oam["3,0"]}, ${oam["3,1"]}, \
	${oam["4,0"]}, ${oam["4,1"]}, ${oam["5,0"]}, ${oam["5,1"]}, ${oam["6,0"]}, ${oam["6,1"]}, ${oam["7,0"]}, ${oam["7,1"]}, \
	${osi[gaudig]}, ${osi[drivrv]}, ${osi[python]}, ${osi[osname]}, \
	${osi[osvern]}, ${osi[opnmpi]}, ${osi[fabric]}, \
	${osi[perfsw]}, ${osi[perfvr]}, ${osi[modelt]}, \
	$energyco, $pwrsread, $pwrfread, \
	$time2trn, $maxpower, $avgtstep, \
	$e2e_time, $trainseq, $finaloss, $rawttime, $evaltime, \
	$test_note, \
	$diff_srv, $diff_pro, $avgttime, $ttm_rslt "

	ss=$(echo $vv | sed "s/, /', '/g")
	ss="'"${ss}"'"

	sql="INSERT INTO GDSUPPORT(${kk}) VALUES ($ss);"

	if [[ "$1" == "sql" ]]; then
		#echo $kk
		#echo $vv
		echo $sql > $OUTPUT/_insert.sql
	elif [[ "$1" == "list" ]]; then
		IFS=', ' read -r -a col <<< "$kk"
		IFS=, 	 read -r"${BASH_VERSION:+a}${ZSH_VERSION:+A}" val <<< "$vv"

		for (( i=0; i<${#col[@]}; i++ )); do
			# trim leading space
			printf  " %30s : %s\n" ${col[$i]} "$( echo -e "${val[$i]}" | sed 's/^[ \t]*//;s/[ \t]*$//' )"
			#echo  ${col[$i]}   ${val[$i]}
		done
	else
		echo $kk
		echo $vv
	fi
}

function save_result_remote(){
	ipp=$(ifconfig | grep 'inet ' | grep -v -P '27.0|172.17' | awk '{print $2}')
	bsl=$(ipmitool fru | grep "Board Serial" | awk -F': ' '{print $2}')
	fff=${OUTPUT}_${ipp}_$(date '+%Y-%m-%dc%H-%M-%S')_${SECONDS}_${pdseri}

	# write test reult to sqlite3, create table
	save_sqlite_init
	sqlite3 gd-spkg.spm < ./init_sqlite &>/dev/null
	rm -rf init_sqlite &>/dev/null

	# insert test result
	sqlite3 gd-spkg.spm < $OUTPUT/_insert.sql

	exec_psql_sql_file 	  $OUTPUT/_insert.sql

	mv $OUTPUT $fff

	# copy to headquarter
	save_sys_cert

	if [[ -n $city ]]; then
		scp -r -P 7022 -i ./id_rsa -o PasswordAuthentication=no -o StrictHostKeyChecking=no $fff spm@129.146.47.229:/home/spm/support_package_repo/ &>/dev/null
	fi

	cp gd-spkg.spm ${fff}/
	zip -r -P 'smci1500$4All' ${fff}.zip ${fff} /var/log/kern.log /var/log/syslog /var/log/dmesg &>/dev/null

	if [[ -n $city ]]; then
		scp -r -P 7022 -i ./id_rsa -o PasswordAuthentication=no -o StrictHostKeyChecking=no ${fff}.zip spm@129.146.47.229:/home/spm/support_package_repo/zip/ &>/dev/null
	fi

	mkdir -p tmp
	mv ${fff}.zip tmp/

	rm -rf  ./.graph_dumps _exp id_ed25519 id_rsa &>/dev/null
}

function exec_psql_sql_file(){
	sql=${1:-_insert.sql}
	if [[ -n $city ]]; then
		psql "postgresql://postgres:smc123@129.146.47.229:7122/toucan" -q -f $sql
	fi
}

function save_sys_cert(){
cat > id_ed25519 <<- EOM
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
QyNTUxOQAAACB+8BuvOM5P+hjRN/2C9GqSYaOm5Jj39IzKUDh1yemdngAAAJh+T+UJfk/l
CQAAAAtzc2gtZWQyNTUxOQAAACB+8BuvOM5P+hjRN/2C9GqSYaOm5Jj39IzKUDh1yemdng
AAAEDrxo+ffBboSDXHA122bC9x88dPqbF3JNcgmYCbC67A237wG684zk/6GNE3/YL0apJh
o6bkmPf0jMpQOHXJ6Z2eAAAAD3NwbTEtMjAtMDgtMjAyNAECAwQFBg==
-----END OPENSSH PRIVATE KEY-----
EOM

cat > id_rsa <<- EOM
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAABlwAAAAdzc2gtcn
NhAAAAAwEAAQAAAYEAsO3tIpb+me5GhiX6CqcwLzXgiexiq6CtH2VuImpYXoBAMxlu8QFK
a49fzhPd2+GAXRBMbf8p+tKY4r6GU46K3mIijoJ46SgovmXgOn5K+OX1XZkTh7fT2I1JFN
d8ZJwvg9RxO4vHBkUp7GySA2JimqIx8SRd54v2tR71IWUvcOW4VMI8Pdh0MSCcJKtetyQB
PGEcpjYJ+J44uJfZZQa1rUQrCFaez0one4f0wmM1q0hGPwwxR9pahIbn3XzqnH/Y37jPFq
L7WrEg+gWdJ2tcy398tOpe0H26xEa/C1UHGECUVb55Dvc5qPhVTpAkcT3MFbv1iTO3429o
dr/3EnZEQQmR8xdQakJMCCE+pLfwPTlM2LIhqYH/R2dY8e64sv06vcryPx3ylunUVuhYfP
W8YG9zRAZawU0Ka1EVQD+3Hszufkefcc5tXyzJFLs67B9EsrKqn2yc/6iNSK1h9d4ZuaJd
lS8AqYjoK5vWcU8H4qCW/+A9VfK2cyfLtpbvIxtpAAAFgOHVEODh1RDgAAAAB3NzaC1yc2
EAAAGBALDt7SKW/pnuRoYl+gqnMC814InsYqugrR9lbiJqWF6AQDMZbvEBSmuPX84T3dvh
gF0QTG3/KfrSmOK+hlOOit5iIo6CeOkoKL5l4Dp+Svjl9V2ZE4e309iNSRTXfGScL4PUcT
uLxwZFKexskgNiYpqiMfEkXeeL9rUe9SFlL3DluFTCPD3YdDEgnCSrXrckATxhHKY2Cfie
OLiX2WUGta1EKwhWns9KJ3uH9MJjNatIRj8MMUfaWoSG59186px/2N+4zxai+1qxIPoFnS
drXMt/fLTqXtB9usRGvwtVBxhAlFW+eQ73Oaj4VU6QJHE9zBW79Ykzt+NvaHa/9xJ2REEJ
kfMXUGpCTAghPqS38D05TNiyIamB/0dnWPHuuLL9Or3K8j8d8pbp1FboWHz1vGBvc0QGWs
FNCmtRFUA/tx7M7n5Hn3HObV8syRS7OuwfRLKyqp9snP+ojUitYfXeGbmiXZUvAKmI6Cub
1nFPB+Kglv/gPVXytnMny7aW7yMbaQAAAAMBAAEAAAGACLglAloiIHhladmHxcwg/Aah8v
IfF7mypnQzdgc7JScZYttLRB3N6tiVPlzsx1gI4S07MwWK7lVAGxaMHKSO8/Aup0rHRihI
P7/aCc/tBnCgw7TWSU82JbsqwZfwBa5LyimnTemwzH6OlxvvozKPTPMW1n02EoHrjdgBeR
yZNq1fhO/Qk7St3zjt8QGwCIMB+5WGmatamPHFNlWnbUrkG66bF01bhLgxE22rEoRcof0N
FzDU4edhJBxY42mzTzSeqMJCsxpwf4uG6sOErgcDwj5xu6YOgX+9iaTgc4jesJhARTA6Hi
NxVMyo/wQMWe9j2aJdEdO687U0m4OHENpg/GrkBIuxwVmXl0JKEHW6LwlrZccGmTWN/eXP
d4un+eIMBbHVg4EPGVFKH8tnpRKJatTQ008+9tbq5am215mgC1/y3x268SljLjnHRB6NN4
9hYg4nm4WD0XUrfA2vXpEaU+q0DrCF2WgsyVHLEF+2JLLV2PCqqhB/FsuoqG9qoWdBAAAA
wG/RYWgCQxaWLmsdgmfPWTM4ayxUGBoaGHJmzT+MM38Qvq1b/R+8d19Ys1K7wDQhkcaduD
WEBG7xjfoAXx+6KtRm/QNnOH7P71LyHfqsMV+fYWUR8sIfhVIM+ZQrwVpVxrYYkKxEVctL
eGMFkh63pyzIkWDDumCGc8DEz8uY8HJKK+3sAbo0g9VXETUvGRoo7E0q4kRtLo5Td0/Ics
J/gVMWGXbnhKz3pqNgC5OzOjU6EduKMaRPkDsEkLGZHj/++QAAAMEA3rfZmpOMSqa0ueuY
Vi/mxrNpYo0UagZiIfozWOKwUc+3HxKunxmjq1wyyiPoy9KWYu/OmSXrcr+0dMO2ZKIRss
/4LHa2z7lgV+Mc+MTiBCMDazoQXkn1QxRUnPCpbCcQvrw0I6pg7ymSPoAoXLAs8m/QtqyN
vziFsoMTuvhOB/1BjHJbrdXBGKDTqKArRQM0VTdQc5a9YARWEAPA6l8PMyrLPg+4btt7wT
ns9+FdTxApEYA+Lu7FSHUskcY65S1hAAAAwQDLXmnVdUJR4vPs/9i+UAbkJP2duH2KVUKb
pc7mPUtN/EdfGG+r7CIRqgWmzLTrhxZ3gvTO+jfi30aRUmzWiO4bsxipTZFgaE7/QfhQ87
zbugyyS5dKDrUSCFyfaSR06AuekO+AP5+nrjr+n9XjBs31evnKhDRmarLEcpNW/ewSRiJy
cv5hFZi/gWXEGimfVYjAR8JE87+kotA4lvf/Eu9B17M0D82OKM0OumsisVX4XmQUqG9UvM
qP9N6WIsGIYwkAAAAJcm9vdEBzcG0xAQI=
-----END OPENSSH PRIVATE KEY-----
EOM

chmod 400 id_rsa id_ed25519
}

function save_sqlite_init(){
cat > init_sqlite <<- EOM
CREATE TABLE GDSUPPORT(
bmc_mac			VARCHAR(50) NOT NULL,
test_start		INTEGER  NOT NULL,
test_end		INTEGER,
elapse_time		INTEGER,
test_date		VARCHAR(50),
bmc_ipv4		VARCHAR(50),
bmc_ipv6		VARCHAR(50),
bmc_fware_version	VARCHAR(50),
bmc_fware_date	VARCHAR(50),
bios_version	VARCHAR(50),
bios_date		VARCHAR(50),
bios_cpld		VARCHAR(50),
gpu_cpld		VARCHAR(50),
mb_serial		VARCHAR(50),
mb_mdate		VARCHAR(50),
mb_model		VARCHAR(50),
pd_serial		VARCHAR(50),
cpu_model		VARCHAR(50),
cpu_cores		VARCHAR(50),
pcie			VARCHAR(50),
memory			VARCHAR(50),
os_idate		VARCHAR(50),
machid			VARCHAR(50),
scaling_governor	VARCHAR(50),
huge_page		VARCHAR(50),
os_kernel		VARCHAR(50),
host_mac		VARCHAR(50),
host_ip			VARCHAR(50),
host_nic		VARCHAR(90),
root_partition_size VARCHAR(50),
hard_drive		VARCHAR(200),
host_uptime_since	VARCHAR(50),
habanalabs_firmware	VARCHAR(50),
optimum_habana		VARCHAR(50),
torch				VARCHAR(50),
pytorch_lightning	VARCHAR(50),
lightning_habana	VARCHAR(50),
tensorflow_cpu		VARCHAR(50),
transformers		VARCHAR(50),
habanalabs		VARCHAR(50),
habanalabs_ib	VARCHAR(50),
habanalabs_cn	VARCHAR(50),
habanalabs_en	VARCHAR(50),
ib_uverbs		VARCHAR(50),
oam0_serial		VARCHAR(50),
oam0_pci		VARCHAR(50),
oam1_serial		VARCHAR(50),
oam1_pci		VARCHAR(50),
oam2_serial		VARCHAR(50),
oam2_pci		VARCHAR(50),
oam3_serial		VARCHAR(50),
oam3_pci		VARCHAR(50),
oam4_serial		VARCHAR(50),
oam4_pci		VARCHAR(50),
oam5_serial		VARCHAR(50),
oam5_pci		VARCHAR(50),
oam6_serial		VARCHAR(50),
oam6_pci		VARCHAR(50),
oam7_serial		VARCHAR(50),
oam7_pci		VARCHAR(50),
gaudi_model		VARCHAR(50),
gaudi_driver	VARCHAR(50),
python_version	VARCHAR(50),
os_name			VARCHAR(50),
os_version		VARCHAR(50),
openmpi_version	VARCHAR(50),
libfabric_version	VARCHAR(50),
test_framework	VARCHAR(50),
test_fw_version	VARCHAR(50),
test_model		VARCHAR(50),
energy_consumed		VARCHAR(50),
energy_meter_start	VARCHAR(50),
energy_meter_end	VARCHAR(50),
time_to_train		FLOAT,
max_ipmi_power		VARCHAR(50),
average_training_time_step	  VARCHAR(50),
e2e_train_time				  VARCHAR(50),
training_sequences_per_second VARCHAR(50),
final_loss		VARCHAR(50),
raw_train_time	VARCHAR(50),
eval_time		VARCHAR(50),
test_note		VARCHAR(200),
result_service	VARCHAR(50),
result_process	VARCHAR(50),
result_avg_train_time_step	VARCHAR(50),
result_time_to_train		VARCHAR(50),
PRIMARY KEY (bmc_mac, test_start) );
EOM
}

function get_external_ip_info(){
	curl -s --connect-timeout 5 --max-time 5 ipinfo.io | grep : | sed 's/"//g' | sed 's/,//g' > sip
	exip=$(  grep ip:   sip   | awk -F': ' '{print $2}' )
	city=$(  grep city: sip   | awk -F': ' '{print $2}' )
	region=$(grep region: sip | awk -F': ' '{print $2}' )
	postal=$(grep postal: sip | awk -F': ' '{print $2}' )
	rm -rf sip &>/dev/null
}

function progress_baa() {
	local duration=${1}
	already_done() { for ((done=0; done<$elapsed; done++)); do printf "▇"; done }
	remaining() { for ((remain=$elapsed; remain<$duration; remain++)); do printf " "; done }
	percentage() { printf "| %s%%" $(( (($elapsed)*100)/($duration)*100/100 )); }
	clean_line() { printf "\r"; }

	for (( elapsed=1; elapsed<=$duration; elapsed++ )); do
		already_done; remaining; percentage
		sleep 1
		clean_line
	done
	clean_line
}

function show_progress {
	bar_size=40
	bar_char_done="#"
	bar_char_todo="-"
	bar_percentage_scale=2

    current="$1"
    total="$2"

    # calculate the progress in percentage 
    percent=$(bc <<< "scale=$bar_percentage_scale; 100 * $current / $total" )
    # The number of done and todo characters
    done=$(bc <<< "scale=0; $bar_size * $percent / 100" )
    todo=$(bc <<< "scale=0; $bar_size - $done" )

    # build the done and todo sub-bars
    done_sub_bar=$(printf "%${done}s" | tr " " "${bar_char_done}")
    todo_sub_bar=$(printf "%${todo}s" | tr " " "${bar_char_todo}")

    # output the bar
    echo -ne "\r  [${done_sub_bar}${todo_sub_bar}] ${percent}%"
	printf "\r";
}

function progress_bar(){
	tasks_in_total=$1
	for current_task in $(seq $tasks_in_total) 
	do
		sleep 1
		show_progress $current_task $tasks_in_total
	done

	printf ' %.0s' {1..100}
	echo
}

function save_unit_testcases(){
cat >testcases.sh <<- 'EOM'
function ts_gpu1010_check_gpu_cnt(){ #desc: check gpu count: 8
	cnt=$(hl-smi -L | grep SPI | wc -l)

	[[ $GD2 == 0 ]] && gcn=$(lspci -d :1020: -nn | wc -l) || gcn=$(lspci -d :1060: -nn | wc -l)

	[[ $cnt == 8 && $gcn == 8 ]] && (print_result ${FUNCNAME} 0; res[$1]=0) \
					|| (print_result ${FUNCNAME} 1; res[$1]=1; exit 1)
}

function ts_gpu1020_check_cpld(){ #desc: check gpu cpld: 10
	check_gpu_oam_cpld
	OAM_CPLDS=$(echo $OAM_CPLDS)

	[[ $OAM_CPLDS == "10 10 10 10 10 10 10 10" ]] \
	&& (print_result ${FUNCNAME} 0; res[$1]=0) \
	|| (print_result ${FUNCNAME} 1; res[$1]=1)
}

ROOT_CAUSES=

function ts_gpu1030_check_gpu_busid(){ #desc: check gpu bus-id
	gcn=$(hl-smi -L | grep "Bus Id" | awk '{print $4}' |  sed 's/0000://')

	check_oam "b3:00.0" 0
	check_oam "19:00.0" 1
	check_oam "1a:00.0" 2
	check_oam "b4:00.0" 3
	check_oam "43:00.0" 4
	check_oam "44:00.0" 5
	check_oam "cc:00.0" 6
	check_oam "cd:00.0" 7

	[[ $gcn =~ "b3:00.0" ]] && [[ $gcn =~ "19:00.0" ]] && [[ $gcn =~ "1a:00.0" ]] && \
	[[ $gcn =~ "b4:00.0" ]] && [[ $gcn =~ "43:00.0" ]] && [[ $gcn =~ "44:00.0" ]] && \
	[[ $gcn =~ "cc:00.0" ]] && [[ $gcn =~ "cd:00.0" ]] && \
	   (print_result ${FUNCNAME} 0; res[$1]=0) \
	|| (print_result ${FUNCNAME} 1; res[$1]=1)
}

function ts_gpu1040_check_powergood(){ #desc: check PowerGood
	flag=0
	pg=`ipmitool raw 0x30 0x70 0xef 2 0x70 0x4b 2 0x9e 1 0x02 | xargs`
	[[ "$pg" == "00" ]] && passert "OAM PRESENT   $pg OK" || passert "OAM PRESENT   $pg NG"
	[[ "$pg" != "00" ]] && flag=$((flag + 1))

	pg=`ipmitool raw 0x30 0x70 0xef 2 0x70 0x4b 2 0x9e 1 0x04 | xargs`
	[[ "$pg" == "ff" ]] && passert "OAM P54V PG   $pg OK" || passert "OAM P54V PG   $pg NG"
	[[ "$pg" != "ff" ]] && flag=$((flag + 1))

	pg=`ipmitool raw 0x30 0x70 0xef 2 0x70 0x4b 2 0x9e 1 0x06 | xargs`
	[[ "$pg" == "ff" ]] && passert "OAM P12V PG   $pg OK" || passert "OAM P12V PG   $pg NG"
	[[ "$pg" != "ff" ]] && flag=$((flag + 1))
	
	pg=`ipmitool raw 0x30 0x70 0xef 2 0x70 0x4b 2 0x9e 1 0x09 | xargs`
	[[ "$pg" == "ff" ]] && passert "OAM MODULE PG $pg OK" || passert "OAM MODULE PG $pg NG"
	[[ "$pg" != "ff" ]] && flag=$((flag + 1))

	pg=`ipmitool raw 0x30 0x70 0xef 2 0x70 0x4c 2 0x84 1 0x09 | xargs`
	[[ "$pg" == "0f" ]] && passert "UBB PG        $pg OK" || passert "UBB PG        $pg NG"
	[[ "$pg" != "0f" ]] && flag=$((flag + 1))

	pg=`ipmitool raw 0x30 0x70 0xef 2 0x70 0x4b 2 0x9e 1 0x01 | xargs`
	[[ "$pg" == "ff" ]] && passert "OAM THERMTRIP $pg OK" || passert "OAM THERMTRIP $pg NG"
	[[ "$pg" != "ff" ]] && flag=$((flag + 1))

	ipmitool raw 0x30 0x70 0xef 2 0x70 0x4b 2 0x9e 0xff 0x0 > $OUTPUT/_cpld0xffx0

	[[ $flag == 0 ]] && print_result ${FUNCNAME} 0 || print_result ${FUNCNAME} 1
	[[ $flag == 0 ]] && res[$1]=0 || res[$1]=1
}

function ts_gpu1050_check_gpu_pcie(){ #desc: check pcie PMC LnkSta Habana
	flag=0
	pg=`lspci -d :4000: -nnvv | grep -Ew "PMC|LnkSta" | grep \(ok\) | wc  -l`
	[[ "$pg" == "12" ]] && passert "PMC-Sierra LnkSta ok count $pg OK" || passert "PMC-Sierra LnkSta ok count $pg NG"
	[[ "$pg" != "12" ]] && flag=$((flag + 1))

	pg=`lspci -d :1020: -nnvv | grep -Ew "Habana|LnkSta" | grep \(ok\) | wc  -l`
	[[ "$pg" == "8" ]] && passert "Habana LnkSta     ok count $pg  OK" || passert "Habana LnkSta     ok count $pg  NG"
	[[ "$pg" != "8" ]] && flag=$((flag + 1))

	[[ $flag == 0 ]] && print_result ${FUNCNAME} 0 || print_result ${FUNCNAME} 1
	[[ $flag == 0 ]] && res[$1]=0 || res[$1]=1
}

function ts_qua1060_Memory_BW_memOnly(){ #desc: check Memory_BW_Test memOnly
	printf "  ${GRN}qual: Memory_BW_Test memOnly: "
	local start=$(date +%s)

	cd $GPATH
	rm -rf ${GLOG}/* &>/dev/null
	__python_cmd=python3 hl_qual -gaudi2 -mb -memOnly -rmod parallel -c all -dis_mon &>/dev/null &
	progress_bar 30

	printf "  -mb -memOnly: "
	hl_qual_exec_time
	printf "${NCL}\n"

	runt=$(($(date +%s) - start))
	cd - &>/dev/null

	glog=$(ls -rt ${GLOG} | tail -n 1)
	rslt=$(tail -n 1 ${GLOG}/${glog})

	cp ${GLOG}/${glog} $OUTPUT/_${glog}-'Memory_memOnly'

	if [[ $rslt == "PASSED" ]]; then
		print_result ${FUNCNAME} 0
		res[$1]=0 
	else
		passert "memory only test fail-${runt}"
		print_result ${FUNCNAME} 1
		res[$1]=1
	fi
}

function ts_qua1062_Memory_BW_pciOnly(){ #desc: check Memory_BW_Test pciOnly
	printf "  ${GRN}qual: Memory_BW_Test pciOnly: "
	local start=$(date +%s)

	cd $GPATH
	rm -rf ${GLOG}/* &>/dev/null
	__python_cmd=python3 hl_qual -gaudi2 -mb -pciOnly -rmod parallel -c all -dis_mon &>/dev/null &
	progress_bar 15

	printf "  -mb -pciOnly: "
	hl_qual_exec_time
	printf "${NCL}\n"

	runt=$(($(date +%s) - start))
	cd - &>/dev/null

	glog=$(ls -rt ${GLOG} | tail -n 1)
	rslt=$(tail -n 1 ${GLOG}/${glog})

	cp ${GLOG}/${glog} $OUTPUT/_${glog}-'Memory_pciOnly'

	if [[ $rslt == "PASSED" ]]; then
		print_result ${FUNCNAME} 0
		res[$1]=0 
	else
		passert "pci only test fail-${runt}"
		print_result ${FUNCNAME} 1
		res[$1]=1
	fi
}

function ts_qua1064_Memory_bidirection(){ #desc: check Memory_BW_Test bidirection
	printf "  ${GRN}qual: Memory_BW_Test bidirection: "
	local start=$(date +%s)

	cd $GPATH
	rm -rf ${GLOG}/* &>/dev/null
	__python_cmd=python3 hl_qual -gaudi2 -mb -b -memOnly -rmod parallel -c all -dis_mon &>/dev/null &
	progress_bar 35

	printf "  -mb -b -memOnly: "
	hl_qual_exec_time
	printf "${NCL}\n"

	runt=$(($(date +%s) - start))
	cd - &>/dev/null

	glog=$(ls -rt ${GLOG} | tail -n 1)
	rslt=$(tail -n 1 ${GLOG}/${glog})

	cp ${GLOG}/${glog} $OUTPUT/_${glog}-'Memory_bidirection'

	if [[ $rslt == "PASSED" ]]; then
		print_result ${FUNCNAME} 0
		res[$1]=0 
	else
		passert "memory bidirection test fail-${runt}"
		print_result ${FUNCNAME} 1
		res[$1]=1
	fi
}

function ts_qua1070_PCI_BW_Test(){ #desc: check PCI_BW_Test
	printf "  ${GRN}qual: PCI_BW_Test: "
	local start=$(date +%s)

	cd $GPATH
	rm -rf ${GLOG}/* &>/dev/null
	if [[ $GD2 == 0 ]]; then
		__python_cmd=python3 hl_qual -gaudi2 -t 20 -p -b -gen gen4 -rmod parallel -c all -dis_mon &>/dev/null &
	else
		__python_cmd=python3 hl_qual -gaudi3 -t 20 -p -b -c all -rmod parallel -dis_mon &>/dev/null &
	fi
	progress_bar 145

	printf "  pci -p -b: "
	hl_qual_exec_time
	printf "${NCL}\n"
	
	runt=$(($(date +%s) - start))
	cd - &>/dev/null

	glog=$(ls -rt ${GLOG} | tail -n 1)
	rslt=$(tail -n 1 ${GLOG}/${glog})

	cp ${GLOG}/${glog} $OUTPUT/_${glog}-'PCI_BW'

	if [[ $rslt == "PASSED" ]]; then
		print_result ${FUNCNAME} 0
		res[$1]=0
	else
		passert "memory test fail-${runt}"
		print_result ${FUNCNAME} 1
		res[$1]=1
	fi
}

function ts_qua1080_HBM_Stress_Full(){ #desc: check HBM_Stress_Test
	clean_runner
	printf "  ${GRN}qual: HBM_Stress_Test: "
	local start=$(date +%s)

	reload_hl_drivers "lock"

	cd $GPATH
	rm -rf ${GLOG}/* &>/dev/null
	hl_qual -gaudi2 -full_hbm_data_check_test -i 3 -rmod parallel -c all -dis_mon &>/dev/null &
	progress_bar 400

	runt=$(($(date +%s) - start))
	echo -e "  -full_hbm_data_check_test : ${runt}${NCL}"

	cd - &>/dev/null

	glog=$(ls -rt ${GLOG} | tail -n 1)
	rslt=$(tail -n 1 ${GLOG}/${glog})

	cp ${GLOG}/${glog} $OUTPUT/_${glog}-'HBM_Stress'

	if [[ $rslt == "PASSED" ]]; then
		print_result ${FUNCNAME} 0
		res[$1]=0 
	else
		passert "hbm full test fail-${runt}"
		print_result ${FUNCNAME} 1
		res[$1]=1
	fi
}

function ts_qua1082_HBM_Stress_DMA(){ #desc: check HBM_Stress_DMA
	clean_runner
	printf "  ${GRN}qual: HBM_Stress_DMA\n"
	local start=$(date +%s)

	cd $GPATH
	rm -rf ${GLOG}/* &>/dev/null
	hl_qual -gaudi2 -hbm_dma_stress -i 3 -rmod parallel -c all -dis_mon &>/dev/null &
	progress_bar 470
	cd - &>/dev/null

	runt=$(($(date +%s) - start))
	printf "  -hbm_dma_stress: "
	hl_qual_exec_time
	printf "${NCL}\n"

	glog=$(ls -rt ${GLOG} | tail -n 1)
	rslt=$(tail -n 1 ${GLOG}/${glog})

	cp ${GLOG}/${glog} $OUTPUT/_${glog}-'HBM_DMA'

	if [[ $rslt == "PASSED" ]]; then
		print_result ${FUNCNAME} 0
		res[$1]=0 
	else
		passert "hbm dma fail-${runt}"
		print_result ${FUNCNAME} 1
		res[$1]=1
	fi
}

function ts_qua1084_HBM_Stress_TPC(){ #desc: check HBM_Stress_TPC
	clean_runner
	printf "  ${GRN}qual: HBM_Stress_TPC: "
	local start=$(date +%s)

	cd $GPATH
	rm -rf ${GLOG}/* &>/dev/null
	hl_qual -gaudi2 -hbm_tpc_stress -i 3 -rmod parallel -c all -dis_mon &>/dev/null &
	progress_bar 660
	cd - &>/dev/null

	runt=$(($(date +%s) - start))
	echo -e "  -hbm_tpc_stress : ${runt}${NCL}"

	glog=$(ls -rt ${GLOG} | tail -n 1)
	rslt=$(tail -n 1 ${GLOG}/${glog})

	cp ${GLOG}/${glog} $OUTPUT/_${glog}-'HBM_TPC'

	if [[ $rslt == "PASSED" ]]; then
		print_result ${FUNCNAME} 0
		res[$1]=0 
	else
		passert "hbm tpc fail-${runt}"
		print_result ${FUNCNAME} 1
		res[$1]=1
	fi
}

function ts_qua1090_NIC_Base_Pairs(){ #desc: check NIC_Base_Pairs
	clean_runner
	printf "  ${GRN}qual: NIC_Base_Pairs\n"
	local start=$(date +%s)

	cd $GPATH
	rm -rf ${GLOG}/* &>/dev/null
	hl_qual -gaudi2 -c all -rmod parallel -i 50 -nic_base -test_type pairs -dis_mon &>/dev/null &
	[[ `ps -ef | grep hl_qual | grep gaudi | wc -l` != 0 ]] || echo -e  "${GRN}  running...${NCL}"

	progress_bar 35
	cd - &>/dev/null

	printf "  -nic_base pairs: "
	hl_qual_exec_time
	printf "${NCL}\n"

	runt=$(($(date +%s) - start))

	glog=$(ls -rt ${GLOG} | tail -n 1)
	rslt=$(tail -n 1 ${GLOG}/${glog})

	cp ${GLOG}/${glog} $OUTPUT/_${glog}-'NIC_Base_Pairs'

	if [[ $rslt == "PASSED" ]]; then
		print_result ${FUNCNAME} 0
		res[$1]=0 
	else
		passert "nic base pairs fail-${runt}"
		print_result ${FUNCNAME} 1
		res[$1]=1
	fi
}

function ts_qua1092_NIC_Base_Allreduce(){ #desc: check NIC_Base_allreduce 20
	clean_runner
	printf "  ${GRN}qual: NIC_Base_allreduce: "
	local start=$(date +%s)

	cd $GPATH
	rm -rf ${GLOG}/* &>/dev/null
	hl_qual -gaudi2 -c all -rmod parallel -i 50 -nic_base -test_type allreduce -ep 100 -dis_mon &>/dev/null &
	progress_bar 25

	printf "  -nic_base allreduce: "
	hl_qual_exec_time
	printf "${NCL}\n"

	runt=$(($(date +%s) - start))

	cd - &>/dev/null

	glog=$(ls -rt ${GLOG} | tail -n 1)
	rslt=$(tail -n 1 ${GLOG}/${glog})

	cp ${GLOG}/${glog} $OUTPUT/_${glog}-'NIC_Base_Allreduce'

	if [[ $rslt == "PASSED" ]]; then
		print_result ${FUNCNAME} 0
		res[$1]=0 
	else
		passert "nic base allreduce fail-${runt}"
		print_result ${FUNCNAME} 1
		res[$1]=1
	fi
}

function ts_qua1100_E2E_Concurrency(){ #desc: check E2E_Concurrency_Test
	# requiers timeout_locked = 0

	clean_runner
	printf "  ${GRN}qual: E2E_Concurrency_Test: "
	local start=$(date +%s)

	cd $GPATH
	rm -rf ${GLOG}/* &>/dev/null
	hl_qual -gaudi2 -e2e_concurrency -disable_ports 8,22,23 -enable_ports_check int -t 30 -rmod parallel -c all -dis_mon &>/dev/null &
	progress_bar 65

	printf "  -e2e_concurrency : "
	hl_qual_exec_time
	printf "${NCL}\n"

	runt=$(($(date +%s) - start))

	cd - &>/dev/null

	glog=$(ls -rt ${GLOG} | tail -n 1)
	rslt=$(tail -n 1 ${GLOG}/${glog})

	cp ${GLOG}/${glog} $OUTPUT/_${glog}-'E2E_Concur'

	if [[ $rslt == "PASSED" ]]; then
		print_result ${FUNCNAME} 0
		res[$1]=0 
	else
		passert "e2e concur fail-${runt}"
		print_result ${FUNCNAME} 1
		res[$1]=1
	fi
}

function ts_qua1110_SerDes_BER_Test(){ #desc: check SerDes_BER_Test
	clean_runner
	printf "  ${GRN}qual: SerDes_BER_Test: "
	local start=$(date +%s)

	cd $GPATH
	rm -rf ${GLOG}/* &>/dev/null
	hl_qual -gaudi2 -ser -rmod parallel -c all -dis_mon &>/dev/null &
	progress_bar 18

	printf "  -ser : "
	hl_qual_exec_time
	printf "${NCL}\n"

	runt=$(($(date +%s) - start))

	cd - &>/dev/null

	glog=$(ls -rt ${GLOG} | tail -n 1)
	rslt=$(tail -n 1 ${GLOG}/${glog})

	cp ${GLOG}/${glog} $OUTPUT/_${glog}-'SerDes_BER'

	if [[ $rslt == "PASSED" ]]; then
		print_result ${FUNCNAME} 0
		res[$1]=0 
	else
		passert "ser fail-${runt}"
		print_result ${FUNCNAME} 1
		res[$1]=1
	fi
}

function ts_qua1120_F2_High(){ #desc: check Functional_High
	clean_runner
	printf "  ${GRN}qual: Functional_High: "
	local start=$(date +%s)

	cd $GPATH
	rm -rf ${GLOG}/* &>/dev/null
	hl_qual -gaudi2 -f2 -t 300 -d -dis_val -serdes -enable_ports_check int -l high -rmod parallel -c all -dis_mon &>/dev/null &
	progress_bar 400

	printf "  -f2 -l high: "
	hl_qual_exec_time
	printf "${NCL}\n"

	runt=$(($(date +%s) - start))

	cd - &>/dev/null

	glog=$(ls -rt ${GLOG} | tail -n 1)
	rslt=$(tail -n 1 ${GLOG}/${glog})

	cp ${GLOG}/${glog} $OUTPUT/_${glog}-'f2'

	if [[ $rslt == "PASSED" ]]; then
		print_result ${FUNCNAME} 0
		res[$1]=0 
	else
		passert "f2 high fail-${runt}"
		print_result ${FUNCNAME} 1
		res[$1]=1
	fi
}

function NG_qua1122_F2_Extreme(){ #desc: check Functional_Extreme 
	clean_runner
	printf "  ${GRN}qual: Functional_Extreme : "
	local start=$(date +%s)

	cd $GPATH
	rm -rf ${GLOG}/* &>/dev/null
	hl_qual -gaudi2 -f2 -t 120 -d -dis_val -serdes -l extreme -rmod parallel -c all -dis_mon &>/dev/null &
	progress_bar 450

	printf "  -f2 -l extreme: "
	hl_qual_exec_time
	printf "${NCL}\n"

	runt=$(($(date +%s) - start))

	cd - &>/dev/null

	glog=$(ls -rt ${GLOG} | tail -n 1)
	rslt=$(tail -n 1 ${GLOG}/${glog})

	cp ${GLOG}/${glog} $OUTPUT/_${glog}-'f2'

	if [[ $rslt == "PASSED" ]]; then
		print_result ${FUNCNAME} 0
		res[$1]=0 
	else
		passert "f2 extreme fail-${runt}"
		print_result ${FUNCNAME} 1
		res[$1]=1
	fi
}

function ts_qua1130_Power_Inc_EDP(){ #desc: check Power_EDP inc_power
	clean_runner
	printf "  ${GRN}qual: Power_Inc_EDP: "
	local start=$(date +%s)

	cd $GPATH
	rm -rf ${GLOG}/* &>/dev/null
	hl_qual -gaudi2 -e -Tw 1 -Ts 2 -sync -inc_power -enable_ports_check int -rmod parallel -c all -dis_mon &>/dev/null &
	progress_bar 80

	printf "  -e -inc_power : "
	hl_qual_exec_time
	printf "${NCL}\n"

	runt=$(($(date +%s) - start))

	cd - &>/dev/null

	glog=$(ls -rt ${GLOG} | tail -n 1)
	rslt=$(tail -n 1 ${GLOG}/${glog})

	cp ${GLOG}/${glog} $OUTPUT/_${glog}-'inc_power'

	if [[ $rslt == "PASSED" ]]; then
		print_result ${FUNCNAME} 0
		res[$1]=0 
	else
		passert "inc_power fail-${runt}"
		print_result ${FUNCNAME} 1
		res[$1]=1
	fi
}

function ts_qua1132_Power_EDP_Extreme(){ #desc: check Power_EDP_Extreme
	#Concurrency Power Stress requiers timeout_locked = 0

	clean_runner
	printf "  ${GRN}qual: Power_EDP_Extreme "
	local start=$(date +%s)

	cd $GPATH
	rm -rf ${GLOG}/* &>/dev/null
	hl_qual -gaudi2 -t 40 -e -l extreme -Tw 3 -Ts 1 -rmod parallel -c all -dis_mon &>/dev/null &
	progress_bar 50

	printf "  -e -extreme : "
	hl_qual_exec_time
	printf "${NCL}\n"

	runt=$(($(date +%s) - start))

	cd - &>/dev/null

	glog=$(ls -rt ${GLOG} | tail -n 1)
	rslt=$(tail -n 1 ${GLOG}/${glog})

	cp ${GLOG}/${glog} $OUTPUT/_${glog}-'power_edp_extreme'

	if [[ $rslt == "PASSED" ]]; then
		print_result ${FUNCNAME} 0
		res[$1]=0 
	else
		passert "power edp extreme fail-${runt}"
		print_result ${FUNCNAME} 1
		res[$1]=1
	fi
}

function ts_qua1134_Power_StressExtreme(){ #desc: check Power_Stress_Extreme
	#Concurrency Power Stress requiers timeout_locked = 0

	clean_runner
	printf "  ${GRN}qual: Power_Stress_Extreme: "
	local start=$(date +%s)

	cd $GPATH
	rm -rf ${GLOG}/* &>/dev/null
	hl_qual -gaudi2 -t 40 -s -l extreme -Tw 3 -Ts 1 -sync -enable_ports_check int -rmod parallel -c all -dis_mon &>/dev/null &	
	progress_bar 50

	printf "  -s -extreme : "
	hl_qual_exec_time
	printf "${NCL}\n"

	runt=$(($(date +%s) - start))

	cd - &>/dev/null

	glog=$(ls -rt ${GLOG} | tail -n 1)
	rslt=$(tail -n 1 ${GLOG}/${glog})

	cp ${GLOG}/${glog} $OUTPUT/_${glog}-'power_stress_extreme'

	if [[ $rslt == "PASSED" ]]; then
		print_result ${FUNCNAME} 0
		res[$1]=0 
	else
		passert "power stress extreme fail-${runt}"
		print_result ${FUNCNAME} 1
		res[$1]=1
	fi
}

function ts_hcc2000_hccl_all_reduce(){ #desc: check node2node all_reduce
	[ $INTERNET -ne 0 ] && { echo "  skip"; return; }

	clean_runner
	printf "  ${GRN}hccl comm: all_reduce\n"
	local start=$(date +%s)

	hlog=$(pwd)/${OUTPUT}/_hccl-a.log

	git clone --depth=1 https://github.com/HabanaAI/hccl_demo &>/dev/null

	cp hccl_demo2 hccl_demo/hccl_demo
	chmod 777     hccl_demo/hccl_demo
	cd hccl_demo

	if [[ -n $city ]]; then
		git pull &>/dev/null
		make
	fi

	HCCL_COMM_ID=127.0.0.1:5555 python3 run_hccl_demo.py --nranks 8 --node_id 0 --size 256m --test all_reduce --loop 1000 --ranks_per_node 8 &>$hlog &
	progress_bar 50
	cd - &>/dev/null

	printf "  --nranks 8 --test all_reduce : "

	runt=$(($(date +%s) - start))

	rslt=$(grep BENCHMARK.*:  $hlog | awk '{print $5}' | head -n 1)
	echo -e "  NW Bandwidth: $rslt > 256" 
	printf "${NCL}\n"

	if [[ $rslt > 256 ]]; then
		print_result ${FUNCNAME} 0
		res[$1]=0 
	else
		passert "hccl-all_reduce fail-${runt}"
		print_result ${FUNCNAME} 1
		res[$1]=1
	fi
}

EOM
}

function clean_runner(){
	pkill runner
	pkill hl_qual
	hl-smi | grep -P "AIP +PID" -A 9 | awk '{print $3}' | grep -P "\d+" | xargs kill -9 &>/dev/null
}

function print_hl_qual_plan(){
cat  << EOF
 --------    --------    --------    --------    --------    --------    --------    --------
|        |  |        |  |        |  |        |  |        |  |        |  |        |  |        | 
| PCI BW |->| Serdes |->| HCLAPI |->| Power  |->| Power  |->| Simple |->| FT     |->| FT     |
|        |  |        |  |        |  | Stress |  | EDP    |  | FT     |  | LoopB  |  | AllG   |
 --------    --------    --------    --------    --------    --------    --------    --------
EOF

	echo
	grep "hl_qual -gaudi2" ${BASH_SOURCE[0]} | grep -v grep | awk -F'&' '{print $1}'
}

function hl_qual_exec_time(){
	# hl_qual still running
	local run=$(ps -ef | grep hl_qual | grep gaudi | wc -l)
	[[ $run != 0 ]] && sleep 10 

	local lll=${GLOG}/$(ls -rt ${GLOG} | tail -n 1)
	local rrr=$(tail -n 1 ${lll})
	local s0=`grep "Start running plugin"  $lll | head -n 1 | awk -F'.' '{print $1}' | awk -F'[' '{print $2}'`
	local s1=`grep "Finish running plugin" $lll | head -n 1 | awk -F'.' '{print $1}' | awk -F'[' '{print $2}'`
	difftm=$(( $(date -d "$s1" "+%s") - $(date -d "$s0" "+%s") ))
	printf "%s - %s %s" $difftm $s1 $s0
}

function reload_hl_drivers(){
	[[ $GD3 == 0 ]] && return

	echo "  reload hl drive with timeout_locked=0"
	rmmod habanalabs &
	progress_bar 105

	[[ $1 =~ "lock" ]] && modprobe habanalabs timeout_locked=0 || modprobe habanalabs
	progress_bar 30
	
	lsmod  | grep -P "habanalabs *2" &>/dev/null
	
	if [[ $? == 0 ]]; then
		echo "  habanalabs driver reloaded"
	else
		echo "  habanalabs reload fail, redo"
		[[ $1 =~ "lock" ]] && modprobe habanalabs timeout_locked=0 || modprobe habanalabs
		lsmod  | grep -P "habanalabs *2" &>/dev/null &
		progress_bar 40
		[[ $? != 0 ]] && exit 9
	fi
}

function check_oam(){
	ok="oam $2 found"
	ng="oam $2 $1 lost"

	[[ $gcn =~ "$1" ]] && passert $ok || passert $ng
}

function passert(){
	[[ $* =~ (lost|fail|NG) ]] && ROOT_CAUSES="$*"

	[[ $* =~ (lost|fail|NG) ]] \
		&& printf "${RED}    %s${NCL}\n" "$*" | tee -a $TRAINL \
		|| printf "${GRN}    %s${NCL}\n" "$*" | tee -a $TRAINL
}

function print_result(){
	printf "  %-30s : " $1	| tee -a $TRAINL
	if   [[ $2 -eq 0 ]]; then
		echo -e "${CYA}PASS${NCL}" | tee -a $TRAINL
	elif [[ $2 -eq 1 ]]; then
		echo -e "${RED}FAIL${NCL}" | tee -a $TRAINL
	fi
	echo
}

function exec_case(){
	kase=$1
	slen=${#kase}
	printf "  ${CYA}%s: %s${NCL}\n\n" "Execute Gaudi Test Cases" $kase | tee -a $TRAINL

	if [[ $kase =~ "all"  ]]; then
		kase="0"
	fi

	bmc1=$(ipmitool lan print | grep -P "MAC Address\s+: "| awk -F ': ' '{print $2}')
	loip=$(ifconfig | grep broadcast | grep -v 172.17 | awk '{print $2}')
	
	for (( i=0; i<${#exe[@]}; i++ )); do
		sql="INSERT INTO GDRESULT (bmc_mac, test_date, testid, result, loip, exip, city, region, postal, note, debug) \
		     VALUES ( '${bmc1}', '${start_YYYY}', " 

		#  [[ $slen < 3 && $slen == $i ]]
		if [[ ${exe[$i]} =~ "$kase" ]]; then
			ROOT_CAUSES=''
			eval "${exe[$i]} $i"

			RST=""
			[[ ${res[$i]} -eq 0 ]] && RST="PASS" || RST="FAIL"

			# insert sql for test result
			sql="$sql '${seq[$i]}', '${RST}', '${loip}', '${exip}', '${city}', '${region}', '${postal}', '${EXETESTNOTE}', '${ROOT_CAUSES}');"
			echo $sql >> $OUTPUT/_caseresult
		fi
	done
	echo

	exec_psql_sql_file $OUTPUT/_caseresult

	echo -e "  ${CYA}Tested in ${SECONDS} seconds${NCL}\n" | tee -a $TRAINL
}

# -------- main start

apt install -y ipmitool expect sqlite3 postgresql-client sysstat zip libsigsegv2 git &>/dev/null

parse_args "$@"

save_unit_testcases

source testcases.sh

# get all test cases
mapfile -t tss < <( grep 'function ts' testcases.sh  | grep -v grep )
declare -a exe	# function name
declare -a des	# description
declare -a seq	# case #
declare -a res	# test result

rm -rf insert2db.sql &>/dev/null

# parse test case info from function
for (( i=0; i<${#tss[@]}; i++ )); do
	casef=${tss[$i]/function /}
	casef=${casef/(/}
	casef=${casef/)/}
	
	cname=$(echo $casef | awk -F'(){ #desc: ' '{print $1}')
	cdesc=$(echo $casef | awk -F'(){ #desc: ' '{print $2}')

	exe=("${exe[@]}" $cname) # case function name
	des=("${des[@]}" $cdesc) # case description	
	
	cnumb=$(echo $cname | awk -F'_' '{print $2}' | grep -o ....$)
	seq=("${seq[@]}" $cnumb) # case sequence#

	res=("${res[@]}" "0")	 # case test result	
	
	# sql - insert cases detail info to db
	ttt="INSERT INTO GDCASE (testid, function, description) \
		 VALUES ( '${cnumb}', '${cname}', '${cdesc}');" 
	echo $ttt >> insert2db.sql

done

exec_psql_sql_file  insert2db.sql &>/dev/null

rm -rf testcases.sh insert2db.sql &>/dev/null

# list cases and exit
if [[ $L_TESTCASES -eq 1 ]]; then
	printf "\n${CYA} %30s         %s${NCL}\n" "Gaudi Support Package Test Cases" "Description"

	for (( i=0; i<${#tss[@]}; i++ )); do
		casef=${tss[$i]/function /}
		casef=${casef/(/}
		casef=${casef/)/}
		
		cname=$(echo $casef | awk -F'(){ #desc: ' '{print $1}')
		cdesc=$(echo $casef | awk -F'(){ #desc: ' '{print $2}')

		printf "%2i \t %-30s : %s\n" $((i+1)) "$cname" "$cdesc"
	done
	echo
	exit
fi

prerun-syscheck

# clear caches
PROC_FS=${PROC_FS:-"/proc"}
#sync && echo 3 > $PROC_FS/sys/vm/drop_caches

# prepare directories
rm -rf   $OUTPUT &>/dev/null
mkdir -p $OUTPUT &>/dev/null

start_sys_mon
sleep 1

# gather system os info
get_sys_envdata "supportpkg" "0.1" "mnist"
echo -e "  ${YLW}Configure:${NCL}" ${SECONDS} | tee -a $tmpf

# print system info only
if [[ $SYSTEM_INFO -eq 1 ]]; then
	stop_sys_mon
	echo
	log2-metabasedb list

	rm -rf support_package_check.sh.x.c
	echo
fi

# run test cases
if [[ $TESTCASE_ID != 0 ]]; then
	exec_case $TESTCASE_ID

	stop_sys_mon
	exit
fi

# save system info to sql and copy to remote server
if [[ $SUPPORT_PKG -eq 1 ]]; then
	exec_case 'all'

	# stop monitoring process
	stop_sys_mon

	echo -e "  ${YLW}Save System Info to DB${NCL}"  | tee -a $TRAINL
	log2-metabasedb sql
	
	echo -e "  ${YLW}Send Test Result to SMC${NCL}" | tee -a $TRAINL
	save_result_remote
	echo
fi

rm -rf _testnt.txt &>/dev/null

echo -e "${BLU}Test Completed in ${SECONDS} seconds${NCL}\n" 

# sqlite3 gd-spkg.spm 'SELECT * FROM GDSUPPORT;'
# sqlite3 gd-spkg.spm 'SELECT count(0) FROM GDSUPPORT;'
# ./zoi -U -f support_package_check.sh -o support_sysinfo_check && rm -rf support_package_check.sh.x.c
