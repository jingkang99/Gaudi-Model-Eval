# rack bringup test summary - *.html
# jk,  7/22/25
# https://us-rack.supermicro.com/searchportal/search-logs

RED='\033[0;31m'
YLW='\033[0;33m'
BLU='\033[0;34m'
GRN='\033[0;32m'
BCY='\033[1;36m'
CYA='\033[0;36m'
NCL='\033[0m' 

function parse(){
	LOG=$1

	# get SN
	grep " badge-danger" ${LOG} -A 8 | grep ext-center\"\>S | awk -F '>' '{print $2}' | awk -F '<' '{print $1}' | tee _a-$LOG
	echo

	# get failure reason
	grep " badge-danger" ${LOG} -A 8 | grep  title | awk -F 'data-original-title="' '{print $2}' | awk -F '"' '{print $1}' | tee _b-$LOG
	echo

	# get MAC
	grep " badge-danger" ${LOG} -A 8 | grep text-center\"\>7 | awk -F '>' '{print $2}' | awk -F '<' '{print $1}'| tee _c-$LOG
	echo

	# get date
	grep " badge-danger" ${LOG} -B 2 | grep text-center | awk -F '>' '{print $2}' | awk -F '<' '{print $1}' 	| tee _h-$LOG
	echo

	# get error log url
	grep " badge-danger" ${LOG} -A 18 | grep '/firmware/' | awk -F '="' '{print $2}' | awk -F '"' '{print $1}'  | tee _u-$LOG
	echo

	# gen rack ID
	RACK="${LOG%%.*}"
	CUNT=$(wc -l _a-${LOG} | awk '{print $1}')
	yes $RACK | head -n $CUNT > _d-$LOG

	#--- count updating and scucess
	# Updating
	grep " badge-info"    ${LOG} -A 8 | grep ext-center\"\>S | awk -F '>' '{print $2}' | awk -F '<' '{print $1}' | tee _e-$LOG
	echo
	grep " badge-success" ${LOG} -A 8 | grep ext-center\"\>S | awk -F '>' '{print $2}' | awk -F '<' '{print $1}' | tee _f-$LOG
	echo
	# New
	grep " badge-light"   ${LOG} -A 8 | grep ext-center\"\>S | awk -F '>' '{print $2}' | awk -F '<' '{print $1}' | tee _g-$LOG
	echo
}

# save each rack test failure
rm  _*

FILES="0*.html"
for f in $FILES
do
	parse "$f"
done

# gen failure list
rm -rf failed_dut.txt
rm -rf bup_report.txt

FILES="0*.html"
for f in $FILES
do
	pr -t -m -J _d-${f} _a-${f} _c-${f} _h-${f} _u-${f} _b-${f} | tee -a failed_dut.txt | tee -a bup_report.txt
done

echo | tee -a bup_report.txt
awk -F '\t' '{print $6}' failed_dut.txt | sort | uniq -c | sort -n -r | tee -a bup_report.txt

echo 
CUNT=$(wc -l failed_dut.txt | awk '{print $1}')
echo -e "total failed count: $CUNT"
echo

echo >> bup_report.txt

FILES="0*.html"
printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "Rack#" "Total" "Update" "Passed" "Failed" "New" "FPYR" | tee -a bup_report.txt
for f in $FILES
do
	RACK="${f%%.*}"

	PASS=$(wc -l _f-$f | awk '{print $1}')
	FAIL=$(wc -l _a-$f | awk '{print $1}')
	UPDT=$(wc -l _e-$f | awk '{print $1}')
	NEWD=$(wc -l _g-$f | awk '{print $1}')

	TOTL=$(( $PASS+$FAIL+$UPDT+$NEWD ))
	FPYR=$(echo "scale=2; $PASS / $((PASS+FAIL)) * 100" | bc)

	echo
	printf "%s\t%s\t%s\t${CYA}%s${NCL}\t${RED}%s${NCL}\t%s\t%s\r" $RACK $TOTL $UPDT $PASS $FAIL $NEWD ${FPYR}%
	printf "%s\t%s\t%s\t${CYA}%s${NCL}\t${RED}%s${NCL}\t%s\t%s\n" $RACK $TOTL $UPDT $PASS $FAIL $NEWD ${FPYR}% >> bup_report.txt
