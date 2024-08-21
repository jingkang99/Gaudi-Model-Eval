#!/bin/bash

# SPM MLPerf Test 
# Jing Kang 7/2024

MLPERFROOT=/sox/Gaudi-Model-Eval
alias bcd="cd $MLPERFROOT/bert-perf-result/$(  ls -tr $MLPERFROOT/bert-perf-result   | tail -n 1)"
alias rcd="cd $MLPERFROOT/resnet-perf-result/$(ls -tr $MLPERFROOT/resnet-perf-result | tail -n 1)"

GD2=1 && GD3=1
GMODEL=`hl-smi -L | head -n 12 | grep Product | awk '{print $4}'`
[[ $GMODEL =~ 'HL-225' ]] && GD2=0 || GD3=0

# Reset
Color_Off="\[\033[0m\]"       # Text Reset

# Regular Colors
Black="\[\033[0;30m\]"        # Black
Red="\[\033[0;31m\]"          # Red
Green="\[\033[0;32m\]"        # Green
Yellow="\[\033[0;33m\]"       # Yellow
Blue="\[\033[0;34m\]"         # Blue
Purple="\[\033[0;35m\]"       # Purple
Cyan="\[\033[0;36m\]"         # Cyan
White="\[\033[0;37m\]"        # White

# Bold
BBlack="\[\033[1;30m\]"       # Black
BRed="\[\033[1;31m\]"         # Red
BGreen="\[\033[1;32m\]"       # Green
BYellow="\[\033[1;33m\]"      # Yellow
BBlue="\[\033[1;34m\]"        # Blue
BPurple="\[\033[1;35m\]"      # Purple
BCyan="\[\033[1;36m\]"        # Cyan
BWhite="\[\033[1;37m\]"       # White

# Underline
UBlack="\[\033[4;30m\]"       # Black
URed="\[\033[4;31m\]"         # Red
UGreen="\[\033[4;32m\]"       # Green
UYellow="\[\033[4;33m\]"      # Yellow
UBlue="\[\033[4;34m\]"        # Blue
UPurple="\[\033[4;35m\]"      # Purple
UCyan="\[\033[4;36m\]"        # Cyan
UWhite="\[\033[4;37m\]"       # White

# Background
On_Black="\[\033[40m\]"       # Black
On_Red="\[\033[41m\]"         # Red
On_Green="\[\033[42m\]"       # Green
On_Yellow="\[\033[43m\]"      # Yellow
On_Blue="\[\033[44m\]"        # Blue
On_Purple="\[\033[45m\]"      # Purple
On_Cyan="\[\033[46m\]"        # Cyan
On_White="\[\033[47m\]"       # White

# High Intensty
IBlack="\[\033[0;90m\]"       # Black
IRed="\[\033[0;91m\]"         # Red
IGreen="\[\033[0;92m\]"       # Green
IYellow="\[\033[0;93m\]"      # Yellow
IBlue="\[\033[0;94m\]"        # Blue
IPurple="\[\033[0;95m\]"      # Purple
ICyan="\[\033[0;96m\]"        # Cyan
IWhite="\[\033[0;97m\]"       # White

# Bold High Intensty
BIBlack="\[\033[1;90m\]"      # Black
BIRed="\[\033[1;91m\]"        # Red
BIGreen="\[\033[1;92m\]"      # Green
BIYellow="\[\033[1;93m\]"     # Yellow
BIBlue="\[\033[1;94m\]"       # Blue
BIPurple="\[\033[1;95m\]"     # Purple
BICyan="\[\033[1;96m\]"       # Cyan
BIWhite="\[\033[1;97m\]"      # White

# High Intensty backgrounds
On_IBlack="\[\033[0;100m\]"   # Black
On_IRed="\[\033[0;101m\]"     # Red
On_IGreen="\[\033[0;102m\]"   # Green
On_IYellow="\[\033[0;103m\]"  # Yellow
On_IBlue="\[\033[0;104m\]"    # Blue
On_IPurple="\[\033[10;95m\]"  # Purple
On_ICyan="\[\033[0;106m\]"    # Cyan
On_IWhite="\[\033[0;107m\]"   # White

