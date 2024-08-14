#!/bin/bash

# Supermiro Gaudi Support Package
# Jing Kang 8/2024

SRC=`readlink -f "${BASH_SOURCE[0]}" 2>/dev/null||echo $0`
CUR=`dirname "${SRC}"`
PAR=`dirname "${CUR}"`

TESTCASE_ID=0
SYSTEM_INFO=0
SUPPORT_PKG=0

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

        -t <test-case-id | all>, --test <test-case-id | all>
            run a specified test case or all cases

        -p, --print-system-info
            print out system hardware and software infomation

        -s, --sendout-support-package
            run all cases and send out the result along with system ino 

        -h, --help
            print this help message

EXAMPLES
       `basename $0` -t all

EOF
}

function check_gpu_oam_cpld(){
	OAM_CPLDS=$( \
			ipmitool raw 0x30 0x70 0xef 4 0x70 0x40 0xe6 0x40 2 0x4a 1 0x0; \
			ipmitool raw 0x30 0x70 0xef 4 0x70 0x40 0xe6 0x41 2 0x4a 1 0x0; \
			ipmitool raw 0x30 0x70 0xef 4 0x70 0x40 0xe6 0x42 2 0x4a 1 0x0; \
			ipmitool raw 0x30 0x70 0xef 4 0x70 0x40 0xe6 0x43 2 0x4a 1 0x0; \
			ipmitool raw 0x30 0x70 0xef 4 0x70 0x40 0xe6 0x44 2 0x4a 1 0x0; \
			ipmitool raw 0x30 0x70 0xef 4 0x70 0x40 0xe6 0x45 2 0x4a 1 0x0; \
			ipmitool raw 0x30 0x70 0xef 4 0x70 0x40 0xe6 0x46 2 0x4a 1 0x0; \
			ipmitool raw 0x30 0x70 0xef 4 0x70 0x40 0xe6 0x47 2 0x4a 1 0x0  )
}

# check Gaudi interal ports 
function check_gpu_int_port(){
	UP_PORTS=$(hl-smi -Q bus_id -f csv,noheader | xargs -I % hl-smi -i % -n link | grep UP | wc -l)
	if [ $UP_PORTS != 168 ]
	then
		echo -e "${RED}ERROR: Gaudi internal ports Not All Up${NCL}"
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
            -t | --test )
                TESTCASE_ID=$2
                shift 2
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
            -sh | --set-hugepage)
				echo -e "${YLW}set scaling_governor to performance${NCL}"
				echo -e "${YLW}set vm.nr_hugepages  to 153600${NCL}"
                echo performance | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
				sysctl -w vm.nr_hugepages=153600
                exit 0 ;;
            -co | --check-oam)
				check_gpu_oam_cpld
				echo -e "${YLW}OAM CPLD Version:${NCL} " $OAM_CPLDS
                exit 0 ;;
            -h | --help )
                print_synopsis
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

function prerun-syscheck(){
	if ! [ -f /usr/local/bin/ipmicfg ]; then
		cp ipmicfg /usr/local/bin/
	fi

	if ! [ -f /usr/local/bin/zip ]; then
		cp zip /usr/local/bin/
	fi

    # add required modules
    apt install -y ipmitool expect sqlite3 postgresql-client sysstat &>/dev/null

	BUSY=$(hl-smi |  grep "N/A   N/A    N/A" | wc -l)
	if [ $BUSY -ne 8 ]
	then
		echo -e "${RED}System Occupied! ${NCL}"
		exit 1
	fi

	start_time=$(date +%s)

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
	pip list | grep habana &>/dev/null
	if [ $? -eq 0 ]
	then
		echo -e "  ${YLW}Prep Gaudi Support Package${NCL} " $(date '+%Y-%m-%d %H:%M:%S') | tee -a $tmpf
		echo -e "  ${YLW}Gaudi internal ports UP count: ${NCL} " ${UP_PORTS} | tee -a $tmpf

		check_gpu_oam_cpld
		echo -e "  ${YLW}OAM CPLD   :${NCL}" $OAM_CPLDS | tee -a $tmpf
		echo
	else
		echo -e "${RED}warn: habana python module not instaleld, skip tests${NCL}"
		exit 1
	fi

	mpiver=$(ls /opt/habanalabs/ | grep openmpi | cut -b 9-)
	export PATH=/opt/python-llm/bin:/opt/habanalabs/openmpi-${mpiver}/bin:${PAR}/tool:$PATH
	export PT_HPU_LAZY_MODE=1
	SECONDS=0
}