done
echo

TT_FAIL=$(cat _a-* | wc -l)
TT_PASS=$(cat _f-* | wc -l)

TT_UPDT=$(cat _e-* | wc -l)
TT_NEWD=$(cat _g-* | wc -l)

TT_TEST=$(cat _a-* _f-* | wc -l)
TT_TOTL=$(cat _a-* _e-* _f-* _g-* | wc -l)

#FAIL_RT=$(echo "scale=2; $TT_FAIL / $TT_TEST * 100" | bc)
FAIL_RT=$(awk -v i="$TT_FAIL" -v t="$TT_TEST" 'BEGIN { printf "%.2f", (i/t)*100 }')

echo
echo >> bup_report.txt
printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "Tested" "Total" "Update" "Passed" "Failed" "New" "FAIL-RATE" | tee -a bup_report.txt

printf "%s\t%s\t%s\t${CYA}%s${NCL}\t${RED}%s${NCL}\t%s\t%s\n" $TT_TEST $TT_TOTL $TT_UPDT $TT_PASS $TT_FAIL $TT_NEWD ${FAIL_RT}% | tee -a bup_report.txt
echo

# uniq SN test result records
awk '{print $2}' failed_dut.txt | sort | uniq -c | sort -n | grep '1 ' | awk '{print $2}' | xargs -I {} grep {} failed_dut.txt | sort > _uniq_1.txt

# multi-records SN
awk '{print $2}' failed_dut.txt | sort | uniq -c | sort -n | grep -v '1 ' > _mult_1.txt

# get latest result for multi-records
#cat _mult_1.txt | awk '{print $2}' | xargs -d $'\n' sh -c 'for arg do grep "$arg" failed_dut.txt | sort -u -k 3 | tail -n 1; done' > _uniq_2.txt
cat _mult_1.txt | awk '{print $2}' | xargs -I {} sh -c 'grep {} failed_dut.txt | sort -u -k 3 | tail -n 1' > _uniq_2.txt

cat _uniq_1.txt _uniq_2.txt | sort > rck_report.txt
sort -k 4 -r rck_report.txt > dat_report.txt

echo "" >> dat_report.txt
awk -F '\t' '{print $6}' rck_report.txt | sort | uniq -c | sort -n -r >> dat_report.txt

# update
UQ_UPDT=$(cat _e-* | sort | uniq -c | wc -l)

# success
UQ_PASS=$(cat _f-* | sort | uniq -c | wc -l)
cat _f-* | sort | uniq -c | awk '{print $2}' > _pass.txt

# new
UQ_NEWD=$(cat _g-* | sort | uniq -c | wc -l)

# fail
UQ_FAIL=$(cat _a-* | sort | uniq -c | wc -l)
cat _a-* | sort | uniq -c | awk '{print $2}' > _fail.txt

UQ_TEST=$(cat _a-* _f-* | sort | uniq -c | wc -l)
UQ_TOTL=$(cat _a-* _e-* _f-* _g-* | sort | uniq -c | wc -l)

FAIL_UQ=$(awk -v i="$UQ_FAIL" -v t="$UQ_TEST" 'BEGIN { printf "%.2f", (i/t)*100 }')

echo "" >> dat_report.txt
echo -e "${BCY}unique SN test stats${NCL}\n" | tee -a dat_report.txt

printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "Tested" "Total" "Update" "Passed" "Failed" "New" "FAIL-RATE" | tee -a dat_report.txt 
printf "%s\t%s\t%s\t${CYA}%s${NCL}\t${RED}%s${NCL}\t%s\t%s\t%s\n" $UQ_TEST $UQ_TOTL $UQ_UPDT $UQ_PASS $UQ_FAIL $UQ_NEWD ${FAIL_UQ}% "some failed DUT fixed and passed" | tee -a dat_report.txt

