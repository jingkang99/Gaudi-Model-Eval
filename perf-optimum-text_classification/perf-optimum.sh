#!/bin/bash

# Supermiro SPM
# https://docs.habana.ai/en/latest/Intel_DevCloud_Quick_Start/Intel_DevCloud_Quick_Start.html
# Jing Kang 9/2024

SRC=`readlink -f "${BASH_SOURCE[0]}" 2>/dev/null||echo $0`
CUR=`dirname "${SRC}"`
PAR=`dirname "${CUR}"`

source $PAR/common-modvars.sh

banner=(''																					
   $RED"  _            _          _               _  __ _           _   _              \n"$NCL
   $RED" | |          | |        | |             (_)/ _(_)         | | (_)             \n"$NCL
   $GRN" | |_ _____  _| |_    ___| | __ _ ___ ___ _| |_ _  ___ __ _| |_ _  ___  _ __   \n"$NCL
   $GRN" | __/ _ \ \/ / __|  / __| |/ _' / __/ __| |  _| |/ __/ _' | __| |/ _ \| '_ \  \n"$NCL
   $GRN" | ||  __/>  <| |_  | (__| | (_| \__ \__ \ | | | | (_| (_| | |_| | (_) | | | | \n"$NCL
   $BLU"  \__\___/_/\_\\__|   \___|_|\__,_|___/___/_|_| |_|\___\__,_|\__|_|\___/|_| |_| \n"$NCL
   $BLU"                                                                               \n"$NCL
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

function single_card_bert_finetune(){
	cd ${PAR}/optimum-habana/examples/text-classification

	TRAINL=$OUTPUT/train-1-card.log

	SECONDS=0
	python run_glue.py \
	--model_name_or_path bert-large-uncased-whole-word-masking \
	--gaudi_config_name Habana/bert-large-uncased-whole-word-masking  \
	--task_name $TASK_NAME \
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
	--overwrite_output_dir 2>&1 | tee -a $TRAINL

	rm -rf .graph_dumps 2>/dev/null
	TRAIN_TIME1=${SECONDS}
	cd -

	print_result "single"
}

function multi_8c_mpi_bert_finetune(){
	# 
	# cd /sox/Gaudi-Model-Eval/optimum-habana/examples/text-classification
	#
	cd ${PAR}/optimum-habana/examples/text-classification
	
	TRAINL=$OUTPUT/train-8c-mpi.log

	SECONDS=0
	python ../gaudi_spawn.py --world_size 8 --use_mpi run_glue.py  \
	--model_name_or_path bert-large-uncased-whole-word-masking  \
	--gaudi_config_name Habana/bert-large-uncased-whole-word-masking  \
	--task_name $TASK_NAME \
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
	--overwrite_output_dir 2>&1 | tee -a $TRAINL

	rm -rf .graph_dumps hl-smi_log.txt 2>/dev/null
	TRAIN_TIME2=${SECONDS}
	cd -

	echo -e "\n  exec 8-card mpi fine-tuning"
	print_result "mpi"
}

function multi_8c_deepspeed_finetune(){
	cd ${PAR}/optimum-habana/examples/text-classification

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

	if [[ $1 == "LlamaGuard-7b" ]]; then
		model_name="meta-llama/LlamaGuard-7b"
		gaudi_config="Habana/llama
		"
		TRAINL=$OUTPUT/train-8-llma.log
	elif [[ $1 == "bert-large-uncased" ]]; then
		model_name="bert-large-uncased-whole-word-masking"
		gaudi_config="Habana/bert-large-uncased-whole-word-masking"
		TRAINL=$OUTPUT/train-8-bert.log
	fi

	SECONDS=0
	python ../gaudi_spawn.py --world_size 8 --use_deepspeed run_glue.py \
	--model_name_or_path $model_name   \
	--gaudi_config_name  $gaudi_config \
	--task_name $TASK_NAME \
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
	--add_pad_token true        \
	--overwrite_output_dir 2>&1 | tee -a $TRAINL

	rm -rf .graph_dumps hl-smi_log.txt 2>/dev/null
	cd -

	echo -e "\n  exec 8-card $1 deepspeed fine-tuning\n"
	
	if [[ $1 == "LlamaGuard-7b" ]]; then
		print_result "llma"
		TRAIN_TIME4=${SECONDS}
	elif [[ $1 == "bert-large-uncased" ]]; then
		print_result "bert"
		TRAIN_TIME3=${SECONDS}
	fi
}

function print_result(){
	cd $PWD 2>/dev/null

	cardn=8
	if [[ $1 == "single" ]]; then
		testresult="ft-1-card.txt"
		TRAINL=$OUTPUT/train-1-card.log
		threshold=330
		cardn=1
	elif [[ $1 == "mpi" ]]; then
		testresult="ft-8c-mpi.txt"
		TRAINL=$OUTPUT/train-8c-mpi.log
		threshold=1040
	elif [[ $1 == "bert" ]]; then
		testresult="ft-8-bert.txt"
		TRAINL=$OUTPUT/train-8-bert.log
		threshold=1000
	elif [[ $1 == "llma" ]]; then
		testresult="ft-8-llma.txt"
		TRAINL=$OUTPUT/train-8-llma.log
		threshold=100
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

	if   [[ $1 == "single" ]]; then
		train_rt1=${tc[1]}
	elif [[ $1 == "mpi" ]]; then
		train_rt2=${tc[1]}
	elif [[ $1 == "bert" ]]; then
		train_rt3=${tc[1]}
	elif [[ $1 == "llma" ]]; then
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
	scp -r -P 7022 -i ./id_rsa -o PasswordAuthentication=no -o StrictHostKeyChecking=no ${fff} spm@129.146.47.229:/home/spm/perf_optimum-text-classification/ &>/dev/null

	rm -rf  ./.graph_dumps _exp id_ed25519 id_rsa &>/dev/null
}

# ----- start test

ss_time=$(date +%s)

PWD=`pwd`

OUTPUT=`dirname $PWD`/optimum-perf-text-classification/perf_optimum
FINALT=0

parse_args "$@"
prerun-check

rm -rf   $OUTPUT 2>/dev/null
mkdir -p $OUTPUT 2>/dev/null
TRAINL=$OUTPUT/train-1-card.log
TRAIN_LOGF=$TRAINL
touch $TRAINL

TASK_NAME=${GLUE[0]}

update_optimum

start_sys_mon

printf "${banner[*]}\n"

echo -e "  exec single_card_training\n"
single_card_bert_finetune

echo -e "\n  exec 8-card ${YLW}bert mpi${NCL} training\n"
multi_8c_mpi_bert_finetune

echo -e "\n  exec 8-card ${YLW}deepspeed bert-large-uncased${NCL} training\n"
multi_8c_deepspeed_finetune "bert-large-uncased"

echo -e "\n  exec 8-card ${YLW}deepspeed LlamaGuard${NCL} training\n"
multi_8c_deepspeed_finetune "LlamaGuard-7b"

stop_sys_mon

# print history result
echo -e "\n  result: ${YLW}8-card bert deepspeed${NCL} training\n"
print_result "bert"    "print_only" 

echo -e "\n  result: ${YLW}8-card bert mpi ${NCL} training\n"
print_result "mpi"    "print_only" 

echo -e "\n  result: ${YLW}single_card${NCL} training\n"
print_result "single" "print_only" 

echo

# log system os info
get_test_envn_data "optimum" "1.13.2" "text-classification"

# -------------

rec_time=$(date +%s)
rec_YYYY=$(date '+%Y-%m-%d %H:%M:%S' -d @$rec_time)
echo -e "fine tuning ${YLW}$TASK_NAME${NCL}"
echo "model testing time           1-card           bert-mpi-8     bert-deepspeed-8     llamaGuard-deepd"
printf "%15s ${CYA}%15s %20s %20s %20s${NCL}\n" "${rec_YYYY}" $TRAIN_TIME1 $TRAIN_TIME2 $TRAIN_TIME3 $TRAIN_TIME4 | tee -a test_time.txt
echo
tail -n 5 test_time.txt

echo
echo "train_runtime                1-card           bert-mpi-8     bert-deepspeed-8     llamaGuard-deepd"
printf "%15s ${CYA}%15s %20s %20s %20s${NCL}\n" "${rec_YYYY}" $train_rt1 $train_rt2 $train_rt3 $train_rt4 | tee -a runtimeg_${TASK_NAME}
echo
tail -n 5 runtimeg_${TASK_NAME}
echo

# max power reading
#hpw=$(sort $OUTPUT/_powerr.log | sort -n | tail -n 1)
#echo -e "${YLW}Maximum Power: ${hpw} watts${NCL}" | tee -a $TRAINL

# print top 30 stat info from hl-smi
print_topnn_hl_smi 5

#print_energy_usage

#save_service_procs

if [[ $FINALT == 0 ]] ; then
	echo -e "fine-tune ${YLW}GLUE ${TASK_NAME}${NCL}: ${GRN}PASS${NCL}" | tee -a $TRAIN_LOGF
else
	echo -e "fine-tune ${YLW}GLUE ${TASK_NAME}${NCL}: ${RED}FAIL${NCL}" | tee -a $TRAIN_LOGF
fi

scp_results_remote

echo
echo -e "${BLU}Test Complete: ${elapsed} sec${NCL}\n" | tee -a completet.txt
