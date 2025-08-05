# jkang 7/4/25
# GB200 NVL72 benchmark, DA-12276-001_v13.pdf, 6/25

export BCHM=/root/gb200/benchmark
export PATH=${BCHM}:/usr/local/cuda-12.8/bin${PATH:+:${PATH}}

export GEMM_DIR=${BCHM}/gemm_memread
export LD_LIBRARY_PATH=/usr/local/cuda-12.8/lib64:${GEMM_DIR}/build/lib:${LD_LIBRARY_PATH}

cd ${BCHM}

rm -rf _smi_L.log _smi_q.log _streamv_* _cubl* _n* _duty*

function stream_v(){
	gpu=$1
	time stream_vectorized_double_test -d${gpu} -n1073741824 -r1 | tee _streamv_${gpu}.log &
	sleep 15
	nvtop -s > _streamv_${gpu}.top
	sleep 150
}

# --------- 

SECONDS=0

nvidia-smi -L  > _smi_L.log
nvidia-smi -q  > _smi_q.log
nvcc --version > _nvccv.log

lsof -n -w /dev/nvidia* > _nvdev.log
cat /proc/driver/nvidia/version > _nvver.log

echo "  -->  STREAM benchmark for measuring memory bandwidth"
stream_v "0"
stream_v "1"
stream_v "2"
stream_v "3"

echo "  -->  Peak TOPS benchmark for FP4 FP6 FP8 INT8 FP16 BF16 TF32 FP32 FP64"
bash run_blackwell.sh | tee ../_peak_tops.log
cd -

echo "  -->  Basic Linear Algebra, General Matrix Multiplication: FP4 FP8 FP16 BF16 TF32 FP32 FP64" 
cublasMatmulBench -P=nvoohso       -m=9728 -n=16384 -k=8192  -ta=1 -tb=0 -A=1 -B=0 -T=1000 -W=10000 -p=t -sf_p=u | tee _cubla_fp4.log

cublasMatmulBench -P=qqssq         -m=9728 -n=2048  -k=32768 -ta=1 -tb=0 -A=1 -B=0 -T=1000 -W=10000 -p=t         | tee _cubla_fp8.log

cublasMatmulBench -P=hsh           -m=8192 -n=9728  -k=16384 -ta=0 -tb=1 -A=1 -B=0 -T=1000 -W=10000 -p=t         | tee _cubl_fp16.log

cublasMatmulBench -P=tst           -m=8192 -n=9728  -k=16384 -ta=0 -tb=1 -A=1 -B=0 -T=1000 -W=10000 -p=t         | tee _cubl_bf16.log

cublasMatmulBench -P=sss_fast_tf32 -m=8192 -n=9728  -k=16384 -ta=1 -tb=0 -A=1 -B=0 -T=1000 -W=10000 -p=t         | tee _cubl_tf32.log

cublasMatmulBench -P=sss           -m=8192 -n=9728  -k=16384 -ta=0 -tb=1 -A=1 -B=0 -T=1000 -W=10000 -p=t         | tee _cubl_fp32.log

cublasMatmulBench -P=ddd           -m=8192 -n=9728  -k=16384 -ta=0 -tb=1 -A=1 -B=0 -T=1000 -W=10000 -p=t         | tee _cubl_fp64.log

grep -i Gflops  _cubl* | awk '{print $10}'

echo "  -->  bandwidth measurement, deliver up to 900 GB/s total"
time nvbandwidth | tee _nvband_wd.log
grep "SUM " _nvband_wd.log

echo "  -->  Collective Communication, NCCL "
all_reduce_perf -b 8 -e 32G -f 2 -t 4 | tee _n_all_rdc.log

alltoall_perf   -b 8 -e 32G -f 2 -t 4 | tee _n_all2all.log

all_gather_perf -b 8 -e 32G -f 2 -t 4 | tee _n_all_gth.log

broadcast_perf  -b 8 -e 32G -f 2 -t 4 | tee _n_broadcs.log

gather_perf     -b 8 -e 32G -f 2 -t 4 | tee _n_gatherp.log

hypercube_perf  -b 8 -e 32G -f 2 -t 4 | tee _n_hypercb.log

reduce_perf     -b 8 -e 32G -f 2 -t 4 | tee _n_reducep.log

reduce_scatter  -b 8 -e 32G -f 2 -t 4 | tee _n_reduces.log

scatter_perf    -b 8 -e 32G -f 2 -t 4 | tee _n_scatter.log

sendrecv_perf   -b 8 -e 32G -f 2 -t 4 | tee _n_sendrcv.log

grep Avg _n_*
echo

echo "  -->  GEMM MemRead measuring the GEMM perf when duty cycle is modulated to 65%"

time python3 ${GEMM_DIR}/scripts/duty_cycle_controller_v2.py --dtype fp4  --gpus 4 --tolerance 1 | tee _dutyc_fp4.log
time python3 ${GEMM_DIR}/scripts/duty_cycle_controller_v2.py --dtype fp8  --gpus 4 --tolerance 1 | tee _dutyc_fp8.log
time python3 ${GEMM_DIR}/scripts/duty_cycle_controller_v2.py --dtype fp16 --gpus 4 --tolerance 1 | tee _duty_fp16.log
time python3 ${GEMM_DIR}/scripts/duty_cycle_controller_v2.py --dtype bf16 --gpus 4 --tolerance 1 | tee _duty_bf16.log

python3 ${GEMM_DIR}/scripts/run_bench.py --dtype fp4 --gpu 0 --duty_cycle 65 | tee _run_bench_fp4.log
python3 ${GEMM_DIR}/scripts/run_bench.py --dtype fp4 --gpu 1 --duty_cycle 65 | tee -a _run_bench_fp4.log
python3 ${GEMM_DIR}/scripts/run_bench.py --dtype fp4 --gpu 2 --duty_cycle 65 | tee -a _run_bench_fp4.log
python3 ${GEMM_DIR}/scripts/run_bench.py --dtype fp4 --gpu 3 --duty_cycle 65 | tee -a _run_bench_fp4.log

echo -e "\ngpu benchmark done in ${SECONDS}\n"

