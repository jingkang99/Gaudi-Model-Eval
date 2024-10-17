#!/bin/bash

# Supermiro SPM MLPerf Test for ResNet50
# Jing Kang 7/2024

SRC=`readlink -f "${BASH_SOURCE[0]}" 2>/dev/null||echo $0`
CUR=`dirname "${SRC}"`
PAR=`dirname "${CUR}"`

source $PAR/common-modvars.sh

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

# Default setting for Pytorch Resnet trainig - batch_256.cfg

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
OUTPUT=$LOGS_DIR
TRAIN_LOGF=$OUTPUT/train.log

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

# --- jk add check
prerun-check

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

# start system monitoring
start_sys_mon

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
	 $TOCH_COMPILE_FLAGS 2>&1 | tee -a $TRAIN_LOGF
ret="$?"
set +x
[ $ret != 0 ] && (echo -e "${RED}ERROR: mpirun exit ${ret} ${NCL}")

# stop monitoring process
stop_sys_mon

# log system os info
get_test_envn_data "mlperf" "3.1" "resnet"

# -------------
# time to train
ttt=$(for nn in {0..7} ; do grep 'run_start\|run_stop' $TRAIN_LOGF | grep worker${nn} | awk '{print $5}' | tr -d ',' | paste -sd " " - | awk '{print ($2 - $1) / 1000 / 60}' ; done | awk '{s+=$1}END{print s/NR}')
echo -e "${YLW}Time To Train: ${ttt} min${NCL}, < 16.80 min" | tee -a $TRAIN_LOGF
arr=$(for nn in {0..7} ; do grep 'run_start\|run_stop' $TRAIN_LOGF | grep worker${nn} | awk '{print $5}' | tr -d ',' | paste -sd " " - | awk '{print ($2 - $1) / 1000 / 60}' ; done)
i=0; for t in $arr ; do echo "  worker:"${i} ${t} | tee -a $TRAIN_LOGF; let i++; done
echo

# max power reading
hpw=$(sort $OUTPUT/_powerr.log | sort -n | tail -n 1)
echo -e "${YLW}Maximum Power: ${hpw} watts${NCL}" | tee -a $TRAIN_LOGF

# delete model checkpoint files
find $OUTPUT -name *.pt -type f -delete &>/dev/null
rm -rf  ./.graph_dumps _exp &>/dev/null 

# print top 30 stat info from hl-smi
print_topnn_hl_smi 30

echo -e "  ${YLW}Time To Train: ${ttt} min${NCL}, < 16.8 min\n" | tee -a $TRAIN_LOGF

#training result
echo -e "  ${YLW}Test Converge: loss < 1.75${NCL}" | tee -a $TRAIN_LOGF
grep 625/626 $TRAIN_LOGF | grep -P '\[0\]|\[17\]|\[34\]' | awk '{printf("  Epoch %4s lr %24s  img/s %-20s  loss \033[0;33m%7s\033[0m  acc1 %8s  acc5 %8s \n",  $2, $7, $9, $11, $14, $17);}' | tee -a $TRAIN_LOGF
lss=$(grep 625/626 $TRAIN_LOGF | grep -P '\[34\]' | awk '{print $11}')
echo | tee -a $TRAIN_LOGF

# PDU energy usage
print_energy_usage

#save_service_procs

if [[ $lss > 1 && $lss < 1.75 ]]
then
	echo -e "test converge: ${GRN}PASS${NCL}" | tee -a $TRAIN_LOGF
else
	echo -e "test converge: ${YLW}WARN${YLW}" | tee -a $TRAIN_LOGF
fi

# performance threshold
print_final_result 16.80

save_result_remote
