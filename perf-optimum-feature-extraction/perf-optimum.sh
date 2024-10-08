#!/bin/bash

# Supermiro SPM
# https://docs.habana.ai/en/latest/Intel_DevCloud_Quick_Start/Intel_DevCloud_Quick_Start.html
# Jing Kang 9/2024

SRC=`readlink -f "${BASH_SOURCE[0]}" 2>/dev/null||echo $0`
CUR=`dirname "${SRC}"`
PAR=`dirname "${CUR}"`

source $PAR/common-modvars.sh

banner=('' 
   $RED"   _            _      __           _                              _                  _   _             \n"$NCL
   $RED"  | |          | |    / _|         | |                            | |                | | (_)            \n"$NCL
   $GRN"  | |_ _____  _| |_  | |_ ___  __ _| |_ _   _ _ __ ___    _____  _| |_ _ __ __ _  ___| |_ _  ___  _ __  \n"$NCL
   $GRN"  | __/ _ \ \/ / __| |  _/ _ \/ _\` | __| | | | '__/ _ \  / _ \ \/ / __| '__/ _\` |/ __| __| |/ _ \| '_ \ \n"$NCL
   $GRN"  | ||  __/>  <| |_  | ||  __/ (_| | |_| |_| | | |  __/ |  __/>  <| |_| | | (_| | (__| |_| | (_) | | | |\n"$NCL
   $BLU"   \__\___/_/\_\\__|  |_| \___|\__,_|\__|\__,_|_|  \___|  \___/_/\_\\__|__|  \__,_|\___|\__|_|\___/|_| |_|\n"$NCL
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

function print_result(){
	local model="${1:-thenlper/gte-small}"
	local mname=`echo $model | awk -F'/' '{print $2}'| tr '[:upper:]' '[:lower:]'`

	cd $PWD 2>/dev/null

	cardn=8
	if [[ $model == "single" ]]; then
		testresult="ft-1-card.txt"
		TRAINL=$OUTPUT/train-1-card.log
		threshold=330
		cardn=1
	elif [[ $model =~ "Llama-2-7b-hf" ]]; then
		testresult="bm-$mname.txt"
		threshold=29000
	elif [[ $model =~ "thenlper/gte" ]]; then
		testresult="bm-$mname.txt"
		threshold=85
	fi

	TRAINL=$OUTPUT/test-${mname}.log

	# score 
	tt=($(grep "Scores for" $TRAINL | awk -F':' '{print $4 }' | sed 's#\[##g' | sed 's#\]##g' | sed 's#,##g'))

	rec_time=$(date +%s)
	rec_YYYY=$(date '+%Y-%m-%d %H:%M:%S' -d @$rec_time)

	printf " %20s  %25s %25s %25s %25s\n" " " "score1" "score2" "score3" "score4"
	if [[ $2 == "print_only" ]]; then
		printf " %20s  ${CYA}%25s %25s %25s %25s${NCL}\n" "${rec_YYYY}" ${tt[0]} ${tt[1]} ${tt[2]} ${tt[3]}
	else
		printf " %20s  ${CYA}%25s %25s %25s %25s${NCL}\n" "${rec_YYYY}" ${tt[0]} ${tt[1]} ${tt[2]} ${tt[3]} | tee -a $testresult
		echo
		printf " %20s  ${CYA}%25s %25s %25s %25s${NCL}\n"  "${rec_YYYY}" $mname $TRAIN_TIME1 ${tt[1]} 		| tee -a test_time.txt
	fi

	echo -e "\n  ${YLW}history result${NCL}"
	tail -n 5 $testresult

	echo
	r1=$((`echo "${tt[1]} > $threshold" | bc`))
	if [[ r1 -eq 1 ]]; then
		echo -e "feature-extraction $mname score benchmark: ${GRN}PASS${NCL}" | tee -a $TRAINL
	else
		echo -e "feature-extraction $mname score benchmark: ${RED}FAIL${NCL}" | tee -a $TRAINL
		FINALT=1
	fi
}

function benchmark_feature-extraction(){
	local model="${1:-thenlper/gte-small}"
	local mname=`echo $model | awk -F'/' '{print $2}'| tr '[:upper:]' '[:lower:]'`

	cd ${PAR}/optimum-habana/examples/text-feature-extraction
	TRAINL=$OUTPUT/test-${mname}.log

	SECONDS=0

	python run_feature_extraction.py \
		--model_name_or_path $model  \
		--source_sentence "What is natural language processing (NLP), and what are some common NLP techniques?" \
		--input_texts \
			"There are many different variants of apples created every year." \
			"The process of breaking down a text into smaller units, such as words or subwords (tokens). Tokenization is the first step in most NLP tasks" \
			"Alexander Hamilton is one of the founding fathers of the United States." \
			"Identifying and classifying named entities, such as names of people, organizations, locations, and dates, in a text." \
		--use_hpu_graphs \
		--bf16 2>&1 | tee $TRAINL

	rm -rf .graph_dumps hl-smi_log.txt 2>/dev/null
	TRAIN_TIME1=${SECONDS}
	cd -

	echo -e "\n  benchmark on $mname"
	print_result $model
}

function scp_results_remote(){
	# rename the result folder
	ee_time=$(date +%s)
	elapsed=$((`echo "$ee_time - $ss_time" | bc`))

	ipp=$(ifconfig | grep 'inet ' | grep -v -P '27.0|172.17' | awk '{print $2}')
	fff=$OUTPUT-${ipp}-${ee_time}-${elapsed}-${tt[1]}

	# 119G after testing
	rm -rf $OUTPUT/output

	mv $OUTPUT $fff

	save_sys_cert
	scp -r -P 7022 -i ./id_rsa -o PasswordAuthentication=no -o StrictHostKeyChecking=no ${fff} spm@129.146.47.229:/home/spm/perf_optimum-feature-extraction/ &>/dev/null

	rm -rf  ./.graph_dumps _exp id_ed25519 id_rsa &>/dev/null
}

# ----- start test
ss_time=$(date +%s)

PWD=`pwd`

OUTPUT=`dirname $PWD`/optimum-perf-feature-extraction/perf_optimum
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

model_1="thenlper/gte-base"
benchmark_feature-extraction $model_1

echo -e '\n------------------------------\n'
model_2="thenlper/gte-small"
benchmark_feature-extraction $model_2

echo -e '\n------------------------------\n'
model_3="thenlper/gte-large"
benchmark_feature-extraction $model_3

stop_sys_mon

echo

echo -e '\n------------------------------\n'

print_result $model_2 "print_only" 

echo -e '\n------------------------------\n'

print_result $model_1 "print_only" 

# log system os info
get_test_envn_data "optimum" "1.13.2" "feature-extraction"

# -------------
echo

rec_time=$(date +%s)
rec_YYYY=$(date '+%Y-%m-%d %H:%M:%S' -d @$rec_time)

echo "  testing time                          name                     exec_time         throughput"
tail -n 6 test_time.txt

# max power reading
#hpw=$(sort $OUTPUT/_powerr.log | sort -n | tail -n 1)
#echo -e "${YLW}Maximum Power: ${hpw} watts${NCL}" | tee -a $TRAINL

# print top 30 stat info from hl-smi
print_topnn_hl_smi 5

#print_energy_usage

#save_service_procs

scp_results_remote

echo
echo -e "${BLU}Test Complete: ${elapsed} sec${NCL}\n"