rm -rf _fixd.txt _ffal.txt
while IFS= read -r line; do
	grep $line _pass.txt >> _fixd.txt
	[ $? != 0 ] && (echo $line >> _ffal.txt)
done < "_fail.txt"

NOT_FIX=$(cat _ffal.txt | wc -l)
FAIL_NF=$(awk -v i="$NOT_FIX" -v t="$UQ_TEST" 'BEGIN { printf "%.2f", (i/t)*100 }')

#printf "%s\t%s\t%s\t${CYA}%s${NCL}\t${RED}%s${NCL}\t%s\t%s\t%s\n" $UQ_TEST $UQ_TOTL $UQ_UPDT $UQ_PASS $NOT_FIX $UQ_NEWD ${FAIL_NF}% "don't count fixed DUT" | tee -a dat_report.txt 

rm -rf unq_report.txt
while IFS= read -r sn; do
	grep $sn dat_report.txt >> unq_report.txt
done < "_ffal.txt"

awk -F '\t' '{print $6}' unq_report.txt | sort | uniq -c | sort -n -r > _rcause.txt

echo 
printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "Tested" "Total" "Update" "Passed" "Failed" "New" "FAIL-RATE" | tee -a unq_report.txt
printf "%s\t%s\t%s\t${CYA}%s${NCL}\t${RED}%s${NCL}\t%s\t%s\t%s\n" $UQ_TEST $UQ_TOTL $UQ_UPDT $UQ_PASS $NOT_FIX $UQ_NEWD ${FAIL_NF}% "don't count fixed DUT" | tee -a unq_report.txt 

# ---- category mapping 

Script_Exec=0
Power=0
BIOS=0
EGM=0
Firmware=0
BMC=0
Task_No_Run=0
while IFS= read -r ll; do
    val=$(echo $ll | awk '{print $1}')
	msg=$(echo $ll | awk '{ for (i = 2; i <= NF; i++) { printf "%s%s", $i, (i == NF ? "" : OFS) } printf "\n" }')

	if   [[ $msg =~ "Error detected in script" ]]; then
		Script_Exec=$((Script_Exec + val))

	elif [[ $msg =~ "Script execution failed" ]]; then
		Script_Exec=$((Script_Exec + val))

	elif [[ $msg =~ "Chassis Power still OFF" ]]; then
		Power=$((Power + val))

	elif [[ $msg =~ "Failed to power" ]]; then
		Power=$((Power + val))

	elif [[ $msg =~ "Failed to perform AC" ]]; then
		Power=$((Power + val))

	elif [[ $msg =~ "BIOS Attributes" ]]; then
		BIOS=$((BIOS + val))

	elif [[ $msg =~ "Failed to set EGM" ]]; then
		EGM=$((EGM + val))

	elif [[ $msg =~ "Firmwares are not" ]]; then
		Firmware=$((Firmware + val))

	elif [[ $msg =~ "Failed to retrieve Firmware" ]]; then
		Firmware=$((Firmware + val))

	elif [[ $msg =~ "BMC is unreachable" ]]; then
		BMC=$((BMC + val))

	elif [[ $msg =~ "Task is no longer" ]]; then
		Task_No_Run=$((Task_No_Run + val))

	else
		UNKNOWN=$((UNKNOWN + 1))		
	fi
done < "_rcause.txt"

echo -e "\n${BCY}failure category stats${NCL}\n" | tee -a unq_report.txt

printf "%s\t%s\n" "Script_Exec"	$Script_Exec | tee -a unq_report.txt
printf "%s\t%s\n" "Power" 		$Power		 | tee -a unq_report.txt	
printf "%s\t%s\n" "BIOS"		$BIOS		 | tee -a unq_report.txt
printf "%s\t%s\n" "EGM" 		$EGM		 | tee -a unq_report.txt
printf "%s\t%s\n" "Firmware"	$Firmware	 | tee -a unq_report.txt
printf "%s\t%s\n" "BMC" 		$BMC		 | tee -a unq_report.txt
printf "%s\t%s\n" "Task_No_Run"	$Task_No_Run | tee -a unq_report.txt
