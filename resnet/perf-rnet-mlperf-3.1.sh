#!/bin/bash

# Supermiro SPM MLPerf Test for ResNet50
# Jing Kang 7/2024

RED='\033[0;31m'
YLW='\033[0;33m'
BLU='\033[0;34m'
GRN='\033[0;32m'
BCY='\033[1;36m'
CYA='\033[0;36m'
NCL='\033[0m' 

function check_internal_ports()
{	# check Gaudi interal ports
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

function print_synopsis()
{
    cat << EOF
NAME
        `basename $0`

SYNOPSIS
        `basename $0` [-c <config>] [-ld <log-dir>] [-wd <work-dir>] [-dd <data-dir>] [-h]

DESCRIPTION
        Runs 8-gaudi local MLPerf Resnet training on PyTorch.

        -c <config-file>, --config <config-file>
            configuration file containing series of "export VAR_NAME=value" commands
            overrides default settings for Resnet training

        -ld <log-dir>, --log-dir <log-dir>
            specify the loggin directory, used to store mllogs and outputs from all mpi processes

        -wd <work-dir>, --work-dir <work-dir>
            specify the work directory, used to store temporary files during the training

        -dd <data-dir>
            specify the data directory, containing the ImageNet dataset

        -ut <bool>, --use-torch-compile <bool>
            turn on the torch compile, default is false

        -h, --help
            print this help message

EXAMPLES
       `basename $0` -wd /data/imagenet
            MLPerf Resnet training on dataset stored in /data/imagenet

EOF
}

function parse_config()
{
    while [ -n "$1" ]; do
        case "$1" in
            -c | --config )
                CONFIG_FILE=$2
                if [[ -f ${CONFIG_FILE} ]]; then
	                source $CONFIG_FILE
                    return
                else
                    echo "Could not find ${CONFIG_FILE}"
                    exit 1
                fi
                ;;
            * )
                shift
                ;;
        esac
    done
}

function parse_args()
{
    while [ -n "$1" ]; do
        case "$1" in
            -c | --config )
                shift 2
                ;;
            -ld | --log-dir )
                LOGS_DIR=$2
                shift 2
                ;;
            -wd | --work-dir )
                WORK_DIR=$2
                shift 2
                ;;
            -dd | --data-dir )
                DATA_ROOT=$2
                shift 2
                ;;
            -ut | --use-torch-compile )
                USE_TORCH_COMPILE=$2
                shift 2
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
            -ph | --perf-hpage)
				echo -e "${YLW}set scaling_governor to performance${NCL}"
				echo -e "${YLW}set vm.nr_hugepages  to 153600${NCL}"
                echo performance | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
				sysctl -w vm.nr_hugepages=153600
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

# Default setting for Pytorch Resnet trainig

NUM_WORKERS_PER_HLS=8
EVAL_OFFSET_EPOCHS=3
EPOCHS_BETWEEN_EVALS=4
DISPLAY_STEPS=1000

NUM_WORKERS=8
BATCH_SIZE=256
TRAIN_EPOCHS=35
LARS_DECAY_EPOCHS=36
WARMUP_EPOCHS=3
BASE_LEARNING_RATE=9
END_LEARNING_RATE=0.0001
WEIGHT_DECAY=0.00005
LR_MOMENTUM=0.9
LABEL_SMOOTH=0.1
STOP_THRESHOLD=0.759
USE_TORCH_COMPILE=false

DATA_ROOT=./data-train/
WORK_DIR=../resnet-perf-result/work
LOGS_DIR=../resnet-perf-result/perf
SCRIPT_DIR=$(dirname "${BASH_SOURCE[0]}")
OUTPUT_DIR=$LOGS_DIR
TRAIN_LOGF=$OUTPUT_DIR/train.log

# Default MPI settings
MPI_HOSTS=localhost:8
MPI_PATH=/opt/habanalabs/openmpi-4.1.5
MPI_OUTPUT=../resnet-perf-result/mpil
SSH_PORT=3022

# MASTER_ADDR and MASTER_PORT are consumed by PyTorch c10d to establish a distributed group
export MASTER_ADDR=${MASTER_ADDR:-127.0.0.1}
export MASTER_PORT=${MASTER_PORT:-12345}

# apply optional config, overwriting default settings
parse_config "$@"

# optional command line arguments overwrite both default and config settings
parse_args "$@"

# --- jk check before test

