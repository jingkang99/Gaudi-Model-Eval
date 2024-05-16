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
alias hl-='hl-smi -Q temperature.aip -f csv,noheader'
alias apy='source $PYTHON_LLM_VEN/bin/activate'
alias jns='jupyter notebook --ip 0.0.0.0 --port 8888 --allow-root'


# reference nodets
#	https://huggingface.co/blog/pretraining-bert
