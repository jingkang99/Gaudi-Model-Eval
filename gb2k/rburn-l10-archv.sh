# rburn test summary, extract SN and count
# jk, 8/19/25

RED='\033[0;31m'
YLW='\033[0;33m'
BLU='\033[0;34m'
GRN='\033[0;32m'
BCY='\033[1;36m'
CYA='\033[0;36m'
NCL='\033[0m'

REGEX_SN="(S[0-9]{6}X[0-9]{7})"

function snsn(){
	grep "$1" "$2" > _tpms.html
	while read p; do
		if [[ "$p" =~ $REGEX_SN ]]; then
			SN="${BASH_REMATCH[1]}"
			echo "$SN"
		fi
	done <_tpms.html
	rm -rf _tpms.html
}
	
function count_dut(){
	LOG=$1

	# get Failure SN
	grep " badge-danger"  ${LOG} | wc -l | tee -a _fail.cnt &>/dev/null
	snsn " badge-danger"  ${LOG} >> _fail.sns

	# get Success SN
	grep " badge-success" ${LOG} | wc -l | tee -a _succ.cnt &>/dev/null
	snsn " badge-success" ${LOG} >> _succ.sns

	# get RUNNING SN
	grep " badge-gray"    ${LOG} | wc -l | tee -a _runn.cnt &>/dev/null
	snsn " badge-gray"	  ${LOG} >> _runn.sns

	# get Warning SN - as Failure
	grep " badge-warning" ${LOG} | wc -l | tee -a _warn.cnt &>/dev/null
	snsn " badge-warning" ${LOG} >> _warn.sns
}

# save each rack test failure
rm  _*

FILES="0*.html"
for f in $FILES
do
	count_dut "$f"
done

cp _warn.sns _warn.bak
cat _succ.sns | xargs -I{} grep {} _warn.sns | xargs -I{} sed -i 's/{}//g' _warn.bak
grep . _warn.bak > _warn.fix
echo -e "  warning DUT after fix:" `cat _warn.fix | wc -l`

cp _fail.sns _fail.bak
cat _succ.sns | xargs -I{} grep {} _fail.sns | xargs -I{} sed -i 's/{}//g' _fail.bak
grep . _fail.bak > _fail.fix
echo -e "  failure DUT after fix:" `cat _fail.fix | wc -l`

cp _runn.sns _runn.bak
cat _succ.sns | xargs -I{} grep {} _runn.sns | xargs -I{} sed -i 's/{}//g' _runn.bak
grep . _runn.bak > _runn.fix
echo -e "  running DUT after fix:" `cat _runn.fix | wc -l`
echo

TT_FAIL=$(paste -sd+ _fail.cnt | bc)
TT_PASS=$(paste -sd+ _succ.cnt | bc)
TT_RUNN=$(paste -sd+ _runn.cnt | bc)
TT_WARN=$(paste -sd+ _warn.cnt | bc)

TT_TEST=$((TT_FAIL+TT_WARN+TT_PASS))
TT_TOTL=$((TT_FAIL+TT_WARN+TT_PASS+TT_RUNN))

TT_BADS=$((TT_FAIL+TT_WARN))

FAIL_RT=$(awk -v i="$TT_BADS" -v t="$TT_TEST" 'BEGIN { printf "%.2f", (i/t)*100 }')

printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "Tested" "Total" "Running" "Pass" "Fail" "Warning" "Fail_Rate"

printf "%s\t%s\t%s\t${CYA}%s${NCL}\t${RED}%s\t%s${NCL}\t%s	not dedup\n" $TT_TEST $TT_TOTL $TT_RUNN $TT_PASS $TT_FAIL $TT_WARN ${FAIL_RT}%

TT_FAIL=$(cat _fail.fix | wc -l)
TT_RUNN=$(cat _runn.fix | wc -l)
TT_WARN=$(cat _warn.fix | wc -l)

TT_TEST=$((TT_FAIL+TT_WARN+TT_PASS))
TT_TOTL=$((TT_FAIL+TT_WARN+TT_PASS+TT_RUNN))

TT_BADS=$((TT_FAIL+TT_WARN))

FAIL_RT=$(awk -v i="$TT_BADS" -v t="$TT_TEST" 'BEGIN { printf "%.2f", (i/t)*100 }')

printf "%s\t%s\t%s\t${CYA}%s${NCL}\t${RED}%s\t%s${NCL}\t%s	remove successfule SN from fail warn and run\n" $TT_TEST $TT_TOTL $TT_RUNN $TT_PASS $TT_FAIL $TT_WARN ${FAIL_RT}% 