gbusy=$(hl-smi |  grep "N/A   N/A    N/A" | wc -l)
if [ $gbusy -ne 8 ]
then
	echo -e "${RED}System Occupied! ${NCL}"
	exit 1
fi

start_time=$(date +%s)

check_internal_ports

echo '' > /var/log/kern.log

which ipmitool &>/dev/null
[ $? != 0 ] && (echo -e "${RED}ERROR: need ipmitool${NCL}"; exit 2)

which expect &>/dev/null
[ $? != 0 ] && (echo -e "${RED}ERROR: need expect${NCL}"; exit 2)

pip list | grep habana &>/dev/null
if [ $? -eq 0 ]
then
	echo -e "  ${YLW}Start MLPerf 3.1 ResNet Testing${NCL} ${start_time}"
	echo -e "  ${YLW}Gaudi internal ports UP count ${UP_PORTS}${NCL}"
	echo
	sleep 3
else
	echo -e "${RED}ERROR: habana python module not found${NCL}"
	exit 1
fi

export PATH=/opt/python-llm/bin:/opt/habanalabs/openmpi-4.1.5/bin:$PATH
export PT_HPU_LAZY_MODE=1
SECONDS=0
# --- jk end

# Use torch compile
if [ "$USE_TORCH_COMPILE" == "true" ]; then
    echo "torch.compile enabled"
    TOCH_COMPILE_FLAGS="--use_torch_compile --run-lazy-mode false"
else
    TORCH_COMPILE_FLAGS=""
fi

# Clear caches
PROC_FS=${PROC_FS:-"/proc"}
sync && echo 3 > $PROC_FS/sys/vm/drop_caches

# determine the number of available cores for each process
MPI_MAP_BY_PE=`lscpu | grep "^CPU(s):"| awk -v NUM=${NUM_WORKERS_PER_HLS} '{print int($2/NUM/2)}'`

# prepare directories
rm -rf   $LOGS_DIR $WORK_DIR $MPI_OUTPUT
mkdir -p $LOGS_DIR $WORK_DIR $MPI_OUTPUT

# start mon 
echo "start mon:" $(date)

watch -n 10 "ipmitool dcmi power reading | grep Instantaneous | awk '{print \$4}' | tee -a $OUTPUT_DIR/_powerr.log" &>/dev/null &
watch -n 30 "ipmitool sdr   | tee -a $OUTPUT_DIR/_im-sdr.log" &>/dev/null &
watch -n 30 "ipmitool sensor| tee -a $OUTPUT_DIR/_im-ssr.log" &>/dev/null &

hl-smi -Q timestamp,index,serial,bus_id,memory.used,temperature.aip,utilization.aip,power.draw -f csv,noheader -l 10 | tee $OUTPUT_DIR/_hl-smi.log &>/dev/null &

watch -n 30 "S_COLORS=always iostat -xm | grep -v loop | tee -a $OUTPUT_DIR/_iostat.log" &>/dev/null &
watch -n 30 "ps -Ao user,pcpu,pid,command --sort=pcpu | grep python | head -n 50 | tee -a $OUTPUT_DIR/_python.log" &>/dev/null &

mpstat 30 | tee $OUTPUT_DIR/_mpstat.log  &>/dev/null & 

watch -n 30 "free -g | grep Mem | tee -a $OUTPUT_DIR/_memmon.log" &>/dev/null &

bash monitor-pwrdu-status.sh | tee $OUTPUT_DIR/_pdulog.log &>/dev/null &

