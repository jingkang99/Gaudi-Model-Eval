RTP[1]=http://10.43.251.42/logs/Supermicro/2025/March/INTEL-IDC-0001/24/R-BURN/S930999X4C26519/905A080D26C4/
RTP[2]=http://10.43.251.42/logs/Supermicro/2025/March/INTEL-IDC-0001/24/R-BURN/S930999X4C26517/905A080D27B4/
RTP[3]=http://10.43.251.42/logs/Supermicro/2025/March/INTEL-IDC-0002/21/R-BURN/S930999X4C26543/905A080D2700/

function chk_gd3_rburn(){
	DBG=yam_debug-information/
	QU[1]=habana_gpu-connectivity-nic-allgather.log
	QU[2]=habana_gpu-connectivity-nic-pairs.log
	QU[3]=habana_gpu-hbm-dma-stress-test.log
	QU[4]=habana_gpu-hbm-tpc-stress-test.log
	QU[5]=habana_gpu-pci-bandwidth-serial-full.log
	QU[6]=habana_gpu-stress-edp-test.log
	QU[7]=habana_gpu-stress-functional2-test.log
	QU[8]=habana_gpu-stress-pci-bandwidth-gen.log
	QU[9]=habana_gpu-stress-power-stress.log
	rm -rf habana_gpu*.log
	for (( i=1; i < 10; i++ )); do
		echo ${1}${DBG}${QU[$i]}
		wget -q ${1}${DBG}${QU[$i]}
	done
	tail -n 1 *.log  | grep -v == | grep .
	sleep 1
}

chk_gd3_rburn ${RTP[1]}

rm -rf habana_gpu-*.log