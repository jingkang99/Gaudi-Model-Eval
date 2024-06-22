# this repo is for validating Gaudi GPU's basic training and inference capabilities

#dpkg --purge linux-modules-extra-5.15.0-94-generic
#apt  autoremove --purge

# ro
export HF_TOKEN=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

# rw
export HF_TOKEN=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
export HF_HOME=/sox/huggingface

export DATASET=/sox/data-ml
export SCIKIT_LEARN_DATA=$DATASET
export PYTHON_LLM_VEN=/opt/python-llm
export PYTHONPATH=/usr/lib/habanalabs:/sox/habana-intel/Model-References
export TZ='America/Los_Angeles'

export MLPERF_ROOT=/sox/mlperf
export SCRATCH_DIR=$MLPERF_ROOT/scratch
export DATASETS_DIR=$DATASET
export MLPERF_DIR=/sox/habana-intel/Model-References/MLPERF3.1/Training
export PYTORCH_BERT_DATA=$DATASET/ptbert-data
export BERT_IMPLEMENTATIONS=/sox/habana-intel/Model-References/MLPERF3.1/Training/benchmarks/bert/implementations

export CONTAINER_NAME=mlperf3_1
export DOCKER_IMAGE=vault.habana.ai/gaudi-docker/1.16.0/ubuntu22.04/habanalabs/pytorch-installer-2.2.2:latest

export PATH=/opt/habanalabs/openmpi-4.1.5/bin:$PATH
export PT_HPU_LAZY_MODE=1

# pytorch env, installed with required modules
[ ! -d "$PYTHON_LLM_VEN" ] && ln -s /sox/python-llm /opt/python-llm

alias ipa="ip a | grep inet | grep metric"
alias ipp="ifconfig | grep 'inet ' | grep -v 127.0 | awk '{print \$2}'"
alias nic="ip a | grep MULTICAST"
alias nii="ip a | grep MULTICAST | awk -F: '{print \$2}'"
alias gg='git log --all --decorate --oneline --graph'
alias gg='git log --all --decorate --oneline --graph'
alias gu='git pull'
alias ga='ls -l | grep drwxr | awk "{print \$9}" | xargs -I{} grep git {}/.git/config 2>/dev/null'
alias gd="for fd in \$( ls -l | grep drwxr | awk '{print \$9}' ) ; do cd \$fd; pwd; echo; git pull; cd - ; done 2>/dev/null"
alias gh='git checkout HEAD'
alias gr='grep url .git/config'
alias gq='git show | grep Date:'
alias gb='for fd in $( ls -l | grep drwxr | awk '\''{print $9}'\'' ) ; do cd $fd; pwd; git log -1 --format="%at" | xargs -I{} date -d @{} +%Y/%m/%d-%H:%M:%S; cd .. ; echo ; done 2>/dev/null'
alias gw='git clone --depth=1'
alias gck="/opt/habanalabs/qual/gaudi2/bin/manage_network_ifs.sh --status"
alias gup="/opt/habanalabs/qual/gaudi2/bin/manage_network_ifs.sh --up"
alias pws='ipmitool sdr | grep PW'
alias hl-='hl-smi -Q timestamp,index,serial,bus_id,memory.used,temperature.aip,utilization.aip,power.draw -f csv,noheader -l 10'
alias apy='source $PYTHON_LLM_VEN/bin/activate'
alias jns='jupyter notebook --ip 0.0.0.0 --port 8888 --allow-root'

alias upp='nmap -sn 172.24.189.11/27| grep 172'

RED='\033[0;31m'
YLW='\033[0;33m'
BLU='\033[0;34m'
BCY='\033[1;36m'
CYA='\033[0;36m'
NCL='\033[0m'

function lsg(){
        find . -mindepth 2 -maxdepth 2 -type d -ls | grep $1
}
function dush(){
    du -h --max-depth=1 $1
}

M_SIZE=$(echo $(grep MemTotal /proc/meminfo | awk '{print $2}')/1024/1014 + 1| bc)
CPU_TP=$(grep "model name" /proc/cpuinfo| head -n 1 |awk -F':' '{print $2}' | xargs)
CPU_CT=$(grep processor /proc/cpuinfo|wc -l)

function sys_info(){
        echo $M_SIZE'GB' $CPU_CT'Core' $CPU_TP | toilet -f term -F border --gay
        df -h | grep /dev/ | grep -v snap | grep -v tmpfs | sort | toilet -f term -F border --gay
}

function print_prd_banner() {
    lspci -d :1020: -nn | grep -P '\S+' > /dev/null
    if [ $? -eq 0 ]; then
        echo "    Supermicro Gaudi    " | toilet -f term -F border --gay
        sys_info

	hlsim=$(hl-smi -v|head -n 1)
        echo $hlsim | toilet -f term -F border --gay

	ifconfig | grep 'inet ' | grep -v -P '0.1\b' | awk '{print $2}' | toilet -f term -F border --gay

        return 0
    fi
    sys_info
}

