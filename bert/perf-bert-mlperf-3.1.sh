#!/bin/bash

# Supermiro SPM MLPerf Test for BERT
# Jing Kang 6/2024

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

OAM_CPLD=
function check_oam_cpld(){
	OAM_CPLD=$( \
			ipmitool raw 0x30 0x70 0xef 4 0x70 0x40 0xe6 0x40 2 0x4a 1 0x0; \
			ipmitool raw 0x30 0x70 0xef 4 0x70 0x40 0xe6 0x41 2 0x4a 1 0x0; \
			ipmitool raw 0x30 0x70 0xef 4 0x70 0x40 0xe6 0x42 2 0x4a 1 0x0; \
			ipmitool raw 0x30 0x70 0xef 4 0x70 0x40 0xe6 0x43 2 0x4a 1 0x0; \
			ipmitool raw 0x30 0x70 0xef 4 0x70 0x40 0xe6 0x44 2 0x4a 1 0x0; \
			ipmitool raw 0x30 0x70 0xef 4 0x70 0x40 0xe6 0x45 2 0x4a 1 0x0; \
			ipmitool raw 0x30 0x70 0xef 4 0x70 0x40 0xe6 0x46 2 0x4a 1 0x0; \
			ipmitool raw 0x30 0x70 0xef 4 0x70 0x40 0xe6 0x47 2 0x4a 1 0x0  )
}

function print_synopsis()
{
    cat << EOF
NAME
        `basename $0`

SYNOPSIS
        `basename $0` [-H <hosts>] [-p <sshport>] [-dd <data-dir>] [-od <output-dir>] [-ep <enable-profiling>] [-ee <enable-evaluation>]

DESCRIPTION
        Runs MLPerf BERT pre-training training and evaluation on PyTorch with optional Habana profiling runs.

        -hf, --hosts-file
            path to a file containing list of IPs for nodes.

        -H, --hosts
            comma-separated list of workers' hostnames or IP addresses
            default: localhost:8

        -p, --ssh-port
            socket port number used by mpirun to establish a inter-process communication for multi-box
            default: 22

        -dd, --data-dir
            specify the data directory, containing books-wiki packed dataset.

        -od, --output-dir
            specify the output directory, used to store training results.

        -ee, --enable-evaluation
            if set, evaluation will be executed after training
            default: true

        -h, --help
            prints this help message.

EXAMPLES
       `basename $0`                                                 # 8-Gaudi local run
       `basename $0` -dd /mnt/data/books_wiki_packed -od /tmp/output # 8-Gaudi local run, overriding data-dir and output-dir
       `basename $0` -ep true                                        # 8-Gaudi local run, with profiling enabled
       `basename $0` -H 10.111.131.28:8,10.111.131.27:8              # 16-Gaudi multi-box run
EOF
}

function generate_hosts_list()
{
    HOSTS_PATH=$1
    local num_nodes=${2:-8}
    HOSTS_LIST=""

    while IFS= read -r ip; do
        HOSTS_LIST="$HOSTS_LIST,$ip:8"
    done < "$HOSTS_PATH"

    echo "${HOSTS_LIST:1}"
}

function parse_args()
{
    REMOTE_SSH_PORT='22'
    REMOTE_HOSTS="localhost:8"

    while true; do
        case "$1" in
            -h | --help )
				print_synopsis
                exit 0 ;;
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
            -co | --check-oam)
				check_oam_cpld
				echo -e "${YLW}OAM CPLD Version:${NCL} " $OAM_CPLD
                exit 0 ;;
			-hf | --hosts-file )
                REMOTE_HOSTS=$(generate_hosts_list "$2" 8)
                shift 2 ;;
            -H | --hosts )
                REMOTE_HOSTS="$2"
                shift 2 ;;
            -p | --ssh-port )
                REMOTE_SSH_PORT="$2"
                shift 2 ;;
            -dd | --data-dir )
                DATA_ROOT="$2"
                shift 2 ;;
            -od | --output-dir )
                OUTPUT_DIR="$2"
                shift 2 ;;
            -ee | --enable-evaluation )
                ENABLE_EVALUATION="$2"
                shift 2 ;;
            -ua | --use-autocast )
                USE_AUTOCAST="$2"
                shift 2 ;;
            -ll | --lower-list )
                PT_HPU_AUTOCAST_LOWER_PRECISION_OPS_LIST="$2"
                shift 2 ;;
            -fl | --f32-list )
                PT_HPU_AUTOCAST_FP32_OPS_LIST="$2"
                shift 2 ;;
            -- )
                shift
                break ;;
            * )
                if [[ -n "$1" ]]; then
                    echo "error: invalid parameter: $1"
                    exit -1
                fi
                break ;;
        esac
    done

    [[ "$REMOTE_HOSTS" =~ 'localhost' ]] || _multibox=true
}

