# rburn test summary, extract failed DUT
# jk, 7/22/25

RED='\033[0;31m'
YLW='\033[0;33m'
BLU='\033[0;34m'
GRN='\033[0;32m'
BCY='\033[1;36m'
CYA='\033[0;36m'
NCL='\033[0m'

URL_HOME="http://10.43.251.42"

function parse(){
	LOG=$1

	# get Failure SN
	grep " badge-danger" ${LOG} | awk -F 'i>|<br>' '{print $4}'	  | tee _a-$LOG
	echo

	# get failure url
	grep " badge-danger" ${LOG} | awk -F 'url=|&amp' '{print $2}' | tee _b-$LOG
	echo

	# get MAC
	grep " badge-danger" ${LOG} | awk -F 'i>|<br>' '{print $1}' | awk -F '>|<' '{print $9}' | tee _c-$LOG
	echo

	# get Date
	grep " badge-danger" ${LOG} | awk -F '<td>| </td' '{print $10}' | tee _d-$LOG

	# failure reason download url
	cat _b-001.html | xargs  -I{} printf "%s%s\n" $URL_HOME {}      | tee _e-$LOG

	# gen ID
	RACK="${LOG%%.*}"
	CUNT=$(wc -l _a-${LOG} | awk '{print $1}')
	yes $RACK | head -n $CUNT > _f-$LOG
	
	# get Success SN
	grep " badge-success" ${LOG} | awk -F 'i>|<br>' '{print $4}'	 | tee _g-$LOG
	echo	

	# get Warning SN
	grep " badge-warning" ${LOG} | awk -F 'i>|<br>' '{print $4}'	 | tee _h-$LOG
	echo
	# total: wc -l _a-$LOG  _h-$LOG _g-$LOG

	while read p; do
		mac=$(echo "$p" | awk -F '/' '{print $12}')
		err=_${mac}_failure-record.txt
		quo=_${mac}_failure-quoted.txt
		curl -s "$p" -o $err

		# add " to the failure for Excel
		echo -n '"' > ${quo}
		cat $err | grep . >> ${quo}
		echo -n '"' >> ${quo}
	done <_e-$LOG
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
rm -rf rbn_report.txt

FILES="0*.html"
for f in $FILES
do
	pr -t -m -J _f-${f} _a-${f} _c-${f} _d-${f} _e-${f} | tee -a failed_dut.txt | tee -a rbn_report.txt
done

rm -rf failed_rpt.txt
while read p; do
	mac=$(echo "$p" | awk '{print $3}')
	quo=_${mac}_failure-quoted.txt

	echo -e -n "$p\t" >> failed_rpt.txt
	cat $quo >> failed_rpt.txt
	echo     >> failed_rpt.txt
done <failed_dut.txt

# ----------------

echo 
CUNT=$(wc -l failed_dut.txt | awk '{print $1}')
echo -e "total failed count: $CUNT"
echo

echo >> rbn_report.txt

FILES="0*.html"
printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "Rack#" "Total" "Update" "Passed" "Failed" "New" "FPYR" | tee -a rbn_report.txt
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
	printf "%s\t%s\t%s\t${CYA}%s${NCL}\t${RED}%s${NCL}\t%s\t%s\n" $RACK $TOTL $UPDT $PASS $FAIL $NEWD ${FPYR}% | tee -a rbn_report.txt
done
echo

TT_FAIL=$(cat _a-* | wc -l)
TT_PASS=$(cat _f-* | wc -l)

TT_UPDT=$(cat _e-* | wc -l)
TT_NEWD=$(cat _g-* | wc -l)

TT_TEST=$(cat _a-* _f-* | wc -l)
TT_TOTL=$(cat _a-* _e-* _f-* _g-* | wc -l)

FAIL_RT=$(echo "scale=2; $TT_FAIL / $TT_TEST * 100" | bc)

echo >> rbn_report.txt
printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "Tested" "Total" "Update" "Passed" "Failed" "New" "FAIL-RATE" | tee -a rbn_report.txt

printf "%s\t%s\t%s\t${CYA}%s${NCL}\t${RED}%s${NCL}\t%s\t%s\n" $TT_TEST $TT_TOTL $TT_UPDT $TT_PASS $TT_FAIL $TT_NEWD ${FAIL_RT}% | tee -a rbn_report.txt
echo