# run Pytorch Resnet training
set -x
time mpirun \
	--allow-run-as-root \
	--np $NUM_WORKERS \
	--bind-to core \
	--rank-by core \
	--map-by socket:PE=$MPI_MAP_BY_PE \
	-H $MPI_HOSTS \
	--report-bindings \
	--tag-output \
	--merge-stderr-to-stdout \
	--output-filename $LOGS_DIR \
	--prefix $MPI_PATH \
	-x PT_HPU_AUTOCAST_LOWER_PRECISION_OPS_LIST=$SCRIPT_DIR/pytorch/ops_bf16_Resnet.txt \
	-x PT_HPU_AUTOCAST_FP32_OPS_LIST=$SCRIPT_DIR/pytorch/ops_fp32_Resnet.txt \
	python3 $SCRIPT_DIR/pytorch/train.py \
	--model resnet50 \
	--device hpu \
	--print-freq $DISPLAY_STEPS \
	--channels-last False \
	--dl-time-exclude False \
	--output-dir $WORK_DIR \
	--log-dir $LOGS_DIR \
	--data-path $DATA_ROOT \
	--eval_offset_epochs $EVAL_OFFSET_EPOCHS \
	--epochs_between_evals $EPOCHS_BETWEEN_EVALS \
	--workers $NUM_WORKERS_PER_HLS \
	--batch-size $BATCH_SIZE \
	--epochs $TRAIN_EPOCHS \
	--lars_decay_epochs $LARS_DECAY_EPOCHS \
	--warmup_epochs $WARMUP_EPOCHS \
	--base_learning_rate $BASE_LEARNING_RATE \
	--end_learning_rate $END_LEARNING_RATE \
	--weight-decay $WEIGHT_DECAY \
	--momentum $LR_MOMENTUM \
	--label-smoothing $LABEL_SMOOTH \
	--target_accuracy $STOP_THRESHOLD \
	--use_autocast \
	--dl-worker-type HABANA \
	 $TOCH_COMPILE_FLAGS 2>&1 | tee $TRAIN_LOGF
ret="$?"
set +x
[ $ret != 0 ] && (echo -e "${RED}ERROR: mpirun exit ${ret} ${NCL}")

pkill watch
pkill mpstat
pkill hl-smi
pkill free
pkill tee

# log system info
end_time=$(date +%s)
#date -d @1718326649

MLOG=$OUTPUT_DIR/_module.log
pip check > $MLOG; pip list | grep -P 'habana|tensor|torch' >> $MLOG; dpkg-query -W | grep habana >> $MLOG; lsmod | grep habana >> $MLOG
echo '-------' >> $MLOG

#IFS='\n' arr=($(ipmitool fru | grep Board | awk -F ': ' '{print $2}'))
mapfile -t arr < <( ipmitool fru | grep Board | awk -F ': ' '{print $2}' )

echo "mfgdat:" ${arr[0]}  >> $MLOG
echo "mfgvdr:" ${arr[1]}  >> $MLOG
echo "mboard:" ${arr[2]}  >> $MLOG
echo "serial:" ${arr[3]}  >> $MLOG

mapfile -t arr < <( dmidecode | grep -i "BIOS Information" -A 3 | awk -F ': ' '{print $2}' )
echo "biosvr:" ${arr[2]}  >> $MLOG
echo "biosdt:" ${arr[3]}  >> $MLOG

echo "ipmiip:" $(ipmitool lan print | grep -P "IP Address\s+: " | awk -F ': ' '{print $2}') >> $MLOG
echo "ipmmac:" $(ipmitool lan print | grep -P "MAC Address\s+: "| awk -F ': ' '{print $2}') >> $MLOG

echo "cpumdl:" $(lscpu | grep Xeon | awk -F ')' '{print $3}' | cut -c 2- | sed 's/i u/iu/' ) >> $MLOG
echo "cpucor:" $(lscpu | grep "^CPU(s):" | awk '{print $2}') >> $MLOG
echo "pcinfo:" $(dmidecode | grep 'PCI' | tail -n 1 | awk -F': ' '{print $2}') >> $MLOG

echo "memcnt:" $(lsmem | grep "online memory" | awk '{print $4}') >> $MLOG

echo "" >> $MLOG
echo "osintl:" $(stat --format=%w /) >> $MLOG
echo "machid:" $(cat /etc/machine-id)>> $MLOG

echo "govnor:" $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor) >> $MLOG
echo "hgpage:" $(grep HugePages_Total /proc/meminfo | awk '{print $2}') >> $MLOG

hostip=$(ifconfig | grep broadcast | grep -v 172.17 | awk '{print $2}')
echo "kernel:" $(uname -a) >> $MLOG
echo "hostip:" ${hostip}   >> $MLOG
echo "hosmac:" $(ifconfig | grep $hostip -A 2 | grep ether |  awk '{print $2}') >> $MLOG

echo "uptime:" $(uptime) >> $MLOG

echo "habana:" $(hl-smi -v | grep -P '\s+'| awk -F 'version' '{print $2}') >> $MLOG
echo "startt:" ${start_time} >> $MLOG
echo "endtme:" ${end_time}   >> $MLOG
echo "elapse:" $(($end_time-$start_time)) >> $MLOG
echo "testts:" $(date) >> $MLOG

