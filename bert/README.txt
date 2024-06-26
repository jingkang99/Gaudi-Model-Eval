--- mlperf 3.1 ---

101GB test suite

-rw-r--r-- 1 spm spm          106 Jun 21 23:29 baseline-1-md5.txt
-rw-r--r-- 1 spm spm 107376680960 Jun 21 23:19 bert-mlperf-31.tar
-rw-r--r-- 1 spm spm    827417506 Jun 21 23:21 python-gd-1.16.tgz

scp spm@172.24.189.10:/home/spm/mlperf31-bert/baseline-1-md5.txt .

scp spm@172.24.189.10:/home/spm/mlperf31-bert/python-gd-1.16.tgz .

scp spm@172.24.189.10:/home/spm/mlperf31-bert/bert-mlperf-31.tar .

# prepare python environment
cd /opt
tar xvzf python-gd-1.16.tgz

export PYTHON_LLM_VEN=/opt/python-llm
alias apy='source $PYTHON_LLM_VEN/bin/activate'
apy

# prepare bert test suite
tar xvzf bert-mlperf-31.tar
cd bert
./perf-test-mlperf-3.1.sh

--- notes ---

Just common used commands and checkpoints for BERT Training, which merged to the main script.

cd /sox/habana-intel/Model-References/MLPERF3.1/Training/benchmarks/bert/implementations/HLS-Gaudi2-PT

. /sox/Gaudi-Model-Eval/env-llm-prep.sh 

export OUTPUT=/fox/llm-perf-result/bert-train-eval

SECONDS=0; \
time ./launch_bert_pytorch-spm.sh -p 22 --data-dir $PYTORCH_BERT_DATA --output-dir $OUTPUT; \
echo $SECONDS

#    ./launch_bert_pytorch-spm.sh -p 22 --data-dir $PYTORCH_BERT_DATA --output-dir $OUTPUT --enable-evaluation false

cd $OUTPUT

hl- | tee   hl-smi.txt
mpstat 10 | tee mpstat.txt

ps -ef | grep python3 >> python.txt
ps -ef | grep mpirun  >> mpirun.txt

grep 'run_start\|run_stop' train.log | grep worker0 | awk '{print $5}' | tr -d ',' | paste -sd " " - | awk '{print ($2 - $1) / 1000 / 60}'

for nn in {0..7} ; do grep 'run_start\|run_stop' train.log | grep worker${nn} | awk '{print $5}' | tr -d ',' | paste -sd " " - | awk '{print ($2 - $1) / 1000 / 60}' ; done

for nn in {0..7} ; do grep 'run_start\|run_stop' train.log | grep worker${nn} | awk '{print $5}' | tr -d ',' | paste -sd " " - | awk '{print ($2 - $1) / 1000 / 60}' ; done | awk '{s+=$1}END{print s/NR}'

grep "Training Iteration: 6700"  train.log 
grep e2e_train_time		 train.log 

cd /fox/llm-perf-result/bert-train-eval/results/checkpoints; for fd in $( ls *.txt ) ; do grep 'run_start\|run_stop' $fd | awk '{print $5}' | tr -d ',' | paste -sd " " - | awk '{print ($2 - $1) / 1000 / 60}' ; done | awk '{s+=$1}END{print s/NR}';cd -

ipmitool dcmi power reading
ipmitool sdr

find . -name *.pt -type f -delete

cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
# schedutil
# echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor

pip list | grep -P 'habana|tensor|torch' > modu.txt; apt list --installed | grep habana >> modu.txt; lsmod | grep habana >> modu.txt


lrwxrwxrwx 1 root root   44 Jun 12 10:48 eval_varlength -> /sox/data-ml/ptbert-data/hdf5/eval_varlength/
lrwxrwxrwx 1 root root   51 Jun 12 10:46 model.ckpt-28252.pt -> /sox/data-ml/ptbert-data/phase1/model.ckpt-28252.pt
lrwxrwxrwx 1 root root   31 Jun 12 16:09 packed -> /sox/data-ml/ptbert-data/packed/

