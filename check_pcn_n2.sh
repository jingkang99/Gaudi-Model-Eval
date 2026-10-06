WO="${1:-101000306994}"

CYA='\033[0;36m'
BCY='\033[1;36m'
RED='\033[0;31m'
NCL='\033[0m'

PARENT_COMMAND=$(ps -o comm= -p $PPID 2>/dev/null | awk '{print $1}')
if [[ "$PARENT_COMMAND" == *"python"* ]]; then
    #echo "Executed by a Python script."
    CYA=''
    BCY=''
    RED=''
    NCL=''
fi

echo
echo -e "WO#:" ${CYA}${WO}${NCL}
echo "PCN: 244-00-20260923-01"
echo """ ____   ___ ____   __    ___   ___ ____  _____        ___  _ 
|___ \ / _ \___ \ / /_  / _ \ / _ \___ \|___ /       / _ \/ |
  __) | | | |__) | '_ \| | | | (_) |__) | |_ \ _____| | | | |
 / __/| |_| / __/| (_) | |_| |\__, / __/ ___) |_____| |_| | |
|_____|\___/_____|\___/ \___/   /_/_____|____/       \___/|_|"""
echo

if [ ! -d "10.32.0.26/prodfile/FTU/${WO}" ]; then 
	wget -r -np http://10.32.0.26/prodfile/FTU/${WO}/ 2>/dev/null
fi

#ls -d 10.32.0.26/prodfile/FTU/${WO}/S*
echo

FIRST=0
for dir in 10.32.0.26/prodfile/FTU/${WO}/S*; do
	dir="${dir%/}"
	log=$(ls $dir/*.txt)

	if [ $FIRST -eq 0 ]; then
		grep "System model" $log
		grep "BIOS Date"    $log
		grep "IPMI Rev"     $log
		grep "CPLD:"         $log
		echo
		echo "9 mismatch MAC:  8 CX8,  1 ROT"
		echo "3 not detected SN: CX8 ROT MG6"
		echo
	fi
	FIRST=$((FIRST+1))

	echo -n "check $log"
	MAC=$(grep '#       #     # ### #######' $log -A 12 | grep AMAC | wc -l)
	AOM=$(grep '#       #     # ### #######' $log -A 12 | grep -E 'HA\w+ 0894.* HA\w+' | awk -F':' '{print $2}' | wc -w)

	PASS=${RED}FAIL${NCL}
	if [ "$MAC" -eq 9 ] && [ "$AOM" -eq 3 ]; then 
		PASS=${BCY}PASS${NCL}
	fi
	echo -e ": $PASS"
done
