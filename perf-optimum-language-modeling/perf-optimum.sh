#!/bin/bash

# Supermiro SPM
# https://docs.habana.ai/en/latest/Intel_DevCloud_Quick_Start/Intel_DevCloud_Quick_Start.html
# Jing Kang 9/2024

SRC=`readlink -f "${BASH_SOURCE[0]}" 2>/dev/null||echo $0`
CUR=`dirname "${SRC}"`
PAR=`dirname "${CUR}"`

source $PAR/common-modvars.sh

banner=(''
   $RED"  _                                                                _      _ _             \n"$NCL
   $RED" | |                                                              | |    | (_)            \n"$NCL
   $GRN" | | __ _ _ __   __ _ _   _  __ _  __ _  ___   _ __ ___   ___   __| | ___| |_ _ __   __ _ \n"$NCL
   $GRN" | |/ _\` | '_ \ / _\` | | | |/ _\` |/ _\` |/ _ \ | '_ \` _ \ / _ \ / _\` |/ _ \ | | '_ \ / _\` |\n"$NCL
   $GRN" | | (_| | | | | (_| | |_| | (_| | (_| |  __/ | | | | | | (_) | (_| |  __/ | | | | | (_| |\n"$NCL
   $BLU" |_|\__,_|_| |_|\__, |\__,_|\__,_|\__, |\___| |_| |_| |_|\___/ \__,_|\___|_|_|_| |_|\__, |\n"$NCL
   $BLU"                 __/ |             __/ |                                             __/ |\n"$NCL
   $BLU"                |___/             |___/                                             |___/ \n"$NCL
 )

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

function finetune_llama1-7b_mpi(){
	cd ${PAR}/optimum-habana/examples/language-modeling

	local model="${1:-huggyllama/llama-7b}"
	local mname=`echo $model | awk -F'/' '{print $2}'| tr '[:upper:]' '[:lower:]'`

	local datas="${2:-tatsu-lab/alpaca}"

	TRAINL=$OUTPUT/train-mpi-${mname}.log

	SECONDS=0
	
	python ../gaudi_spawn.py --world_size 8 --use_mpi run_lora_clm.py \
	--model_name_or_path  ${model} \
	--dataset_name 		  ${datas} \
	--do_train  \
	--do_eval   \
	--bf16 True \
	--output_dir  $OUTPUT/output/    \
	--logging_dir $OUTPUT/tboard/    \
	--per_device_train_batch_size 8 \
	--gradient_accumulation_steps 2  \
	--eval_strategy "no" \
	--save_strategy "no" \
	--learning_rate		3e-4 \
	--num_train_epochs	3 	 \
	--max_seq_length	512  \
	--warmup_ratio		0.03 \
	--lr_scheduler_type "constant" \
	--max_grad_norm  0.3 \
	--logging_steps	 1   \
	--use_habana    \
	--use_lazy_mode \
	--throughput_warmup_steps 3 \
	--lora_rank=8   \
	--lora_alpha=16 \
	--lora_dropout=0.05 \
	--lora_target_modules "q_proj" "v_proj" \
	--dataset_concatenation \
	--ddp_bucket_cap_mb 50  \
	--adam_epsilon 		1e-08 \
	--validation_split_percentage 4 \
	--low_cpu_mem_usage True \
	--overwrite_output_dir 2>&1 | tee -a $TRAINL

	rm -rf .graph_dumps hl-smi_log.txt 2>/dev/null
	TRAIN_TIME1=${SECONDS}
	cd -
	echo -e "\n  fine-tuning in mpi mode on ${YLW}LORA $model${NCL} with ${YLW}$datas${NCL}"
	print_result $model
}