SCRIPT_DIR=mlperf-3.1
DATA_ROOT=data-train
INPUT_DIR=$DATA_ROOT/packed
PHASE_1_CKPT=$DATA_ROOT/model.ckpt-28252.pt
EVAL_DIR=$DATA_ROOT/eval_varlength/

OUTPUT_DIR=../bert-perf-result/perf
ENABLE_EVALUATION=true
USE_AUTOCAST=true

# autocast files paths
PT_HPU_AUTOCAST_LOWER_PRECISION_OPS_LIST=$SCRIPT_DIR/ops_bf16_bert_pt.txt
PT_HPU_AUTOCAST_FP32_OPS_LIST=$SCRIPT_DIR/ops_fp32_bert_pt.txt

# parse arguments, possibly overwriting the default settings, print help
parse_args "$@"

# --- jk check before test
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
	echo -e "  ${YLW}Start MLPerf Bert Testing${NCL} ${start_time}"
	echo -e "  ${YLW}Gaudi internal ports UP count: ${NCL} " ${UP_PORTS}
	check_oam_cpld
	echo -e "  ${YLW}OAM CPLD   :${NCL}" $OAM_CPLD
	echo -e "  ${YLW}PDU Console:${NCL}" `head -n 1  apc-pdu.cnf`
	echo
	sleep 3
else
	echo -e "${RED}ERROR: habana python module not found${NCL}"
	exit 1
fi

export PATH=/opt/python-llm/bin:/opt/habanalabs/openmpi-4.1.5/bin:../tool/:$PATH
export PT_HPU_LAZY_MODE=1
SECONDS=0
# --- jk end

# output files for console logging for train/eval
DESCR_FILE=$OUTPUT_DIR/desc.txt
TRAIN_LOGF=$OUTPUT_DIR/train.log

# output directories for train/eval
RESULTS_DIR_FOR_TRAIN_EVAL=$OUTPUT_DIR/result
RESULTS_DIR_FOR_INIT_CKPT_EVAL=$OUTPUT_DIR/result_init_ckpt

# checkpoint dirs for train/eval
CKPT_DIR_FOR_TRAIN_AND_EVAL=$RESULTS_DIR_FOR_TRAIN_EVAL/checkpoints
RESULTS_DIR_FOR_INIT_CKPT_EVAL=$RESULTS_DIR_FOR_INIT_CKPT_EVAL/checkpoints

# dlloger output files for train/eval
DLLOGER_OUT_TRAIN_AND_EVAL=$RESULTS_DIR_FOR_TRAIN_EVAL/dlloger.json

# tensorboard directory for run and train
TB_DIR_TRAIN=$OUTPUT_DIR/tb_train
TB_DIR_INIT_EVAL=$OUTPUT_DIR/tb_init_eval

# MASTER_ADDR and MASTER_PORT are consumed by PyTorch c10d to establish a distributed group
if [ -z "$_multibox" ]; then
    _master_addr='127.0.0.1'
else
    _master_addr=`hostname -i`
fi
export MASTER_ADDR=${MASTER_ADDR:-$_master_addr}
export MASTER_PORT=${MASTER_PORT:-12345}

# build the primary mpirun command for the preparation and training
read -r -d '' MPIRUN_CMD << EOM
    mpirun \
        --allow-run-as-root \
        --tag-output \
        -x PT_HPU_AUTOCAST_LOWER_PRECISION_OPS_LIST=$PT_HPU_AUTOCAST_LOWER_PRECISION_OPS_LIST \
        -x PT_HPU_AUTOCAST_FP32_OPS_LIST=$PT_HPU_AUTOCAST_FP32_OPS_LIST \
        -H $REMOTE_HOSTS
EOM

