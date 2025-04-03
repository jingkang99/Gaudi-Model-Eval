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

export PATH=/opt/habanalabs/openmpi-4.1.5/bin:$PATH
export PT_HPU_LAZY_MODE=1

export WANDB_DISABLED=true
export HF_HOME=/sox/huggingface

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
alias cls="echo '' > /var/log/syslog; echo '' > /var/log/kern.log; rm -rf /var/log/habana_logs/*"

alias gov='cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor | uniq -c'
alias hkill='hl-smi | grep -A 9 Type | grep == -A 8 | grep -v == | grep -v  N/A | awk '\''{print $3}'\'' | xargs kill -9 2>/dev/null'

MLPERFROOT=/sox/Gaudi-Model-Eval

alias acd='cd /sox/habana-intel/Model-References/MLPERF3.1/Training/benchmarks'
alias bcd="cd $MLPERFROOT/bert-perf-result/$(  ls -tr $MLPERFROOT/bert-perf-result   | tail -n 1)"
alias rcd="cd $MLPERFROOT/resnet-perf-result/$(ls -tr $MLPERFROOT/resnet-perf-result | tail -n 1)"

alias spi='hl-smi -q | grep SPI'
alias oam='hl-smi -L | grep "CPLD Version" -B 15 | grep -P "accel|Serial|SPI|CPLD"'
alias cpld='hl-smi -q | grep "CPLD Ver"'
alias pcnt='hl-smi -Q bus_id -f csv,noheader | xargs -I % hl-smi -i % -n link | grep UP | wc -l'
alias hccl='HCCL_COMM_ID=127.0.0.1:5555 python3 run_hccl_demo.py --nranks 8 --node_id 0 --size 32m --test all_reduce --loop 1000 --ranks_per_node 8 | tee -a _hccl.log'
alias oopt="cat /sys/class/accel/accel*/device/status"
alias apth='apt list --installed | grep haba'
alias erom='hl-smi --fw-version | grep erom -A 1 | grep  gaudi'
alias SPI='hl-fw-loader -s | grep Sending -A 6 | grep -P "SPI|Sending"'
alias gd3='cd /var/log/habana_logs/qual/;tail -n 1 *.log | grep -v == | grep .'

RED='\033[0;31m'
YLW='\033[0;33m'
BLU='\033[0;34m'
BCY='\033[1;36m'
CYA='\033[0;36m'
NCL='\033[0m'

M_SIZE=$(echo $(grep MemTotal /proc/meminfo | awk '{print $2}')/1024/1014 + 1| bc)
CPU_TP=$(grep "model name" /proc/cpuinfo| head -n 1 |awk -F':' '{print $2}' | xargs)
CPU_CT=$(grep processor /proc/cpuinfo|wc -l)

function lsg(){
        find . -mindepth 2 -maxdepth 2 -type d -ls | grep $1
}
function dush(){
    du -h --max-depth=1 $1
}

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

function pip-show-version() {
    curl -s  https://pypi.org/pypi/${1}/json | jq  -r '.releases | keys | .[]' | sort -V
}

function pse() {
	pip list | grep $1
}

function pii() {
	pip install $1
}

function piu() {
	pip install --upgrade $@
}

function pir() {
	REQ=${1:-requirements.txt}
	awk -F"==" '{print $1}' $REQ | xargs -I{} pip install {}
}

mkdir -p /root/.postgresql 2>/dev/null
cp tool/root.crt /root/.postgresql/root.crt

function psnic(){
	mapfile -t aoc < <( lspci | grep Eth | awk '{print $1}' );
	for nic in "${aoc[@]}" ; do
		iface=$(dmesg | grep  $nic | grep renamed | awk '{print $5}' | awk -F':' '{print $1}')
		ifconfig $iface up
		upord=$(ethtool $iface | grep Link | awk -F':' '{print $2}')
		echo -e "$nic \t $iface \t $upord"
	done
}
