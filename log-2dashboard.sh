#!/bin/bash

# log to sql for dashboard
# Jing Kang 7/2024 aves hdyN-_VekyaLdwxIVJbjRg

if [ -z "${OUTPUT}" ]; then
	OUTPUT=.
fi

M0=${OUTPUT}/_module.log
declare -A pkg
grep '\-------' -B 36 $M0 | grep -v '\-------' > 1
while read -r key value; do
    pkg["$key"]="$value"
done < 1
rm -rf 1

declare -A osi
grep '\-------' -A 44 $M0 | grep -v '\-------' | grep . > 1
while IFS=': ' read -r key value; do
    osi["$key"]="$value"
done < 1
#echo ${osi[machid]}

# ------ oam info
declare -A oam
awk '{print $7 $8 $9}' ${OUTPUT}/_hl-smi.log | sed 's/,/ /g' | sort | uniq > 1
while read -r seq srl bus ; do
    oam["$seq,0"]=$srl
    oam["$seq,1"]=$bus
done < 1
#echo ${oam[@]}

#remove color control chars in log
sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]//g" ${OUTPUT}/train.log > 1

# --- training result
time2trn=$(grep -P "^Time To Train: " 1 | awk '{print $4}')
maxpower=$(grep -P "^Maximum Power: " 1 | awk '{print $3}')
avgtstep=$(grep -P "^  average_training_time_step: " 1 | awk '{print $2}')
e2e_time=$(grep -P "^  e2e_train_time " 1 | awk '{print $3}')
trainseq=$(grep -P "^  training_sequences" 1 | awk '{print $2}')
finaloss=$(grep -P "^  final_loss" 1 | awk '{print $3}')
rawttime=$(grep -P "^  raw_train_time" 1 | awk '{print $3}')
evaltime=$(grep -P "^  model eval time" 1 | awk '{print $4}')
energyco=$(grep -P "^  pdu energy used" 1 | awk '{print $4}')

pwrsread=
pwrfread=
read -r -d '' pwrsread pwrfread <<< "$(grep -P '^  pdu energy used' 1 | awk '{print $7, $8}')"

diff_srv=$(grep -P "^services diff" 1 | awk '{print $3}')
diff_pro=$(grep -P "^process  diff" 1 | awk '{print $3}')
avgttime=$(grep -P "^avgtrain time" 1 | awk '{print $3}')
ttm_rslt=$(grep -P "^time to train" 1 | awk '{print $4}')
testtime=$(grep -P "^Test Complete" 1 | awk '{print $3}')

rm -rf 1

# INSERT INTO table_name (column1, column2, column3, ...)
# VALUES (value1, value2, value3, ...);

kk="bmc_mac, test_start, test_end, elapse_time, test_date, \
bmc_ipv4, bmc_ipv6, bmc_fware_version, bmc_fware_date, \
bios_version, bios_date, bios_cpld, gpu_cpld, mb_serial, mb_mdate, mb_model, \
cpu_model, cpu_cores, pcie, memory, \
os_idate, machid, scaling_governor, huge_page, os_kernel, host_mac, host_ip, \
host_nic, root_partition_size, hard_drive, host_uptime_since, \
habanalabs_firmware, optimum_habana, torch, pytorch_lightning, \
lightning_habana, tensorflow_cpu, transformers, \
habanalabs, habanalabs_ib, habanalabs_cn, habanalabs_en, ib_uverbs, \
oam0_serial, oam0_pci, \
oam1_serial, oam1_pci, \
oam2_serial, oam2_pci, \
oam3_serial, oam3_pci, \
oam4_serial, oam4_pci, \
oam5_serial, oam5_pci, \
oam6_serial, oam6_pci, \
oam7_serial, oam7_pci, \
gaudi_model, gaudi_driver, python_version, os_name, \
os_version, openmpi_version, libfabric_version, \
test_framework, test_fw_version, test_model, \
energy_consumed, energy_meter_start, energy_meter_end, \
time_to_train, max_ipmi_power, average_training_time_step, \
e2e_train_time, training_sequences_per_second, final_loss, raw_train_time, eval_time, \
result_service, result_process, result_avg_train_time_step, result_time_to_train "

vv="${osi[ipmmac]}, ${osi[startt]}, ${osi[endtme]}, ${osi[elapse]}, ${osi[testts]}, \
${osi[ipmiip]}, ${osi[ipipv6]}, ${osi[fwvern]}, ${osi[fwdate]}, \
${osi[biosvr]}, ${osi[biosdt]}, ${osi[cpldvr]}, ${osi[gpcpld]}, ${osi[serial]}, ${osi[mfgdat]}, ${osi[mboard]}, \
${osi[cpumdl]}, ${osi[cpucor]}, ${osi[pcinfo]}, ${osi[memcnt]}, \
${osi[osintl]}, ${osi[machid]}, ${osi[govnor]}, ${osi[hgpage]}, ${osi[kernel]}, ${osi[hosmac]}, ${osi[hostip]}, \
${osi[hosnic]}, ${osi[rootsz]}, ${osi[hdrive]}, ${osi[uptime]}, \
${pkg[habanalabs-firmware]}, ${pkg[optimum-habana]}, ${pkg[torch]}, ${pkg[pytorch-lightning]}, \
${pkg[lightning-habana]}, ${pkg[tensorflow-cpu]}, ${pkg[transformers]}, \
${pkg[habanalabs]}, ${pkg[habanalabs_ib]}, ${pkg[habanalabs_cn]}, ${pkg[habanalabs_en]}, ${pkg[ib_uverbs]}, \
${oam["0,0"]}, ${oam["0,1"]}, ${oam["1,0"]}, ${oam["1,1"]}, ${oam["2,0"]}, ${oam["2,1"]}, ${oam["3,0"]}, ${oam["3,1"]}, \
${oam["4,0"]}, ${oam["4,1"]}, ${oam["5,0"]}, ${oam["5,1"]}, ${oam["6,0"]}, ${oam["6,1"]}, ${oam["7,0"]}, ${oam["7,1"]}, \
${osi[gaudig]}, ${osi[drivrv]}, ${osi[python]}, ${osi[osname]}, \
${osi[osvern]}, ${osi[opnmpi]}, ${osi[fabric]}, \
${osi[perfsw]}, ${osi[perfvr]}, ${osi[modelt]}, \
$energyco, $pwrsread, $pwrfread, \
$time2trn, $maxpower, $avgtstep, \
$e2e_time, $trainseq, $finaloss, $rawttime, $evaltime, \
$diff_srv, $diff_pro, $avgttime, $ttm_rslt "

ss=$(echo $vv | sed "s/, /', '/g")
ss="'"${ss}"'"

sql="INSERT INTO PERF_TEST(${kk}) VALUES ($ss);"

if [[ "$1" == "sql" ]]; then
	echo $kk
	echo $vv
	echo $sql
elif [[ "$1" == "list" ]]; then
	IFS=', ' read -r -a col <<< "$kk"
	IFS=, 	 read -r"${BASH_VERSION:+a}${ZSH_VERSION:+A}" val <<< "$vv"

	for (( i=0; i<${#col[@]}; i++ )); do
		# trim leading space
		printf  " %30s : %s\n" ${col[$i]} "$( echo -e "${val[$i]}" | sed 's/^[ \t]*//;s/[ \t]*$//' )"
		#echo  ${col[$i]}   ${val[$i]}
	done
else
	echo $kk
	echo $vv
fi
