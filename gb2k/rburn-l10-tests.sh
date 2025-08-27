# rburn test summary, extract failed DUT
# jk, 7/22/25

RED='\033[0;31m'
YLW='\033[0;33m'
BLU='\033[0;34m'
GRN='\033[0;32m'
BCY='\033[1;36m'
CYA='\033[0;36m'
NCL='\033[0m'

URL_RCK1="http://10.43.251.42"
URL_RCK2="http://10.43.251.45"

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

	# gen rack ID
	RACK="${LOG%%.*}"
	CUNT=$(wc -l _a-${LOG} | awk '{print $1}')
	yes $RACK | head -n $CUNT > _f-$LOG

	URL_RACK=$URL_RCK1
	if [ "$RACK" == "020" ] || [ "$RACK" == "030" ] || [ "$RACK" == "031" ]; then
		URL_RACK=$URL_RCK2
	fi

	# failure reason download url
	cat _b-$LOG | xargs  -I{} printf "%s%s\n" $URL_RACK {} | tee _e-$LOG
	
	# -------------
	
	# get Success SN
	grep " badge-success" ${LOG} | awk -F 'i>|<br>' '{print $4}'	 | tee _g-$LOG
	echo	

	# get RUNNING SN
	grep " badge-gray"    ${LOG} | awk -F 'i>|<br>' '{print $4}'	 | tee _i-$LOG
	echo

	# -------------

	# get Warning SN - as Failure
	grep " badge-warning" ${LOG} | awk -F 'i>|<br>' '{print $4}'   | tee _h-$LOG
	echo

	# get failure url
	grep " badge-warning" ${LOG} | awk -F 'url=|&amp' '{print $2}' | tee _j-$LOG
	echo

	# get MAC
	grep " badge-warning" ${LOG} | awk -F 'i>|<br>' '{print $1}' | awk -F '>|<' '{print $9}' | tee _k-$LOG
	echo

	# get Date
	grep " badge-warning" ${LOG} | awk -F '<td>| </td' '{print $10}' | tee _l-$LOG

	# gen rack ID
	RACK="${LOG%%.*}"
	CUNT=$(wc -l _h-${LOG} | awk '{print $1}')
	yes $RACK | head -n $CUNT > _n-$LOG

	URL_RACK=$URL_RCK1
	if [ "$RACK" == "020" ] || [ "$RACK" == "030" ] || [ "$RACK" == "031" ]; then
		URL_RACK=$URL_RCK2
	fi

	# warning reason download url
	cat _j-$LOG | xargs  -I{} printf "%s%s\n" $URL_RACK {} | tee _m-$LOG

	# -------------

	# total: wc -l _a-$LOG  _h-$LOG _g-$LOG
	rm _curl-$LOG &>/dev/null

	curl_failure_log _e-$LOG

	curl_failure_log _m-$LOG
}

function curl_failure_log(){
	while read p; do
		mac=$(echo "$p" | awk -F '/' '{print $12}')
		err=_${mac}_failure-record.txt
		quo=_${mac}_failure-quoted.txt

		# get the error root cause
		curl -s "$p" -o _1
		head -n 20 _1 > $err
		rm -rf _1
		echo $? >> _curl-$LOG

		grep "404 Not Found" $err
		if [ "$?" == "0" ] ; then
			echo "404 Not Found" > $err
		fi

		# add " to the failure for Excel
		echo -n '"' > ${quo}
		cat $err | grep . > _1		#remove empty lines
		truncate -s -1      _1		#remove last newline
		cat _1      >> ${quo}
		echo -n '"' >> ${quo}
		rm -rf _1
	done <"$1"
}