function finetune_llama2-7b_fp8_mpi(){
	cd ${PAR}/optimum-habana/examples/language-modeling

	local model="${1:-meta-llama/Llama-2-7b-hf}"
	local mname=`echo $model | awk -F'/' '{print $2}'| tr '[:upper:]' '[:lower:]'`
	local datas="${2:-tatsu-lab/alpaca}"

	TRAINL=$OUTPUT/train-mpi-${mname}.log

	SECONDS=0
	
	LOWER_LIST=ops_bf16.txt python ../gaudi_spawn.py --world_size 8 --use_mpi run_lora_clm.py \
	--model_name_or_path $model \
	--dataset_name 		 $datas \
	--do_train  \
	--do_eval   \
	--bf16 True \
	--fp8 True	\
	--output_dir  $OUTPUT/output/    \
	--logging_dir $OUTPUT/tboard/    \
	--num_train_epochs 3 \
	--per_device_train_batch_size 16 \
	--gradient_accumulation_steps 1  \
	--eval_strategy "no" \
	--save_strategy "no" \
	--learning_rate 3e-4 \
	--warmup_ratio 0.03  \
	--max_grad_norm 0.3  \
	--logging_steps 20   \
	--lr_scheduler_type "constant" \
	--use_habana    \
	--use_lazy_mode \
	--throughput_warmup_steps 3 \
	--lora_rank=8       \
	--lora_alpha=16     \
	--lora_dropout=0.05 \
	--lora_target_modules "q_proj" "v_proj" \
	--dataset_concatenation \
	--max_seq_length 512    \
	--ddp_bucket_cap_mb 50  \
	--adam_epsilon 1e-08    \
	--validation_split_percentage 10 \
	--low_cpu_mem_usage True \
	--pipelining_fwd_bwd \
	--overwrite_output_dir 2>&1 | tee -a $TRAINL

	rm -rf .graph_dumps hl-smi_log.txt 2>/dev/null
	TRAIN_TIME2=${SECONDS}
	cd -
	echo -e "\n  fine-tuning in mpi mode on ${YLW}LORA $model${NCL} with ${YLW}$datas${NCL}"
	print_result $model
}

function create_ds_config (){
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
}

function finetune_llama2-70b_lora_deepspeed_zero3(){
	cd ${PAR}/optimum-habana/examples/language-modeling

	local model="${1:-meta-llama/Llama-2-70b-hf}"
	local mname=`echo $model | awk -F'/' '{print $2}'| tr '[:upper:]' '[:lower:]'`
	local datas="${2:-tatsu-lab/alpaca}"

	TRAINL=$OUTPUT/train-dpz-${mname}.log

	create_ds_config
	SECONDS=0

	PT_HPU_MAX_COMPOUND_OP_SIZE=10 \
	python3 ../gaudi_spawn.py --use_deepspeed --world_size 8 run_lora_clm.py \
	--model_name_or_path $model \
	--dataset_name		 $datas \
	--deepspeed 		dp.json \
	--do_train  \
	--do_eval   \
	--bf16 True \
	--fp8  True	\
	--output_dir  $OUTPUT/output/   \
	--logging_dir $OUTPUT/tboard/   \
	--num_train_epochs 2 \
	--max_seq_len	2048 \
	--per_device_train_batch_size 10 \
	--per_device_eval_batch_size   1 \
	--gradient_checkpointing \
	--eval_strategy epoch \
	--eval_delay 	2  \
	--save_strategy no \
	--learning_rate	3e-4   \
	--warmup_ratio	0.03   \
	--lr_scheduler_type "cosine" \
	--logging_steps 1 \
	--dataset_concatenation  \
	--attn_softmax_bf16 True \
	--use_habana \
	--use_lazy_mode \
	--pipelining_fwd_bwd \
	--throughput_warmup_steps 3 \
	--lora_rank 4 \
	--lora_target_modules "q_proj" "v_proj" "k_proj" "o_proj" \
	--validation_split_percentage 10 \
	--use_flash_attention True \
	--flash_attention_causal_mask True \
	--overwrite_output_dir 2>&1 | tee -a $TRAINL

	rm -rf .graph_dumps hl-smi_log.txt 2>/dev/null
	TRAIN_TIME3=${SECONDS}
	cd -
	echo -e "\n  fine-tuning in deepspeed zero3 mode on ${YLW}LORA $model${NCL} with ${YLW}$datas${NCL}"
	print_result $model
}

