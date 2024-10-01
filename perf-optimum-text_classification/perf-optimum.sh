#!/bin/bash

# Supermiro SPM
# https://docs.habana.ai/en/latest/Intel_DevCloud_Quick_Start/Intel_DevCloud_Quick_Start.html
# Jing Kang 9/2024

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
        `basename $0` 

DESCRIPTION
        Runs optimum-habana text-classification 
			Execute Single-Card Training
			Execute Multi-Card  Training
			Training with DeepSpeed

        -od, --output-dir
            specify the output directory, used to store training results.

        -ee, --enable-evaluation
            if set, evaluation will be executed after training
            default: true

        -h, --help
            prints this help message.

EXAMPLES
       `basename $0`                                                 # 8-Gaudi local run
EOF
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
				check_gpu_oam_cpld
				echo -e "${YLW}OAM CPLD Version:${NCL} " $OAM_CPLDS
                exit 0 ;;
			-hf | --hosts-file )
                REMOTE_HOSTS=$(generate_host_list "$2" 8)
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
                OUTPUT="$2"
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

function update_optimum(){
	_pwd=`pwd`
	cd ..
	if [[ ! -f optimum-habana/.git/config ]]; then
		git clone --depth=1 https://github.com/huggingface/optimum-habana 2>/dev/null
	else
		git pull 2>/dev/null
	fi
	cd $_pwd
}

function single_card_bert_training(){
	cd ${PAR}/optimum-habana/examples/text-classification

	TRAINL=$OUTPUT/train-1-card.log

	SECONDS=0
	python run_glue.py \
	--model_name_or_path bert-large-uncased-whole-word-masking \
	--gaudi_config_name Habana/bert-large-uncased-whole-word-masking  \
	--task_name mrpc   \
	--do_train   \
	--do_eval    \
	--per_device_train_batch_size 32 \
	--learning_rate 	3e-5  \
	--num_train_epochs	3     \
	--max_seq_length 	128   \
	--seed 2024 \
	--output_dir  $OUTPUT/output/   \
	--logging_dir $OUTPUT/tboard/   \
	--use_habana    \
	--use_lazy_mode \
	--bf16 \
	--use_hpu_graphs_for_inference \
	--throughput_warmup_steps 3 \
	--overwrite_output_dir | tee -a $TRAINL

	rm -rf .graph_dumps 2>/dev/null
	TRAIN_TIME1=${SECONDS}
	cd -

	print_result "single"
}

function multi_card_bert_training(){
	# 
	# cd /sox/Gaudi-Model-Eval/optimum-habana/examples/text-classification
	#
	cd ${PAR}/optimum-habana/examples/text-classification
	
	TRAINL=$OUTPUT/train-8-card.log

	SECONDS=0
	python ../gaudi_spawn.py --world_size 8 --use_mpi run_glue.py  \
	--model_name_or_path bert-large-uncased-whole-word-masking  \
	--gaudi_config_name Habana/bert-large-uncased-whole-word-masking  \
	--task_name mrpc  \
	--do_train  \
	--do_eval   \
	--per_device_train_batch_size 32  \
	--per_device_eval_batch_size   8  \
	--learning_rate		3e-5  \
	--num_train_epochs	3     \
	--max_seq_length 	128   \
	--seed 2024 \
	--output_dir  $OUTPUT/output/   \
	--logging_dir $OUTPUT/tboard/   \
	--use_habana   \
	--use_lazy_mode   \
	--bf16 \
	--use_hpu_graphs_for_inference  \
	--throughput_warmup_steps 3 \
	--overwrite_output_dir | tee -a $TRAINL

	rm -rf .graph_dumps hl-smi_log.txt 2>/dev/null
	TRAIN_TIME2=${SECONDS}
	cd -

	echo -e "\n  exec multi_card_training\n"
	print_result "mpi"
}

function multi_card_deepspeed_training(){
	cd ${PAR}/optimum-habana/examples/text-classification

	TRAINL=$OUTPUT/train-8-deep.log

	cat > ds_config.json <<- EOM
{
    "steps_per_print": 1,
    "train_batch_size": "auto",
    "train_micro_batch_size_per_gpu": "auto",
    "gradient_accumulation_steps": "auto",
    "bf16": {
        "enabled": true
    },
    "gradient_clipping": 1.0,
    "zero_optimization": {
        "stage": 2,
        "overlap_comm": false,
        "reduce_scatter": false,
        "contiguous_gradients": false
    }
}
EOM

	SECONDS=0
	python ../gaudi_spawn.py --world_size 8 --use_deepspeed run_glue.py \
	--model_name_or_path bert-large-uncased-whole-word-masking \
	--gaudi_config_name Habana/bert-large-uncased-whole-word-masking \
	--task_name mrpc \
	--do_train \
	--do_eval  \
	--per_device_train_batch_size 32 \
	--per_device_eval_batch_size   8 \
	--learning_rate		3e-5 \
	--num_train_epochs	3 	 \
	--max_seq_length	128  \
	--seed 2024 \
	--output_dir  $OUTPUT/output/   \
	--logging_dir $OUTPUT/tboard/   \
	--use_habana	\
	--use_lazy_mode \
	--bf16 \
	--use_hpu_graphs_for_inference  \
	--throughput_warmup_steps 3 \
	--deepspeed ds_config.json  \
	--overwrite_output_dir | tee -a $TRAINL

	rm -rf .graph_dumps hl-smi_log.txt 2>/dev/null
	TRAIN_TIME3=${SECONDS}
	cd -

	echo -e "\n  exec multi_card deepspeed training\n"
	print_result "deepspeed"
}