if [ -n "$_multibox" ]; then
    read -r -d '' MPIRUN_CMD << EOM
    $MPIRUN_CMD \
        --mca plm_rsh_args "-p$REMOTE_SSH_PORT" \
        --prefix /opt/amazon/openmpi \
        -x DATA_LOADER_AEON_LIB_PATH \
        -x FI_EFA_ENABLE_SHM_TRANSFER \
        -x HABANA_LOGS \
        -x LD_LIBRARY_PATH \
        -x LD_PRELOAD \
        -x MASTER_ADDR \
        -x MASTER_PORT \
        -x PATH \
        -x PYTHONPATH \
        -x TCMALLOC_LARGE_ALLOC_REPORT_THRESHOLD \
        -x HCL_USE_EDMA_COMMAND_V2_GAUDI2 \
        -x PT_HPU_LAZY_ACC_PAR_MODE \
        -x PT_HPU_LAZY_MODE=${PT_HPU_LAZY_MODE:-$PT_HPU_LAZY_MODE}
EOM
fi

# test mpirun invocation by counting workers
WORKER_REPORTS=`$MPIRUN_CMD echo 'WORKER_REPORTS' | grep -F 'WORKER_REPORTS'`
NUM_WORKERS=`echo "$WORKER_REPORTS" | wc -l`
IFS="," read -ra _distinc_host_arr <<< "$REMOTE_HOSTS"
NUM_NODES=${#_distinc_host_arr[@]}
NUM_LOCAL_WORKERS=`expr $NUM_WORKERS / $NUM_NODES`

# build the auxiliary mpirun command for (local) evaluation
read -r -d '' MPIRUN_LOCAL_CMD << EOM
    mpirun \
        --allow-run-as-root \
        --tag-output \
        -n $NUM_LOCAL_WORKERS
EOM

# determine key hyperparameters
case "$NUM_WORKERS" in
    8 )
        NUM_ACCUM_STEPS=2
        TOTAL_BATCH_SIZE=$((28*$NUM_ACCUM_STEPS))
        TRAIN_STEPS=6700
        LEARNING_RATE=0.000425
        SAVE_CHECKPOINTS_STEPS=335
        LAMB_BETA_1=0.9
        LAMB_BETA_2=0.999
        LAMB_WEIGHT_DECAY=0.01
        EVAL_BATCH_SIZE=125
        MAX_EVAL_STEPS=10
        NUM_DIST_EVAL_WORKERS=8
        # 'fastddp' distribution strategy performs gradient clipping normalization before all-reduce, but effectively there is no gradient accumulation
        DISTRIBUTION_OPTION='--distribution_strategy fastddp --allreduce_dtype bf16 --use_hpu_graph true'
        ;;
    16 )
        NUM_ACCUM_STEPS=8
        TOTAL_BATCH_SIZE=$((24*$NUM_ACCUM_STEPS))
        TRAIN_STEPS=1140
        LEARNING_RATE=0.002
        SAVE_CHECKPOINTS_STEPS=57
        LAMB_BETA_1=0.71
        LAMB_BETA_2=0.998
        LAMB_WEIGHT_DECAY=0.01
        EVAL_BATCH_SIZE=125
        MAX_EVAL_STEPS=5
        NUM_DIST_EVAL_WORKERS=16
        # 'gradientbuffer' distribution strategy performs gradient clipping normalization before every accumulation
        DISTRIBUTION_OPTION='--distribution_strategy gradientbuffer --allreduce_dtype fp32'

        # Disable PT bridge's accumulation thread (see: SW-113836)
        export PT_HPU_LAZY_ACC_PAR_MODE=0
        ;;
    32 )
        NUM_ACCUM_STEPS=4
        TOTAL_BATCH_SIZE=$((24*$NUM_ACCUM_STEPS))
        TRAIN_STEPS=1140
        LEARNING_RATE=0.002
        SAVE_CHECKPOINTS_STEPS=57
        LAMB_BETA_1=0.71
        LAMB_BETA_2=0.998
        LAMB_WEIGHT_DECAY=0.01
        EVAL_BATCH_SIZE=100
        MAX_EVAL_STEPS=4
        NUM_DIST_EVAL_WORKERS=25
        # 'gradientbuffer' distribution strategy performs gradient clipping normalization before every accumulation
        DISTRIBUTION_OPTION='--distribution_strategy gradientbuffer --allreduce_dtype fp32'

        # Disable PT bridge's accumulation thread (see: SW-113836)
        export PT_HPU_LAZY_ACC_PAR_MODE=0
        ;;
    64 )
        NUM_ACCUM_STEPS=2
        TOTAL_BATCH_SIZE=$((24*$NUM_ACCUM_STEPS))
        TRAIN_STEPS=1140
        LEARNING_RATE=0.0021
        SAVE_CHECKPOINTS_STEPS=57
        LAMB_BETA_1=0.625
        LAMB_BETA_2=0.8675
        LAMB_WEIGHT_DECAY=0.0075
        EVAL_BATCH_SIZE=100
        MAX_EVAL_STEPS=2
        NUM_DIST_EVAL_WORKERS=50
        # 'gradientbuffer' distribution strategy performs gradient clipping normalization before every accumulation
        # [SW-114363] TODO: As there is effectively only 1 accumulation per step, consider using FastDDP. Check it with bf16.
        DISTRIBUTION_OPTION='--distribution_strategy fastddp --allreduce_dtype bf16 --use_hpu_graph true'
        ;;
    * )
        echo "error: invalid or unsupported total number of workers: $NUM_WORKERS"
        exit -1