# Various variables you might want for your PS1 prompt instead
Time12h="\T"
Time12a="\@"
PathShort="\w"
PathFull="\W"
NewLine="\n"
Jobs="\j"

export PS1=$IBlack$Time12h$Color_Off'$(git branch &>/dev/null;\
if [ $? -eq 0 ]; then \
  echo "$(echo `git status` | grep "nothing to commit" > /dev/null 2>&1; \
  if [ "$?" -eq "0" ]; then \
    # @4 - Clean repository - nothing to commit
    echo "'$Green'"$(__git_ps1 " (%s)"); \
  else \
    # @5 - Changes to working tree
    echo "'$IRed'"$(__git_ps1 " {%s}"); \
  fi) '$BYellow$PathShort$Color_Off'\$ "; \
else \
  # @2 - Prompt when not in GIT repo
  echo " '$Yellow$PathShort$Color_Off'\$ "; \
fi)'
git config --global alias.lg "log --color --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr)%C(bold blue)<%an>%Creset' --abbrev-commit"

RED='\033[0;31m'
YLW='\033[0;33m'
BLU='\033[0;34m'
GRN='\033[0;32m'
BCY='\033[1;36m'
CYA='\033[0;36m'
NCL='\033[0m' 

# global var
tmpf=
PDUCHK=
PDUSTATUS=
OAM_CPLDS=
start_time=

function prerun-check(){
    # add required modules
    apt install -y ipmitool expect sqlite3 postgresql-client &>/dev/null

	ping -c1 -W1 -q $(head -n 1 ${CUR}/apc-pdu.cnf) &>/dev/null
	PDUCHK=$?
	[[ $PDUCHK -eq 0 ]] && PDUSTATUS='UP' || PDUSTATUS='DOWN'

	BUSY=$(hl-smi |  grep "N/A   N/A    N/A" | wc -l)
	if [ $BUSY -ne 8 ]
	then
		echo -e "${RED}System Occupied! ${NCL}"
		exit 1
	fi

	start_time=$(date +%s)

	check_gpu_int_port

	echo '' > /var/log/kern.log

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
		echo -e "  ${YLW}Start MLPerf LLMs Testing${NCL} ${start_time}" | tee -a $tmpf
		echo -e "  ${YLW}Gaudi internal ports UP count: ${NCL} " ${UP_PORTS} | tee -a $tmpf
		
		check_gpu_oam_cpld
		echo -e "  ${YLW}OAM CPLD   :${NCL}" $OAM_CPLDS | tee -a $tmpf
		echo -e "  ${YLW}PDU Console:${NCL}" `head -n 1  ${CUR}/apc-pdu.cnf` ${PDUSTATUS} | tee -a $tmpf
		echo
		echo performance | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor &>/dev/null
	else
		echo -e "${RED}ERROR: habana python module not found${NCL}"
		exit 1
	fi

	mpiver=$(ls /opt/habanalabs/ | grep openmpi | cut -b 9-)
	export PATH=/opt/python-llm/bin:/opt/habanalabs/openmpi-${mpiver}/bin:${PAR}/tool:$PATH
	export PT_HPU_LAZY_MODE=1
	SECONDS=0
}

