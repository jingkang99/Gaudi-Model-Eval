# rburn test summary, extract SN and count
# jk, 8/25/25

RED='\033[0;31m'
YLW='\033[0;33m'
BLU='\033[0;34m'
GRN='\033[0;32m'
BCY='\033[1;36m'
CYA='\033[0;36m'
NCL='\033[0m'

REGEX_SN="(S[0-9]{6}X[0-9]{7})"	# S959549X5704811

URL41_06="http://10.43.251.41/monitor/Oracle/backup/2025-06/"
URL41_07="http://10.43.251.41/monitor/Oracle/backup/2025-07/"
URL41_08="http://10.43.251.41/monitor/Oracle/backup/2025-08/"

URL40_07="http://10.43.251.40/monitor/Oracle/backup/2025-07/"
URL40_08="http://10.43.251.40/monitor/Oracle/backup/2025-08/"

URL39_06="http://10.43.251.39/monitor/Oracle/backup/2025-06/"
URL39_07="http://10.43.251.39/monitor/Oracle/backup/2025-07/"

url_rack1='http://10.43.251.41'

#  -- parse current L11 result
#
function get_current_index(){
	index='s'$1'.html'
	snsns='_'$1'-00'

	while IFS= read -r line; do
		link=$(echo $line | awk -F 'href="' '{print $2}' | awk -F '"' '{print $1}')
		html='SR'$(echo $link | awk -F 'SR' '{print $2}')
		#echo ${url_rack1}${link} ${html}

		parse_l11_sns ${html} ${snsns}
		
		#curl -s -O ${url_rack1}${link}
	done < <(grep "fas fa-check-circle mr-1" $index)
	
	PASS=$(grep "fas fa-check-circle mr-1" $index | grep bg-success-bright |wc -l)
	WARN=$(grep "fas fa-check-circle mr-1" $index | grep bg-warning-bright |wc -l)
	RUNN=$(grep "fas fa-check-circle mr-1" $index | grep bg-dark-bright    |wc -l)
	TOTL=$(( $PASS + $RUNN + $WARN ))
}

#  -- parse archived rack L11 result and 18 server SN
#
function get_archive_index(){
	url=$1

	rm -rf _1 _2 
	curl -k -s $url -o _1

	grep 1.html _1 | awk -F 'href="' '{print $2}' | awk -F '"' '{print $1}' | xargs -I{} curl -s -O $url{}
	grep 1.html _1 | awk -F 'href="' '{print $2}' | awk -F '"' '{print $1}' > _2

	while read p; do
		parse_l11_sns $p $2
	done <_2
	echo | tee -a _l11_rklist.txt
	rm -rf _1 _2 
}

#  -- parse rack L11 result and 18 servers SN
#
function parse_l11_sns(){
	p=$1

	Group_Name=$( grep -A 1 "Group Name" $p | awk -F '<|>' '{print $3}' | grep . )
	Pass_Count=$( grep "mb-0 font-weight-bold text-success" $p | grep h2 | awk -F '<|>' '{print $3}' | sed 's/\r//g; s/\n//g' )
	Fail_Count=$( grep "mb-0 font-weight-bold text-danger"  $p | grep h2 | awk -F '<|>' '{print $3}' | sed 's/\r//g; s/\n//g' )

	L11_Result='Pass'
	if [[ $Fail_Count -gt 0 ]]; then
		L11_Result='Fail'
	elif [[ $Fail_Count -eq 0 && $Pass_Count -eq 0 ]]; then
		L11_Result='Runn'
	fi

	printf "%s %s %2s %2s %s\n" $Group_Name $L11_Result $Pass_Count $Fail_Count $p | tee -a _l11_rklist.txt | tee -a $2 
	printsn $p >> _l11_snlist.txt
}

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

function printsn(){
	REGEX_SN="(S[0-9]{6}X[0-9]{7})"

	files=$1
	if [[ $1 =~ "all" ]]; then
		files="0*.html"
	fi

	grep -P 'badge-danger|badge-success|badge-gray|badge-warning' ""$files"" > _tpms.html
	while read p; do
		if [[ "$p" =~ $REGEX_SN ]]; then
			SN="${BASH_REMATCH[1]}"
			echo "$SN"
		fi
	done <_tpms.html
	rm -rf _tpms.html
}