function finetune_llama2-70b_lora_mpi_fsdp(){
	cd ${PAR}/optimum-habana/examples/language-modeling

	local model="${1:-meta-llama/Llama-2-70b-hf}"
	local mname=`echo $model | awk -F'/' '{print $2}'| tr '[:upper:]' '[:lower:]'`
	local datas="${2:-tatsu-lab/alpaca}"

	TRAINL=$OUTPUT/train-fsdp-${mname}.log

	create_ds_config
	SECONDS=0

	LOWER_LIST=ops_bf16.txt PT_HPU_LAZY_MODE=0 \
	python3 ../gaudi_spawn.py --world_size 8 --use_mpi run_lora_clm.py \
	--model_name_or_path $model \
	--dataset_name		 $datas \
	--do_train  \
	--do_eval   \
	--bf16 True \
	--output_dir  $OUTPUT/output/   \
	--logging_dir $OUTPUT/tboard/   \
	--num_train_epochs 2 \
	--max_seq_len	2048 \
	--gradient_checkpointing \
	--per_device_train_batch_size 10 \
	--per_device_eval_batch_size  1  \
	--save_strategy no \
	--learning_rate 0.0004 \
	--warmup_ratio 0.03 \
	--lr_scheduler_type "constant" \
	--logging_steps 1 \
	--dataset_concatenation \
	--use_habana \
	--throughput_warmup_steps 3 \
	--lora_rank 4 \
	--lora_target_modules "q_proj" "v_proj" "k_proj" "o_proj" \
	--attn_softmax_bf16 True \
	--validation_split_percentage 4 \
	--use_lazy_mode False \
	--fsdp_config fsdp_config.json \
	--fsdp auto_wrap \
	--eval_strategy epoch \
	--eval_delay 2 \
	--pipelining_fwd_bwd False \
	--use_fused_rope False \
	--torch_compile_backend hpu_backend \
	--torch_compile \
	--gradient_accumulation_steps 2 \
	--use_flash_attention True \
	--flash_attention_causal_mask True \
	--overwrite_output_dir 2>&1 | tee -a $TRAINL

	rm -rf .graph_dumps hl-smi_log.txt 2>/dev/null
	TRAIN_TIME4=${SECONDS}
	cd -
	echo -e "\n  fine-tuning in mpi fsdp mode on ${YLW}LORA $model${NCL} with ${YLW}$datas${NCL}"
	print_result "llama-2-70b-fsdp"
}