function print_result(){
	cd $PWD 2>/dev/null

	if [[ $1 == "single" ]]; then
		testresult="ai-1-card.txt"
		TRAINL=$OUTPUT/train-1-card.log
		threshold=340
		cardn=1
	elif [[ $1 == "mpi" ]]; then
		testresult="ai-8-card.txt"
		TRAINL=$OUTPUT/train-8-card.log
		threshold=1100
		cardn=8
	elif [[ $1 == "deepspeed" ]]; then
		testresult="ai-8-deep.txt"
		TRAINL=$OUTPUT/train-8-deep.log
		threshold=1000
		cardn=8
	fi

	# train_samples_per_second
	tt=$(egrep "train_samples_per_second\s+=" $TRAINL | sed 's/=//')
	ta=($tt)

	# train_steps_per_second
	tt=$(egrep "train_steps_per_second\s+=" $TRAINL | sed 's/=//')
	tb=($tt)

	# eval_samples_per_second
	tt=$(egrep "eval_samples_per_second\s+=" $TRAINL | sed 's/=//')
	ea=($tt)

	# eval_steps_per_second
	tt=$(egrep "eval_steps_per_second\s+=" $TRAINL | sed 's/=//')
	eb=($tt)

	rec_time=$(date +%s)
	rec_YYYY=$(date '+%Y-%m-%d %H:%M:%S' -d @$rec_time)

	printf " %20s  %15s %15s %15s %15s\n" " " "train_samples/s" "train_steps_/s" "eval_samples/s" "eval_steps/s" 
	printf " %20s  ${CYA}%15s %15s %15s %15s${NCL}\n" "${rec_YYYY}" ${ta[1]} ${tb[1]} ${ea[1]} ${eb[1]} | tee -a $testresult

	echo -e "\n  ${YLW}history result${NCL}"
	tail -n 10 $testresult
	
	if [[ ${ta[1]} > $threshold ]]; then
		echo -e "train_samples/s with $cardn card: ${GRN}PASS${NCL}" | tee -a $TRAINL
	else
		echo -e "train_samples/s with $cardn card: ${RED}FAIL${NCL}" | tee -a $TRAINL
		FINALT=1
	fi
}

PWD=`pwd`

OUTPUT=`dirname $PWD`/optimum-perf/perf_optimum
FINALT=0

WANDB_MODE=disabled
WANDB_DISABLED=true

parse_args "$@"
prerun-check

rm -rf   $OUTPUT 2>/dev/null
mkdir -p $OUTPUT 2>/dev/null
touch $TRAINL

update_optimum

start_sys_mon

echo -e "\n  exec single_card_training\n"
single_card_bert_training

echo -e "\n  exec multi_card ${YLW}mpi${NCL} training\n"
multi_card_bert_training

echo -e "\n  exec multi_card ${YLW}deepspeed${NCL} training\n"
multi_card_deepspeed_training

stop_sys_mon

echo -e "\n  result: ${YLW}multi_card mpi${NCL} training\n"
print_result "mpi"

echo -e "\n  result: ${YLW}single_card ${NCL} training\n"
print_result "single"

echo 

# log system os info
get_test_envn_data "optimum" "1.13.2" "text-classification"

# -------------

rec_time=$(date +%s)
rec_YYYY=$(date '+%Y-%m-%d %H:%M:%S' -d @$rec_time)
echo "model testing time"
printf "%15s %15s %15s %15s\n" "${rec_YYYY}" $TRAIN_TIME1  $TRAIN_TIME2  $TRAIN_TIME3 | tee -a test_time.txt
tail -n 5 test_time.txt

# max power reading
#hpw=$(sort $OUTPUT/_powerr.log | sort -n | tail -n 1)
#echo -e "${YLW}Maximum Power: ${hpw} watts${NCL}" | tee -a $TRAINL

# print top 30 stat info from hl-smi
print_topnn_hl_smi 5

#print_energy_usage

#save_service_procs

rm -rf _exp 2>/dev/null
#save_result_remote