esac

# NUM_EVAL_EXAMPLES is always expected to 10000.
NUM_EVAL_EXAMPLES=$(($EVAL_BATCH_SIZE*$NUM_DIST_EVAL_WORKERS*$MAX_EVAL_STEPS))
if [[ $NUM_EVAL_EXAMPLES != 10000 ]]; then
    echo "error: NUM_EVAL_EXAMPLES must be exactly 10000, but is: $NUM_EVAL_EXAMPLES"
    exit -1
fi

# TOTAL_BATCH_SIZE already contains NUM_ACCUM_STEPS this is why it is not present here
SAMPLES_BETWEEN_EVAL=$(($TOTAL_BATCH_SIZE*$NUM_WORKERS*$SAVE_CHECKPOINTS_STEPS))

PROC_FS=${PROC_FS:-"/proc"}
# install requirements, clear caches and reset the output directory (on every node)
read -r -d '' PREPARE_CMD << EOM
    if [[ \$OMPI_COMM_WORLD_LOCAL_RANK == 0 ]]; then \
        sync && echo 3 > $PROC_FS/sys/vm/drop_caches ; \
        rm -rf $OUTPUT_DIR ; \
        mkdir -p $CKPT_DIR_FOR_TRAIN_AND_EVAL ; \
        mkdir -p $TB_DIR_TRAIN ; \
        mkdir -p $RESULTS_DIR_FOR_INIT_CKPT_EVAL ; \
        mkdir -p $TB_DIR_INIT_EVAL ; \
    fi
EOM

set -x
$MPIRUN_CMD bash -c "$PREPARE_CMD"
set +x

# setup mpirun core binding
MPI_MAP_BY_PE=${MPI_MAP_BY_PE:-`lscpu | grep "^CPU(s):"| awk -v NUM=${NUM_LOCAL_WORKERS} '{print int($2/NUM/2)}'`}
read -r -d '' MPIRUN_CMD << EOM
$MPIRUN_CMD \
    --bind-to core \
    --map-by socket:PE=$MPI_MAP_BY_PE \
    --rank-by core \
    --report-bindings
EOM
read -r -d '' MPIRUN_LOCAL_CMD << EOM
$MPIRUN_LOCAL_CMD \
    --bind-to core \
    --map-by socket:PE=$MPI_MAP_BY_PE \
    --rank-by core \
    --report-bindings
EOM

# label the run (on this node)
cat > $DESCR_FILE <<- EOM
Date                    : `date`

# parameters configurable from the environment
MPI_MAP_BY_PE           : $MPI_MAP_BY_PE  (numer of CPU cores assigned exclusively to each worker process)
MASTER_ADDR             : $MASTER_ADDR  (hostname or IP address of the distributed group leader)
MASTER_PORT             : $MASTER_PORT  (socket port number used by PyTorch c10d to establish a distributed group)