function print_result(){
	cd $PWD 2>/dev/null
	
	local model="${1:-huggyllama/llama-7b}"
	local mname=`echo $model | awk -F'/' '{print $2}'| tr '[:upper:]' '[:lower:]'`

	TRAINL=$OUTPUT/train-mpi-${mname}.log

	cardn=8
	if [[ $1 == "huggyllama/llama-7b" ]]; then
		testresult="ft-llama1-7b.txt"
		threshold=150
	elif [[ $1 == "meta-llama/Llama-2-7b-hf" ]]; then
		testresult="ft-llama2-7b.txt"
		TRAINL=$OUTPUT/train-mpi-${mname}.log
		threshold=170
	elif [[ $1 == "meta-llama/Llama-2-70b-hf" ]]; then
		testresult="ft-llama-2-70b.txt"
		TRAINL=$OUTPUT/train-dpz-${mname}.log
		threshold=3.7
	elif [[ $1 == "llama-2-70b-fsdp" ]]; then
		testresult="ft-llama-2-70b-fsdp.txt"
		TRAINL=$OUTPUT/train-fsdp-llama-2-70b-hf.log
		threshold=1.5
	fi

	# train_samples_per_second
	tt=$(egrep "train_samples_per_second\s+=" $TRAINL | sed 's/=//')
	ta=($tt)

	# train_steps_per_second
	tt=$(egrep "train_steps_per_second\s+=" $TRAINL | sed 's/=//')
	tb=($tt)

	# train_runtime
	tt=$(egrep "train_runtime\s+=" $TRAINL | sed 's/=//')
	tc=($tt)

	# ---------- eval_samples_per_second
	tt=$(egrep "eval_samples_per_second\s+=" $TRAINL | sed 's/=//')
	ea=($tt)

	# eval_steps_per_second
	tt=$(egrep "eval_steps_per_second\s+=" $TRAINL | sed 's/=//')
	eb=($tt)
	
	# eval_runtime
	tt=$(egrep "eval_runtime\s+=" $TRAINL | sed 's/=//')
	ec=($tt)

	if [[ $1 == "huggyllama/llama-7b" ]]; then
		train_rt1=${tc[1]}
	elif [[ $1 == "meta-llama/Llama-2-7b-hf" ]]; then
		train_rt2=${tc[1]}
	elif [[ $1 == "meta-llama/Llama-2-70b-hf" ]]; then
		train_rt3=${tc[1]}
	elif [[ $1 == "llama-2-70b-fsdp" ]]; then
		train_rt4=${tc[1]}
	fi

	rec_time=$(date +%s)
	rec_YYYY=$(date '+%Y-%m-%d %H:%M:%S' -d @$rec_time)

	printf " %20s  %15s %15s %15s %15s %15s %15s\n" " " "train_samples/s" "train_steps/s" "eval_samples/s" "eval_steps/s" "train_runtime" "eval_runtime"

	if [[ $2 == "print_only" ]]; then
		printf " %20s  ${CYA}%15s %15s %15s %15s %15s %15s${NCL}\n" "${rec_YYYY}" ${ta[1]} ${tb[1]} ${ea[1]} ${eb[1]} ${tc[1]} ${ec[1]}
	else
		printf " %20s  ${CYA}%15s %15s %15s %15s %15s %15s${NCL}\n" "${rec_YYYY}" ${ta[1]} ${tb[1]} ${ea[1]} ${eb[1]} ${tc[1]} ${ec[1]}| tee -a $testresult
	fi

	echo -e "\n  ${YLW}history result${NCL}"
	tail -n 5 $testresult

	sampersec=${ta[1]}
	r1=$((`echo "${ta[1]} > $threshold" | bc`))
	if [[ r1 -eq 1 ]]; then
		echo -e "train_samples/s with $cardn card: ${GRN}PASS${NCL}" | tee -a $TRAINL
	else
		echo -e "train_samples/s with $cardn card: ${RED}FAIL${NCL} : ${ta[1]} < ${threshold}" | tee -a $TRAINL
		FINALT=1
	fi
}

function scp_results_remote(){
	# rename the result folder
	ee_time=$(date +%s)
	elapsed=$((`echo "$ee_time - $ss_time" | bc`))

	ipp=$(ifconfig | grep 'inet ' | grep -v -P '27.0|172.17' | awk '{print $2}')
	fff=$OUTPUT-${ipp}-${ee_time}-${elapsed}-${sampersec}

	# 119G after testing
	rm -rf $OUTPUT/output

	mv $OUTPUT $fff

	save_sys_cert
	scp -r -P 7022 -i ./id_rsa -o PasswordAuthentication=no -o StrictHostKeyChecking=no ${fff} spm@129.146.47.229:/home/spm/language-modeling/ &>/dev/null

	rm -rf  ./.graph_dumps _exp id_ed25519 id_rsa &>/dev/null
}

# ----- start test

ss_time=$(date +%s)

PWD=`pwd`