echo "" >> $MLOG
hl-smi -Q timestamp,index,serial,bus_id,memory.used,temperature.aip,utilization.aip,power.draw -f csv,noheader >> $MLOG
hl-smi | grep HL-225 | awk '{print "gpu busidr- " $2,$6}' >> $MLOG

ipmitool dcmi power reading >> $MLOG

# -------------
# time to train
ttt=$(for nn in {0..7} ; do grep 'run_start\|run_stop' $OUTPUT_DIR/train.log | grep worker${nn} | awk '{print $5}' | tr -d ',' | paste -sd " " - | awk '{print ($2 - $1) / 1000 / 60}' ; done | awk '{s+=$1}END{print s/NR}')
echo -e "${YLW}Time To Train: ${ttt} min${NCL}, < 16.5 min" | tee -a $TRAIN_LOGF
arr=$(for nn in {0..7} ; do grep 'run_start\|run_stop' $OUTPUT_DIR/train.log | grep worker${nn} | awk '{print $5}' | tr -d ',' | paste -sd " " - | awk '{print ($2 - $1) / 1000 / 60}' ; done)
i=0; for t in $arr ; do echo "  worker:"${i} ${t} | tee -a $TRAIN_LOGF; let i++; done
echo

# max power reading
hpw=$(sort $OUTPUT_DIR/_powerr.log | sort -n | tail -n 1)
echo -e "${YLW}Maximum Power: ${hpw} watts${NCL}" | tee -a $TRAIN_LOGF

# delete model checkpoint files
find $OUTPUT_DIR -name *.pt -type f -delete &>/dev/null
rm -rf  ./.graph_dumps _exp &>/dev/null 

# print top 10 stat
cnt=10
mapfile -t mem < <( awk '{print $10}' $OUTPUT_DIR/_hl-smi.log | sort -n | uniq -c | tail -n $cnt )
mapfile -t utl < <( awk '{print $14}' $OUTPUT_DIR/_hl-smi.log | sort -n | uniq -c | tail -n $cnt )
mapfile -t tmp < <( awk '{print $12}' $OUTPUT_DIR/_hl-smi.log | sort -n | uniq -c | tail -n $cnt )
mapfile -t pow < <( awk '{print $16}' $OUTPUT_DIR/_hl-smi.log | sort -n | uniq -c | tail -n $cnt )

echo -e "  ${CYA}GPU Top 10 Stats${NCL}" | tee -a $TRAIN_LOGF
echo -e "  ${CYA}cnt PowerDraw   cnt AIP-Util   cnt Temprature  cnt Memory-Usage${NCL}" | tee -a $TRAIN_LOGF
for (( i=0; i<${#mem[@]}; i++ ));
do
    echo -e "    ${BCY}${pow[$i]}     ${utl[$i]}       ${tmp[$i]}     ${mem[$i]}${NCL}" | tee -a $TRAIN_LOGF
done
echo | tee -a $TRAIN_LOGF
echo -e "${GRN}  max       550 W    	    100 %                           98304 MB${NCL}\n" | tee -a $TRAIN_LOGF

echo -e "  ${YLW}Time To Train: ${ttt} min${NCL}, < 16.5 min\n" | tee -a $TRAIN_LOGF

# calc power usage
pdu=$OUTPUT_DIR/_pdulog.log
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

if [[ $ttt > 10 && $ttt < 16.5 ]]
then
	echo -e "time to train: ${GRN}PASS${NCL}" | tee -a $TRAIN_LOGF
else
	echo -e "time to train: ${RED}FAIL${NCL}" | tee -a $TRAIN_LOGF
fi

echo -e "${BLU}Test Complete: ${SECONDS} sec${NCL}\n" | tee -a $TRAIN_LOGF

cp /var/log/kern.log $OUTPUT_DIR/_kernal.log
TS=$(date +"%b %d")
grep -P "^${TS}.+accel accel" /var/log/syslog | tail -n 2000 > $OUTPUT_DIR/_logsys.log

ipp=$(ifconfig | grep 'inet ' | grep -v -P '27.0|172.17' | awk '{print $2}')
fff=$OUTPUT_DIR-${ipp}-${end_time}-${SECONDS}-${ttt}

mv $OUTPUT_DIR $fff
scp -P 7022 -r $fff spm@129.146.47.229:/home/spm/mlperf31-resn-test-result/ &>/dev/null

exit 0