function start_sys_mon(){
	#echo "start mon:" $(date)

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
	pdseri=${tmpser:-'SMICSMIC1500'}
	echo "pdseri:" $pdseri >> $MLOG

	echo "fwvern:" $(ipmitool mc info | grep "Firmware Revision" | awk '{print $4}') >> $MLOG
	echo "fwdate:" $(ipmicfg -summary | grep "Firmware Build" | awk '{print $5}') >> $MLOG

	#mapfile -t arr < <( dmidecode | grep -i "BIOS Information" -A 3 | awk -F ': ' '{print $2}' )
	#echo "biosvr:" ${arr[2]}  >> $MLOG
	#echo "biosdt:" ${arr[3]}  >> $MLOG
	echo "biosvr:" $(ipmicfg -summary | grep "BIOS Version" |  awk '{print $4}') >> $MLOG
	echo "biosdt:" $(ipmicfg -summary | grep "BIOS Build" |  awk '{print $5}') >> $MLOG

	echo "ipmiip:" $(ipmitool lan print | grep -P "IP Address\s+: " | awk -F ': ' '{print $2}') >> $MLOG
	echo "ipmmac:" $(ipmitool lan print | grep -P "MAC Address\s+: "| awk -F ': ' '{print $2}') >> $MLOG
	echo "ipipv6:" $(ipmicfg -summary | grep "IPv6" |  awk '{print $5}') >> $MLOG
	echo "cpldvr:" $(ipmicfg -summary | grep "CPLD" |  awk '{print $4}') >> $MLOG

	echo "cpumdl:" $(lscpu | grep Xeon | awk -F ')' '{print $3}' | cut -c 2- | sed 's/i u/iu/' ) >> $MLOG
	echo "cpucor:" $(lscpu | grep "^CPU(s):" | awk '{print $2}') >> $MLOG
	echo "pcinfo:" $(dmidecode | grep 'PCI' | tail -n 1 | awk -F': ' '{print $2}') >> $MLOG

	echo "memcnt:" $(lsmem | grep "online memory" | awk '{print $4}') >> $MLOG
	echo "gpcpld:" $OAM_CPLDS >> $MLOG

	echo "" >> $MLOG
	echo "osintl:" $(stat --format=%w /) >> $MLOG
	echo "machid:" $(cat /etc/machine-id)>> $MLOG

	echo "govnor:" $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor) >> $MLOG
	echo "hgpage:" $(grep HugePages_Total /proc/meminfo | awk '{print $2}') >> $MLOG

	hostip=$(ifconfig | grep broadcast | grep -v 172.17 | awk '{print $2}')
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
	echo "testts:" $(date '+%Y-%m-%d %H:%M:%S') >> $MLOG

	echo "python:" $( python -V | cut -b 8-) >> $MLOG
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
}