OUTPUT=`dirname $PWD`/optimum-perf-language-modeling/perf_optimum
FINALT=0

parse_args "$@"
prerun-check

printf "${banner[*]}\n"

model="huggyllama/llama-7b"
mname=`echo $model | awk -F'/' '{print $2}'| tr '[:upper:]' '[:lower:]'`

rm -rf   $OUTPUT 2>/dev/null
mkdir -p $OUTPUT 2>/dev/null
TRAINL=$OUTPUT/train-mpi-${mname}.log
TRAIN_LOGF=$TRAINL
touch $TRAINL
TRAIN_TIME1=0
train_rt1=0

TASK_NAME='alpaca'

update_optimum

start_sys_mon

echo -e "\n fine-tune ${YLW}${model} mpi${NCL}\n"
finetune_llama1-7b_mpi

echo -e "\n fine-tune ${YLW}llama2-7b fp8${NCL}\n"
finetune_llama2-7b_fp8_mpi

echo -e "\n fine-tune ${YLW}llama2-70b deepspeed zero3${NCL}\n"
finetune_llama2-70b_lora_deepspeed_zero3

echo -e "\n fine-tune ${YLW}llama2-70b fsdp${NCL}\n"
finetune_llama2-70b_lora_mpi_fsdp

stop_sys_mon

#print history result
echo -e '\n------------------------------\n'

echo -e "  result: ${YLW}llama2-70b deepspeed zero3${NCL} fine-tune\n"
print_result "meta-llama/Llama-2-70b-hf" "print_only" 

echo -e '\n------------------------------\n'

echo -e "  result: ${YLW}llama2-7b fp8${NCL} fine-tune\n"
print_result "meta-llama/Llama-2-7b-hf"	 "print_only" 

echo -e '\n------------------------------\n'

echo -e "  result: ${YLW}llama1-7b${NCL} fine-tune\n"
print_result "huggyllama/llama-7b"		 "print_only" 

echo -e '\n------------------------------\n'

# log system os info
get_test_envn_data "optimum" "1.13.2" "language-modeling"

# -------------

rec_time=$(date +%s)
rec_YYYY=$(date '+%Y-%m-%d %H:%M:%S' -d @$rec_time)

echo -e "${YLW}model testing time${NCL}         llama-7b        llama2-7b-fp8      llama2-70b-zero      llama2-70b-fsdp"
printf "%15s ${CYA}%15s %20s %20s %20s${NCL}\n" "${rec_YYYY}" $TRAIN_TIME1 $TRAIN_TIME2 $TRAIN_TIME3 $TRAIN_TIME4 | tee -a test_time.txt
echo
tail -n 5 test_time.txt

echo
echo -e "${YLW}model testing time${NCL}         llama-7b        llama2-7b-fp8      llama2-70b-zero      llama2-70b-fsdp"
printf "%15s ${CYA}%15s %20s %20s %20s${NCL}\n" "${rec_YYYY}" $train_rt1 $train_rt2 $train_rt3 $train_rt4 | tee -a runtime${TASK_NAME}
echo
tail -n 5 runtime${TASK_NAME}
echo

# max power reading
#hpw=$(sort $OUTPUT/_powerr.log | sort -n | tail -n 1)
#echo -e "${YLW}Maximum Power: ${hpw} watts${NCL}" | tee -a $TRAINL

# print top 30 stat info from hl-smi
print_topnn_hl_smi 10

#print_energy_usage

#save_service_procs

if [[ $FINALT == 0 ]] ; then
	echo -e "language-modeling ${YLW}fine-tune${NCL}: ${GRN}PASS${NCL}" | tee -a $TRAIN_LOGF
else
	echo -e "language-modeling ${YLW}fine-tune${NCL}: ${RED}FAIL${NCL}" | tee -a $TRAIN_LOGF
fi

scp_results_remote

echo
echo -e "${BLU}Test Complete: ${elapsed} sec${NCL}\n"