function countsn(){
	FAIL=0
	PASS=0
	WARN=0
	RUNN=0
	declare -a arr_f arr_p arr_w arr_r

	BCY='\033[1;36m'
	NCL='\033[0m'
	REGEX_SN="(S[0-9]{6}X[0-9]{7})"

	files=$1
	if [[ $1 =~ "all" ]]; then
		files="0*.html"
	fi

	grep -P "badge-danger|badge-success|badge-gray|badge-warning" ""$files"" > _tpms.html
	while read p; do
		if [[ "$p" =~ $REGEX_SN ]]; then
			SN="${BASH_REMATCH[1]}"
			echo "$SN"

			if   [[ $p =~ "badge-danger" ]]; then
				FAIL=$((FAIL + 1))
				arr_f+=("$SN")
			elif [[ $p =~ "badge-success" ]]; then
				PASS=$((PASS + 1))
				arr_p+=("$SN")
			elif [[ $p =~ "badge-warning" ]]; then
				WARN=$((WARN + 1))
				arr_w+=("$SN")
			elif [[ $p =~ "badge-gray" ]]; then
				RUNN=$((RUNN + 1))
				arr_r+=("$SN")
			fi
		fi
	done <_tpms.html
	rm -rf _tpms.html
	
	echo
	printf "${BCY}RUNN    PASS    FAIL    WARN${NCL}\n"
	printf "%4s%8s%8s%8s\n" $RUNN $PASS $FAIL $WARN 
	
	if [[ ${#arr_f[@]} > 0 ]]; then
		echo "---FAIL"
		for sn in "${arr_f[@]}"; do
			echo "  $sn"
		done
		echo
	fi

	if [[ ${#arr_w[@]} > 0 ]]; then
		echo "---WARN"
		for sn in "${arr_w[@]}"; do
			echo "  $sn"
		done
		echo
	fi

	if [[ ${#arr_r[@]} > 0 ]]; then
		echo "---RUNN"
		for sn in "${arr_r[@]}"; do
			echo "  $sn"
		done
		echo
	fi

	if [[ ${#arr_p[@]} > 0 && $2 =~ "succ" ]]; then
		echo "---Success"
		for sn in "${arr_p[@]}"; do
			echo "  $sn"
		done
	fi
}

function statsn(){
	printf "${BCY}RUNN    PASS    FAIL    WARN${NCL}\n"
	rm -rf _stats.txt
	FILES="0*.html"
	for f in $FILES
	do
		countsn "$f" | grep -P "RUNN "  -A 1 | grep -v RUNN | grep -v "\-\-"
	done
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

FILES="0*.html"		# print FAIL DUT
for f in $FILES
do
	pr -t -m -J _f-${f} _a-${f} _c-${f} _d-${f} _e-${f} | tee -a failed_dut.txt | tee -a rbn_report.txt
done

echo | tee -a failed_dut.txt | tee -a rbn_report.txt

FILES="0*.html"		# print WARNING DUT
for f in $FILES
do
	pr -t -m -J _n-${f} _h-${f} _k-${f} _l-${f} _m-${f} | tee -a failed_dut.txt | tee -a rbn_report.txt
done

rm -rf failed_rpt.txt
while read p; do
	[[ ! -n "$p" ]] && continue

	mac=$(echo "$p" | awk '{print $3}')
	quo=_${mac}_failure-quoted.txt

	echo -e -n "$p\t" >> failed_rpt.txt
	cat $quo >> failed_rpt.txt
	echo     >> failed_rpt.txt
done <failed_dut.txt

# ----------------

echo 
CUNT=$(grep . failed_dut.txt | wc -l | awk '{print $1}')
echo -e "total failed count: $CUNT"
echo

echo >> rbn_report.txt

FILES="0*.html"
printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "Rack#" "Total" "Running" "Pass" "Fail" "Warning" "SCANned" | tee -a rbn_report.txt
for f in $FILES
do
	RACK="${f%%.*}"

	PASS=$(wc -l _g-$f | awk '{print $1}')
	FAIL=$(wc -l _a-$f | awk '{print $1}')
	WARN=$(wc -l _h-$f | awk '{print $1}')
	RUNN=$(wc -l _i-$f | awk '{print $1}')
	
	SCAN=$(grep "fas fa-barcode mr-2" $f -A 1 | tail -1 | awk -F '<|>'  '{print $3}')
	TOTL=$(( $PASS + $FAIL + $RUNN + $WARN ))

	echo
	printf "%s\t%s\t%s\t${CYA}%s${NCL}\t${RED}%s\t%s${NCL}\t%s\r" $RACK $TOTL $RUNN $PASS $FAIL $WARN $SCAN  
	printf "%s\t%s\t%s\t${CYA}%s${NCL}\t${RED}%s\t%s${NCL}\t%s\n" $RACK $TOTL $RUNN $PASS $FAIL $WARN $SCAN  >> rbn_report.txt
	sync
done
echo

TT_FAIL=$(cat _a-* | wc -l)
TT_WARN=$(cat _h-* | wc -l)
TT_PASS=$(cat _g-* | wc -l)
TT_RUNN=$(cat _i-* | wc -l)

TT_SCAN=$(cat _g-* | wc -l)

TT_TEST=$(cat _a-* _g-* _h-* | wc -l)
TT_TOTL=$(cat _a-* _g-* _h-* _i-* | wc -l)

TT_BADS=$((TT_FAIL+TT_WARN))

FAIL_RT=$(awk -v i="$TT_BADS" -v t="$TT_TEST" 'BEGIN { printf "%.2f", (i/t)*100 }')

echo
echo >> rbn_report.txt
printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "Tested" "Total" "Running" "Pass" "Fail" "Warning" "Fail_Rate" | tee -a rbn_report.txt

printf "%s\t%s\t%s\t${CYA}%s${NCL}\t${RED}%s\t%s${NCL}\t%s\n" $TT_TEST $TT_TOTL $TT_RUNN $TT_PASS $TT_FAIL $TT_WARN ${FAIL_RT}% | tee -a rbn_report.txt
echo