function log2-metabasedb(){
	M0=${OUTPUT}/_module.log
	declare -A pkg
	grep '\-------' -B 36 $M0 | grep -v '\-------' > 1
	while read -r key value; do
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

	test_note=""
	if [ -f $OUTPUT/_testnt.txt ]; then
		test_note=$(grep \## $OUTPUT/_testnt.txt -A 1 | grep -v \#)
		test_note=${test_note:0:190}
	fi

	ttm_rslt="SPM"

	time2trn=0

	vv="${osi[ipmmac]}, ${osi[startt]}, ${osi[endtme]}, ${osi[elapse]}, ${osi[testts]}, \
	${osi[ipmiip]}, ${osi[ipipv6]}, ${osi[fwvern]}, ${osi[fwdate]}, \
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
	fff=${OUTPUT}_${ipp}_$(date '+%Y-%m-%d~%H:%M:%S')_${SECONDS}_${bsl}

	# write test reult to sqlite3, create table
	sqlite3 gd-spkg.spm < ./init_db.sql &>/dev/null

	# check test note
	if [ -f _testnt.txt ]; then
		cp  _testnt.txt $OUTPUT/_testnt.txt
	fi

	# insert test result
	log2-metabasedb sql
	sqlite3 gd-spkg.spm < $OUTPUT/_insert.sql

	importsqlcockroach 	  $OUTPUT/_insert.sql

	mv $OUTPUT $fff

	save_sys_cert

	# copy to headquarter
	scp -o "StrictHostKeyChecking no" -P 7022 -r $fff spm@129.146.47.229:/home/spm/support_package_repo &>/dev/null
	
	rm -rf $HOME/.ssh/id_ed25519

	cp gd-spkg.spm ${fff}/
	./zip -r -P 'smci1500$4All' ${fff}.zip ${fff} &>/dev/null

	mkdir -p tmp
	mv ${fff}.zip tmp/

	rm -rf  ./.graph_dumps _exp &>/dev/null
}

function importsqlcockroach(){
	sql=${1:-_insert.sql}
	psql "postgresql://aves:_EKb2pIKnIew0ulmcvFohQ@perfmon-11634.6wr.aws-us-west-2.cockroachlabs.cloud:26257/toucan" -q -f $sql
}

function ts_gpu0010_count-gpu(){ #desc: gpu count should be 8
	cnt=$(hl-smi -L  | grep SPI | wc -l)
	[[ $cnt == 8 ]] && (echo -e "${FUNCNAME}: ${GRN}PASS${NCL}") || (echo -e "${FUNCNAME}: ${RED}FAIL${NCL}")
}

function ts_gpu0020_check-cpld(){ #desc: check gpu cpld: 10
	check_gpu_oam_cpld
	OAM_CPLDS=$(echo $OAM_CPLDS)

	[[ $OAM_CPLDS == "10 10 10 10 10 10 10 10" ]] && (echo -e "${FUNCNAME}: ${GRN}PASS${NCL}") || (echo -e "${FUNCNAME}: ${RED}FAIL${NCL}")
}

function save_sys_cert(){
mkdir -p $HOME/.ssh
cat > $HOME/.ssh/id_ed25519 <<- EOM
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
QyNTUxOQAAACD8yULF/xM3LIfvF0kAhmGbMtj9SOIwJ+htl5BasVgkuQAAAJDRxqQY0cak
GAAAAAtzc2gtZWQyNTUxOQAAACD8yULF/xM3LIfvF0kAhmGbMtj9SOIwJ+htl5BasVgkuQ
AAAED4k6iy8oAkU+sUQPxu/ugRADthGcHhUojmkFFM0EDVzPzJQsX/Ezcsh+8XSQCGYZsy
2P1I4jAn6G2XkFqxWCS5AAAACXJvb3RAc3BtMQECAwQ=
-----END OPENSSH PRIVATE KEY-----
EOM

}

# -------- test start

# optional command line arguments overwrite both default and config settings
parse_args "$@"

prerun-syscheck

# clear caches
PROC_FS=${PROC_FS:-"/proc"}
sync && echo 3 > $PROC_FS/sys/vm/drop_caches

# prepare directories
rm -rf   $OUTPUT &>/dev/null
mkdir -p $OUTPUT &>/dev/null

# start system monitoring
start_sys_mon

#echo $TESTCASE_ID $SYSTEM_INFO $SUPPORT_PKG
sleep 5

# stop monitoring process
stop_sys_mon

# log system os info
get_sys_envdata "supportpkg" "0.1" "mnist"

# print system info only
if [[ $SYSTEM_INFO -eq 1 ]]; then
	log2-metabasedb list
	rm -rf gd-spkg support_package_check.sh.x.c
	echo
fi

# print system info only
if [[ $TESTCASE_ID -ne 0 ]]; then
	echo "run case:" $TESTCASE_ID
	ts_gpu0010_count-gpu
	
	ts_gpu0020_check-cpld
	
	echo
fi

# save system info to sql and copy to remote server
if [[ $SUPPORT_PKG -eq 1 ]]; then
	echo -e "  ${YLW}Save System Info to DB${NCL}"
	log2-metabasedb sql
	
	echo -e "  ${YLW}Send Test Result to SMC${NCL}"
	save_result_remote
	echo
fi

echo -e "${BLU}Test Complete in ${SECONDS} seconds${NCL}\n" | tee -a $TRAIN_LOGF

# sqlite3 gd-spkg.spm 'SELECT * FROM GDSUPPORT;'
# sqlite3 gd-spkg.spm 'SELECT count(0) FROM GDSUPPORT;'
# ./zoi -U -f support_package_check.sh -o support_package_check && rm -rf support_package_check.sh.x.c