# check Gaudi interal ports 
function check_gpu_int_port(){
	UP_PORTS=$(hl-smi -Q bus_id -f csv,noheader | xargs -I % hl-smi -i % -n link | grep UP | wc -l)
	if [ $UP_PORTS != 168 ]
	then
		echo -e "${RED}ERROR: Gaudi internal ports Not All Up${NCL}"
		
		[[ $GD2 ]] && gp=gaudi2 || gp=gaudi3
		echo -e "${GRN}  /opt/habanalabs/qual/${gp}/bin/manage_network_ifs.sh --up${NCL}"

		echo -e "${GRN}  reboot or reload habana driver${NCL}"
		echo -e "${GRN}  rmmod habanalabs${NCL}"
		echo -e "${GRN}  modprobe habanalabs${NCL}\n"
		echo -e "${GRN}  $(basename $0) --check-ports${NCL}\n"
		exit 1
	fi
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

function generate_host_list(){
    HOSTS_PATH=$1
    local num_nodes=${2:-8}
    HOSTS_LIST=""

    while IFS= read -r ip; do
        HOSTS_LIST="$HOSTS_LIST,$ip:8"
    done < "$HOSTS_PATH"

    echo "${HOSTS_LIST:1}"
}

function start_sys_mon(){
	echo "start mon:" $(date)

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

	cat $tmpf > $TRAIN_LOGF
	rm  $tmpf

	# save open listening ports
	(sleep 480 && netstat -lntp > $OUTPUT/_openpt.log) &
}

function stop_sys_mon(){
	pkill watch
	pkill mpstat
	pkill hl-smi
	pkill free
	pkill tee
}

function get_test_envn_data(){
	# log system info
	end_time=$(date +%s)
	#date -d @1718326649
	echo ${start_time} > $OUTPUT/_time_s.log
	echo ${end_time}  >> $OUTPUT/_time_s.log

	MLOG=$OUTPUT/_module.log
	pip check > $MLOG; pip list | grep -P 'habana|tensor|torch|transformers' >> $MLOG; dpkg-query -W | grep habana >> $MLOG; lsmod | grep habana >> $MLOG
	echo '-------' >> $MLOG

	#IFS='\n' arr=($(ipmitool fru | grep Board | awk -F ': ' '{print $2}'))
	mapfile -t arr < <( ipmitool fru | grep Board | awk -F ': ' '{print $2}' )
	echo "mfgdat:" ${arr[0]}  >> $MLOG
	echo "mfgvdr:" ${arr[1]}  >> $MLOG
	echo "mboard:" ${arr[2]}  >> $MLOG
	echo "serial:" ${arr[3]}  >> $MLOG

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
	
	hosnic=$(lspci | grep Eth | grep $(dmesg | grep $macadd | awk -F'0000:' '{print $2}' | awk -F': ' '{print $1}') | awk -F': ' '{print $2}')
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

function print_topnn_hl_smi(){
	# print top 10 stat
	local cnt=$1
	mapfile -t mem < <( awk '{print $10}' $OUTPUT/_hl-smi.log | sort -n | uniq -c | tail -n $cnt )
	mapfile -t utl < <( awk '{print $14}' $OUTPUT/_hl-smi.log | sort -n | uniq -c | tail -n $cnt )
	mapfile -t tpr < <( awk '{print $12}' $OUTPUT/_hl-smi.log | sort -n | uniq -c | tail -n $cnt )
	mapfile -t pow < <( awk '{print $16}' $OUTPUT/_hl-smi.log | sort -n | uniq -c | tail -n $cnt )

	echo -e "  ${CYA}GPU Top 10 Stats - 131 times checked${NCL}" | tee -a $TRAIN_LOGF
	echo -e "  ${CYA}cnt PowerDraw   cnt AIP-Util   cnt Temprature  cnt Memory-Usage${NCL}" | tee -a $TRAIN_LOGF
	for (( i=0; i<${#mem[@]}; i++ ));
	do
		echo -e "    ${BCY}${pow[$i]}     ${utl[$i]}       ${tpr[$i]}     ${mem[$i]}${NCL}" | tee -a $TRAIN_LOGF
	done
	if [[ $(hl-smi -Q name -f csv,noheader | head -n 1) == "HL-225"  ]]; then
		echo -e "${GRN}  max       550 W    	   100 %            100 C           98304 MB${NCL}\n" | tee -a $TRAIN_LOGF
	else
		echo -e "${GRN}  max       550 W    	   100 %            100 C           131072 MB${NCL}\n" | tee -a $TRAIN_LOGF
	fi
}

function print_energy_usage(){
	# calc power usage
	pdu=$OUTPUT/_pdulog.log
	if [[ $(wc -l $pdu | awk '{print $1}' ) -gt 20 ]]
	then
		engy_s=`head -n 2 $pdu | tail -n 1 | awk '{print $1}'`
		engy_e=`tail -n 1 $pdu | awk '{print $1}'`
		usedee=`echo "$engy_e $engy_s" | awk '{print $1-$2}'`

		echo -e "  pdu energy used: ${YLW}${usedee}${NCL} kWh : ${engy_s} ${engy_e}" | tee -a $TRAIN_LOGF;
		printf "  ${CYA}max\n" | tee -a $TRAIN_LOGF;
		printf "  energy/kWh    power/kW    appower/kVA    current/A    voltage/V    ipmi/Watts${NCL}\n" | tee -a $TRAIN_LOGF;

		max_eng=`grep -P '\d+\.\d' $pdu | awk '{print $1}' | sort -n | tail -n 1`
		max_pow=`grep -P '\d+\.\d' $pdu | awk '{print $2}' | sort -n | tail -n 1`
		max_app=`grep -P '\d+\.\d' $pdu | awk '{print $3}' | sort -n | tail -n 1`
		max_cur=`grep -P '\d+\.\d' $pdu | awk '{print $4}' | sort -n | tail -n 1`
		max_vol=`grep -P '\d+\.\d' $pdu | awk '{print $5}' | sort -n | tail -n 1`
		max_bmc=`grep -P '\d+\.\d' $pdu | awk '{print $6}' | sort -n | tail -n 1`

		printf "${BCY}%8s     %8s      %8s       %8s     %8s  %8s${NCL}\n\n" $max_eng  $max_pow  $max_app  $max_cur  $max_vol  $max_bmc | tee -a $TRAIN_LOGF;
	fi
}

function save_service_procs(){
	# check services
	systemctl list-units --state running | grep running | grep -v session- > $OUTPUT/_servcs.log
	diff $OUTPUT/_servcs.log ../service.diff
	[[ $? -eq 0 ]] && echo -e "services diff: ${GRN}PASS${NCL}" | tee -a $TRAIN_LOGF || echo -e "services diff: ${YLW}WARN${NCL}" | tee -a $TRAIN_LOGF
	echo | tee -a $TRAIN_LOGF

	# check process
	pp='sshd|bash|CMD|ps|awk|sort|sftp|sleep|bin/login|agetty|dbus-daemon|udevd'
	echo "check process, skip "$(echo $pp | sed 's/|/ /g')
	ps -ef | grep -v -P "\\[|$pp" | awk '{print $8}'| sort > $OUTPUT/_procss.log
	diff $OUTPUT/_procss.log ../process.diff
	[[ $? -eq 0 ]] && echo -e "process  diff: ${GRN}PASS${NCL}" | tee -a $TRAIN_LOGF || echo -e "process  diff: ${YLW}WARN${NCL}" | tee -a $TRAIN_LOGF
	echo | tee -a $TRAIN_LOGF
	
	cp /var/log/kern.log $OUTPUT/_kernal.log
	TS=$(date +"%b %d")
	grep -P "^${TS}.+accel accel" /var/log/syslog | tail -n 2000 > $OUTPUT/_logsys.log
	
	cat > $OUTPUT/_intrvl.log <<- EOM
_powerr.log 10
_hl-smi.log 10
_pdulog.log 10
_im-sdr.log 30
_im-ssr.log 30
_iostat.log 30
_python.log 30
_mpstat.log 30
_memmon.log 30
_python.log 30log-
EOM
}

# bert: 16.5 - 
function print_final_result(){
	if [[ $ttt > 10 && $ttt < $1 ]]
	then
		echo -e "time to train: ${GRN}PASS${NCL}" | tee -a $TRAIN_LOGF
	else
		echo -e "time to train: ${RED}FAIL${NCL}" | tee -a $TRAIN_LOGF
	fi

	echo -e "${BLU}Test Complete: ${SECONDS} sec${NCL}\n" | tee -a $TRAIN_LOGF
}

function save_result_remote(){
	ipp=$(ifconfig | grep 'inet ' | grep -v -P '27.0|172.17' | awk '{print $2}')
	fff=$OUTPUT-${ipp}-${end_time}-${SECONDS}-${ttt}

	# write test reult to sqlite3, create table
	sqlite3 mlperf_largelm_test.db3 < ../init_db_mlperf_test.sh &>/dev/null

	# check test note
	if [ -f _testnt.txt ]; then
		cp  _testnt.txt $OUTPUT/_testnt.txt
	fi

	# insert test result
	OUTPUT=$OUTPUT bash ../log-2dashboard.sh sql | tail -n 1 > $OUTPUT/_insert.sql
	sqlite3 mlperf_largelm_test.db3 < $OUTPUT/_insert.sql

	importsqlcockroach $OUTPUT/_insert.sql

	mv $OUTPUT $fff
	
	# copy to headquarter
	save_sys_cert
	scp -o "StrictHostKeyChecking no" ./id_rsa -P 7022 -r $fff spm@129.146.47.229:/home/spm/mlperf31-bert-test-result/ &>/dev/null

	# scp -r $fff spm@172.24.189.10:/home/spm/mlperf31-bert-test-result/   &>/dev/null
	# scp -P 7022 -r $fff spm@129.146.47.229:/home/spm/mlperf31-bert-test-result/  &>/dev/null
	
	rm -rf  ./.graph_dumps _exp id_ed25519 id_rsa &>/dev/null 
}

function importsqlcockroach(){
	sql=${1:-_insert.sql}
	
	psql "postgresql://aves:_EKb2pIKnIew0ulmcvFohQ@perfmon-11634.6wr.aws-us-west-2.cockroachlabs.cloud:26257/toucan" -q -f $sql

	#psql "postgresql://aves:_EKb2pIKnIew0ulmcvFohQ@perfmon-11634.6wr.aws-us-west-2.cockroachlabs.cloud:26257/toucan?sslmode=verify-full" -q -f $sql
}

# convert date format
# date -d'Wed Jul 24 05:38:12 PM PDT 2024' '+%Y-%m-%d %H:%M:%S'
function conv_date(){
	date -d"${1}" '+%Y-%m-%d %H:%M:%S'
}

function piplist_size(){
    python -c "for d in __import__('importlib.metadata').metadata.distributions(): print('{:>12.3f} KiB  {}'.format(sum(0 if not f.locate().is_file() else f.locate().stat().st_size for f in d.files) / 1024, d.name))" | sort -n
}

function save_sys_cert(){
cat > id_ed25519 <<- EOM
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
QyNTUxOQAAACD8yULF/xM3LIfvF0kAhmGbMtj9SOIwJ+htl5BasVgkuQAAAJDRxqQY0cak
GAAAAAtzc2gtZWQyNTUxOQAAACD8yULF/xM3LIfvF0kAhmGbMtj9SOIwJ+htl5BasVgkuQ
AAAED4k6iy8oAkU+sUQPxu/ugRADthGcHhUojmkFFM0EDVzPzJQsX/Ezcsh+8XSQCGYZsy
2P1I4jAn6G2XkFqxWCS5AAAACXJvb3RAc3BtMQECAwQ=
-----END OPENSSH PRIVATE KEY-----
EOM

cat > id_rsa <<- EOM
-----BEGIN OPENSSH PRIVATE KEY-----
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
qP9N6WIsGIYwkAAAAJcm9vdEBzcG0xAQI=
-----END OPENSSH PRIVATE KEY-----
EOM
}