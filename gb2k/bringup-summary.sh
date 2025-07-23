# rack bringup test summary - *.html
# jk,  7/22/25

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
	grep " badge-danger" ${LOG} -A 8 | grep  title | awk -F 'title="' '{print $2}' | awk -F '"' '{print $1}'    | tee _b-$LOG
	echo

	# get MAC
	grep " badge-danger" ${LOG} -A 8 | grep ext-center\"\>7 | awk -F '>' '{print $2}' | awk -F '<' '{print $1}' | tee _c-$LOG
	echo

	# gen ID
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

FILES="0*.html"
for f in $FILES
do
	pr -t -m -J _d-${f} _a-${f} _c-${f} _b-${f} | tee -a failed_dut.txt
done

echo
awk -F '\t' '{print $4}' failed_dut.txt | sort | uniq -c | sort -n -r 

echo
CUNT=$(wc -l failed_dut.txt | awk '{print $1}')
echo -e "total failed count: $CUNT"
echo

FILES="0*.html"
printf "%s\t%s\t%s\t%s\t%s\t%s\t\t%s" "Rack#" "Total" "Update" "Passed" "Failed" "New" "FPYR" 
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

	printf "%s\t\t%s\t\t%s\t\t${CYA}%s${NCL}\t\t${RED}%s${NCL}\t\t%s\t\t%s" $RACK $TOTL $UPDT $PASS $FAIL $NEWD ${FPYR}%
done
echo

TT_FAIL=$(cat _a-* | wc -l)
TT_PASS=$(cat _f-* | wc -l)

TT_UPDT=$(cat _e-* | wc -l)
TT_NEWD=$(cat _g-* | wc -l)

TT_TEST=$(cat _a-* _f-* | wc -l)
TT_TOTL=$(cat _a-* _e-* _f-* _g-* | wc -l)

FAIL_RT=$(echo "scale=2; $TT_FAIL / $TT_TEST * 100" | bc)

echo
printf "%s\t%s\t%s\t%s\t%s\t%s\t\t%s\n" "Tested" "Total" "Update" "Passed" "Failed" "New" "FAIL-RATE" 

printf "%s\t\t%s\t\t%s\t\t${CYA}%s${NCL}\t\t${RED}%s${NCL}\t\t%s\t\t%s\n" $TT_TEST $TT_TOTL $TT_UPDT $TT_PASS $TT_FAIL $TT_NEWD ${FAIL_RT}%