# input parameters
REMOTE_HOSTS            : $REMOTE_HOSTS  (comma-separated list of workers' hostnames or IP addresses)
REMOTE_SSH_PORT         : $REMOTE_SSH_PORT  (socket port number used by mpirun to establish a inter-process connections in multi-box mode)

# other parameters which are in effect
NUM_WORKERS             : $NUM_WORKERS  (total number of distributed workers)
NUM_NODES               : $NUM_NODES  (number of nodes involved)
NUM_LOCAL_WORKERS       : $NUM_LOCAL_WORKERS  (number of distributed workers per node)

# training
TOTAL_BATCH_SIZE        : $TOTAL_BATCH_SIZE
TRAIN_STEPS             : $TRAIN_STEPS
LEARNING_RATE           : $LEARNING_RATE
LAMB_BETA_1             : $LAMB_BETA_1
LAMB_BETA_2             : $LAMB_BETA_2
LAMB_WEIGHT_DECAY       : $LAMB_WEIGHT_DECAY
dataset                 : packed
gradient_accumulation_steps : $NUM_ACCUM_STEPS  (effectively /2 due to packed dataset)

# evaluation
SAVE_CHECKPOINTS_STEPS  : $SAVE_CHECKPOINTS_STEPS
EVAL_BATCH_SIZE         : $EVAL_BATCH_SIZE
MAX_EVAL_STEPS          : $MAX_EVAL_STEPS
NUM_DIST_EVAL_WORKERS   : $NUM_DIST_EVAL_WORKERS
NUM_EVAL_EXAMPLES       : $NUM_EVAL_EXAMPLES
EOM
cat $DESCR_FILE

if [ "$ENABLE_EVALUATION" == "true" ]; then
    echo
    echo 'Running training & evaluation'
    echo
    EVALUATION_FLAG="--do_eval"
else
    echo
    echo 'Running training (no evaluation)'
    echo
    EVALUATION_FLAG=""
fi

# start mon 
echo "start mon:" $(date)

watch -n 10 "ipmitool dcmi power reading | grep Instantaneous | awk '{print \$4}' | tee -a $OUTPUT_DIR/_powerr.log" &>/dev/null &
watch -n 30 "ipmitool sdr   | tee -a $OUTPUT_DIR/_im-sdr.log" &>/dev/null &
watch -n 30 "ipmitool sensor| tee -a $OUTPUT_DIR/_im-ssr.log" &>/dev/null &

hl-smi -Q timestamp,index,serial,bus_id,memory.used,temperature.aip,utilization.aip,power.draw -f csv,noheader -l 10 | tee $OUTPUT_DIR/_hl-smi.log &>/dev/null &

watch -n 30 "S_COLORS=always iostat -xm | grep -v loop | tee -a $OUTPUT_DIR/_iostat.log" &>/dev/null &
watch -n 30 "ps -Ao user,pcpu,pid,command --sort=pcpu | grep python | head -n 50 | tee -a $OUTPUT_DIR/_python.log" &>/dev/null &

mpstat 30 | tee $OUTPUT_DIR/_mpstat.log  &>/dev/null & 
free -g -s 30 | grep Mem | tee $OUTPUT_DIR/_memmon.log &>/dev/null &

# check PDU ip and start monitor
ping -c1 -W1 -q $(head -n 1 apc-pdu.cnf) &>/dev/null
if [[ $? -eq 0 ]]; then
    bash monitor-pwrdu-status.sh | tee $OUTPUT_DIR/_pdulog.log &>/dev/null &
else
	echo "0 0 0 0 0 0" > $OUTPUT_DIR/_pdulog.log
fi

# change log_freq from 20 to 50
set -x
time $MPIRUN_CMD python3 $SCRIPT_DIR/run_pretraining.py \
    --config_file $SCRIPT_DIR/bert_config.json \
    --output_dir $CKPT_DIR_FOR_TRAIN_AND_EVAL \
    --do_train \
    $EVALUATION_FLAG \
    --json-summary $DLLOGER_OUT_TRAIN_AND_EVAL \
    --use_fused_lamb \
    --use_habana \
    --use_autocast $USE_AUTOCAST \
    --input_dir $INPUT_DIR \
    --max_seq_length 512 \
    --train_batch_size $TOTAL_BATCH_SIZE \
    --learning_rate $LEARNING_RATE \
    --lamb_beta_1 $LAMB_BETA_1 \
    --lamb_beta_2 $LAMB_BETA_2 \
    --lamb_weight_decay $LAMB_WEIGHT_DECAY \
    --max_predictions_per_seq 76 \
    --warmup_proportion 0 \
    --max_steps $TRAIN_STEPS \
    --gradient_accumulation_steps $NUM_ACCUM_STEPS \
    --num_steps_per_checkpoint $SAVE_CHECKPOINTS_STEPS \
    --phase2 \
    --log_freq 20 \
    --init_checkpoint $PHASE_1_CKPT \
    --eval_dir $EVAL_DIR \
    --eval_batch_size $EVAL_BATCH_SIZE \
    --num_eval_examples $NUM_EVAL_EXAMPLES \
    --num_eval_workers $NUM_DIST_EVAL_WORKERS \
    --samples_between_eval $SAMPLES_BETWEEN_EVAL \
    --enable_packed_data_mode true \
    --checkpoint_filter model \
    $DISTRIBUTION_OPTION \
    --tensorboard_dir $TB_DIR_TRAIN  2>&1 | tee $TRAIN_LOGF
retval="$?"
set +x

pkill watch
pkill mpstat
pkill hl-smi
pkill free
pkill tee

# log system info
end_time=$(date +%s)
#date -d @1718326649
echo ${start_time} > $OUTPUT_DIR/_time_s.log
echo ${end_time}  >> $OUTPUT_DIR/_time_s.log

MLOG=$OUTPUT_DIR/_module.log
pip check > $MLOG; pip list | grep -P 'habana|tensor|torch' >> $MLOG; dpkg-query -W | grep habana >> $MLOG; lsmod | grep habana >> $MLOG
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
echo "gpcpld:" $OAM_CPLD >> $MLOG

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

echo -e "  ${CYA}average_perf_per_step, Higher is Better. data processed/training, 20 steps/training, total steps:6700 ${NCL}${BCY}" | tee -a $TRAIN_LOGF;
mapfile -t aaa < <(grep "average_perf_per_step : " $OUTPUT_DIR/train.log | awk -F "average_perf_per_step : " '{print $2}' | awk -F "." '{print $1}' | sort | uniq -c)
echo -n -e ${BCY}
for (( i=0; i<${#aaa[@]}; i=$(($i + 2)) ));
do
	printf "%11s %s\n" ${aaa[$i]} ${aaa[ $(($i + 1)) ]} | tee -a $TRAIN_LOGF
done
echo -e "${NCL}" | tee -a $TRAIN_LOGF

echo -e "  ${YLW}Time To Train: ${ttt} min${NCL}, < 16.5 min\n" | tee -a $TRAIN_LOGF

avg_tts=$(grep "average_perf_per_step : " $OUTPUT_DIR/train.log | awk -F "average_training_time_step : " '{print $2}' | awk '{ sum += $1; n++ } END { if (n > 0) print sum / n; }' )
echo -e "  ${CYA}average_training_time_step: ${NCL}${YLW}${avg_tts}${NCL} < 0.165	\n" | tee -a $TRAIN_LOGF;

# training summary
# grep training_sequences_per_second $OUTPUT_DIR/train.log | awk -F ':' '{for (i=5; i<NF; i++) printf $i":"; print $NF}';echo | tee -a $TRAIN_LOGF;
mapfile -t rst < <( grep e2e_train_time $OUTPUT_DIR/train.log | awk '{printf("%s %s %s %s\n", $9, $12, $15, $19);}' | awk '{OFS=RS;$1=$1}1' )
echo -e "  e2e_train_time      : ${YLW}${rst[0]} ${NCL}\n" | tee -a $TRAIN_LOGF;
echo -e "  training_sequences/s: ${YLW}${rst[1]} ${NCL}\n" | tee -a $TRAIN_LOGF;
echo -e "  final_loss          : ${YLW}${rst[2]} ${NCL}\n" | tee -a $TRAIN_LOGF;
echo -e "  raw_train_time      : ${YLW}${rst[3]} ${NCL}\n" | tee -a $TRAIN_LOGF;

eval_t=$(grep "eval used time" $TRAIN_LOGF  | grep 1,0 | awk '{print $4}' | cut -c 1-6)
echo -e "  model eval time: ${eval_t}\n" | tee -a $TRAIN_LOGF;

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

if [[ $avg_tts > 0.1 && $avg_tts < 0.18 ]]
then
	echo -e "avgtrain time: ${GRN}PASS${NCL}" | tee -a $TRAIN_LOGF
else
	echo -e "avgtrain time: ${RED}FAIL${NCL}" | tee -a $TRAIN_LOGF
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

cat > $OUTPUT_DIR/_intrvl.log <<- EOM
_powerr.log 10
_hl-smi.log 10
_pdulog.log 10
_im-sdr.log 30
_im-ssr.log 30
_iostat.log 30
_python.log 30
_mpstat.log 30
_memmon.log 30
_python.log 30
EOM

ipp=$(ifconfig | grep 'inet ' | grep -v -P '27.0|172.17' | awk '{print $2}')
fff=$OUTPUT_DIR-${ipp}-${end_time}-${SECONDS}-${ttt}

mv $OUTPUT_DIR $fff

#       scp -r $fff spm@172.24.189.10:/home/spm/mlperf31-bert-test-result/   &>/dev/null
scp -P 7022 -r $fff spm@129.146.47.229:/home/spm/mlperf31-bert-test-result/  &>/dev/null