function search_sn(){
	echo -e "       ${YLW}$1${NCL} in "
	grep $1 _40-00 _41-00
	grep $1 _39_06 _39_07 _40-07 _40-08 _41-06 _41-07 _41-08
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

# ------------------

rm -rf _l11_rklist.txt _l11_snlist.txt _*

get_current_index "41"
P1=$(grep Pass _41-00 | wc -l)
W1=$(grep Fail _41-00 | wc -l)
R1=$(grep Runn _41-00 | wc -l)
T1=$(grep .    _41-00 | wc -l)
echo

[[ ! -e _41-06 ]] && get_archive_index $URL41_06 "_41-06"
P416=$(grep -P    "Pass 1[0-9] " _41-06 | wc -l)
W416=$(grep -P -v "Pass 1[0-9] " _41-06 | wc -l)
T416=$(grep . _41-06 | wc -l)
R416=0

[[ ! -e _41-07 ]] && get_archive_index $URL41_07 "_41-07"
P417=$(grep -P    "Pass 1[0-9] " _41-07 | wc -l)
W417=$(grep -P -v "Pass 1[0-9] " _41-07 | wc -l)
T417=$(grep . _41-07 | wc -l)
R417=0

get_archive_index $URL41_08 "_41-08"
P418=$(grep -P    "Pass 1[0-9] " _41-08 | wc -l)
W418=$(grep -P -v "Pass 1[0-9] " _41-08 | wc -l)
T418=$(grep . _41-08 | wc -l)
R418=0

# -----	40
get_current_index "40"
#read -r T0 P0 W0 R0 <<< "$TOTL $PASS $WARN $RUNN"
P0=$(grep Pass _40-00 | wc -l)
W0=$(grep Fail _40-00 | wc -l)
R0=$(grep Runn _40-00 | wc -l)
T0=$(grep .    _40-00 | wc -l)
echo

[[ ! -e _40-07 ]] && get_archive_index $URL40_07 "_40-07"
P407=$(grep -P    "Pass 1[0-9] " _40-07 | wc -l)
W407=$(grep -P -v "Pass 1[0-9] " _40-07 | wc -l)
T407=$(grep . _40-07 | wc -l)
R407=0

get_archive_index $URL40_08 "_40-08"
P408=$(grep -P    "Pass 1[0-9] " _40-08 | wc -l)
W408=$(grep -P -v "Pass 1[0-9] " _40-08 | wc -l)
T408=$(grep . _40-08 | wc -l)
R408=0

# ----- 39
[[ ! -e _39-06 ]] && get_archive_index $URL39_06 "_39_06"
P396=$(grep -P    "Pass 1[0-9] " _39_06 | wc -l)
W396=$(grep -P -v "Pass 1[0-9] " _39_06 | wc -l)
T396=$(grep . _39_06 | wc -l)
R396=0

[[ ! -e _39-07 ]] && get_archive_index $URL39_07 "_39_07"
P397=$(grep -P    "Pass 1[0-9] " _39_07 | wc -l)
W397=$(grep -P -v "Pass 1[0-9] " _39_07 | wc -l)
T397=$(grep . _39_07 | wc -l)
R397=0

rm -rf _arch_rk_sv.txt _a_rk.txt _curr_rk_sv.txt _c_rk.txt
# archived rack and server sn
REGEX_RK="(SR[0-9]{12})-1"	# SR010530252523
for f in 2025-*.html
do
	if [[ "$f" =~ $REGEX_RK ]]; then
		RK="${BASH_REMATCH[1]}"
		echo "=$RK"	 | tee -a _arch_rk_sv.txt | tee -a _a_rk.txt
		countsn "$f" | tee -a _arch_rk_sv.txt
	fi
done

# current rack and server sn
REGEX_NW="(^SR[0-9]+)"		# SR010530252523
for f in SR0*.html
do
	if [[ $f =~ $REGEX_NW ]]; then
		RK="${BASH_REMATCH[1]}"
		echo "=$RK"	 | tee -a _curr_rk_sv.txt | tee -a _c_rk.txt
		countsn "$f" | tee -a _curr_rk_sv.txt
	fi
done

echo
printf "${BCY}%s\t%s\t%s\t%s\t%s${NCL}\n" "Site" "Total" "Pass" "Fail" "Runn" | tee -a _l11_statsd.txt
printf "%s\t%s\t%s\t%s\t%s\n" "41-c" $T1 	$P1   $W1 	$R1 	| tee -a _l11_statsd.txt
printf "%s\t%s\t%s\t%s\t%s\n" "41-6" $T416 $P416 $W416 $R416	| tee -a _l11_statsd.txt
printf "%s\t%s\t%s\t%s\t%s\n" "41-7" $T417 $P417 $W417 $R417	| tee -a _l11_statsd.txt
printf "%s\t%s\t%s\t%s\t%s\n" "41-8" $T418 $P418 $W418 $R418	| tee -a _l11_statsd.txt
echo | tee -a _l11_statsd.txt
printf "%s\t%s\t%s\t%s\t%s\n" "40-c" $T0 	$P0   $W0 	$R0 	| tee -a _l11_statsd.txt
printf "%s\t%s\t%s\t%s\t%s\n" "40-7" $T407 $P407 $W407 $R407	| tee -a _l11_statsd.txt
printf "%s\t%s\t%s\t%s\t%s\n" "40-8" $T408 $P408 $W408 $R408	| tee -a _l11_statsd.txt
echo | tee -a _l11_statsd.txt
printf "%s\t%s\t%s\t%s\t%s\n" "39-6" $T396 $P396 $W396 $R396	| tee -a _l11_statsd.txt
printf "%s\t%s\t%s\t%s\t%s\n" "39-7" $T397 $P397 $W397 $R397	| tee -a _l11_statsd.txt
echo | tee -a _l11_statsd.txt

printf "%s\t%s\t%s\t%s\t%s\n" "TT41" $((T1+T416+T417+T418)) \
									 $((P1+P416+P417+P418)) \
									 $((W1+W416+W417+W418)) \
									 $((R1+R416+R417+R418))		| tee -a _l11_statsd.txt
echo | tee -a _l11_statsd.txt
printf "%s\t%s\t%s\t%s\t%s\n" "TT40" $((T0+T407+T408)) \
									 $((P0+P407+P408)) \
									 $((W0+W407+W408)) \
									 $((R0+R407+R408))			| tee -a _l11_statsd.txt
echo | tee -a _l11_statsd.txt

printf "%s\t%s\t%s\t%s\t%s\n" "TT39" $((T396+T397)) \
									 $((P396+P397)) \
									 $((W396+W397)) \
									 $((R396+R397))				| tee -a _l11_statsd.txt
echo | tee -a _l11_statsd.txt

TT=$((T1+T416+T417+T418+T0+T407+T408+T396+T397))
PS=$((P1+P416+P417+P418+P0+P407+P408+P396+P397))
FA=$((W1+W416+W417+W418+W0+W407+W408+W396+W397))
RU=$((R1+R416+R417+R418+R0+R407+R408+R396+R397))

printf "%s\t%s\t%s\t%s\t%s\n" "TOTL" $TT $PS $FA $RU | tee -a _l11_statsd.txt

grep . _l11_rklist.txt | awk '{print $1}' | sort | uniq > _l11_uniqrk.txt
dup_rack=$(grep . _l11_rklist.txt | awk '{print $1}' | sort | uniq -c | sort | grep -v '1 ' | wc -l)
dup_fail=$(grep . _l11_rklist.txt | awk '{print $1}' | sort | uniq -c | sort | grep -v '1 ' | awk '{print $2}' | xargs -I {} grep {} _l11_rklist.txt | grep -v Pass | wc -l)

printf "%s\t%s\t%s\t%s\t%s\t%s\n" "FINL" $((TT-dup_rack)) $((PS-dup_rack)) $FA $RU "after dedup Pass $dup_rack, Fail $dup_fail" | tee -a _l11_statsd.txt
sleep 2

echo -e "\n-- not shipped rack" | tee -a _l11_statsd.txt
while read p; do
	grep $p shipped.txt &>/dev/null
	if [[ $? -ne 0 ]]; then
		grep $p _l11_rklist.txt
	fi
done <_l11_uniqrk.txt | sort -k 2 | tee -a _l11_statsd.txt
echo
echo | tee -a _l11_statsd.txt
sleep 2

# search current testing rack existing in archive
echo "-- current testing rack existing in archive:" $(cat _c_rk.txt | xargs -I {} grep {} _a_rk.txt | sort | uniq | wc -l)
cat _c_rk.txt | xargs -I {} grep {} _a_rk.txt | sort | uniq | cut -b 2- | tee _c_du.txt
echo

while read p; do
	search_sn $p | tee -a _l11_statsd.txt
done <_c_du.txt
