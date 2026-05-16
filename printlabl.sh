# use curl to send print commands
# bash printlabl.sh 8234291 10 "13/20 A/P"

printr="172.30.191.54"

RED='\033[0;31m'
YLW='\033[0;33m'
BLU='\033[0;34m'
GRN='\033[0;32m'
BCY='\033[1;36m'
CYA='\033[0;36m'
NCL='\033[0m' 

ora_pn["8209200"]="672042983179 CBL-CDAT-8209200-OC018"
ora_pn["8232688"]="672042982677 CBL-CDAT-8232688-OC018"
ora_pn["8232689"]="672042982684 CBL-CDAT-8232689-OC018"
ora_pn["8232690"]="672042982691 CBL-CDAT-8232690-OC018"
ora_pn["8232719"]="672042981762 CBL-CDAT-8232719-OC018"
ora_pn["8232720"]="672042982530 CBL-CDAT-8232720-OC018"
ora_pn["8232942"]="672042982585 CBL-CDAT-8232942-OC018"
ora_pn["8236716"]="672042983193 CBL-CUSB-1081Q-90J-OC018"
ora_pn["8232678"]="672042982554 CBL-MCIO-1218M5-OC018"
ora_pn["8234289"]="672042980529 CBL-MCIO-1220M5R-OC018"
ora_pn["8234290"]="672042982745 CBL-MCIO-1230M5-OC018"
ora_pn["8234291"]="672042982592 CBL-MCIO-1230M5R-OC018"
ora_pn["8234292"]="672042982561 CBL-MCIO-1233M5R-OC018"
ora_pn["8234295"]="672042982608 CBL-MCIO-1260M5-OC018"
ora_pn["8236715"]="672042984282 CBL-MCIO-1445AM5B1-OC08"
ora_pn["8234293"]="672042934836 CBL-MCIO-1445AM5RF"
ora_pn["8234296"]="672042982721 CBL-PWEX-0946Y-17-OC018"
ora_pn["8234297"]="672042982714 CBL-PWEX-1093-36-OC018"
ora_pn["8234304"]="672042982738 CBL-PWEX-1093-A0-OC018"
ora_pn["8234300"]="672042983186 CBL-PWEX-1316-60-OC018"
ora_pn["8232679"]="672042982615 CBL-PWEX-8232679-OC018"
ora_pn["8232703"]="672042982707 CBL-PWEX-8232703-OC018"
ora_pn["8232707"]="672042982752 CBL-PWEX-8232707-OC018"
ora_pn["8232708"]="672042982622 CBL-PWEX-8232708-OC018"
ora_pn["8232709"]="672042982639 CBL-PWEX-8232709-OC018"
ora_pn["8232710"]="672042982646 CBL-PWEX-8232710-OC018"
ora_pn["8232711"]="672042982653 CBL-PWEX-8232711-OC018"
ora_pn["8232713"]="672042982660 CBL-PWEX-8232713-OC018"

oracle="${1:-8209200}"	# Oracle PN
oarray=(${ora_pn["${oracle}"]}); 

counts="${2:-3}"
if [ $counts -gt 999 ]; then
	echo -e "${RED}limited to print up to 999 labels every hour${NCL}"
	exit
fi

upcstr="${oarray[0]}"	# UPC 
partnm="${oarray[1]}"	# SMC PN

todays=$(date +"%m/%y")
redate="${3:-${todays}}"

declare -A mons=([01]=1 [02]=2 [03]=3 [04]=4 [05]=5 [06]=6 [07]=7 [08]=8 [09]=9 [10]=A [11]=B [12]=C)
declare -A days=([01]=1 [02]=2 [03]=3 [04]=4 [05]=5 [06]=6 [07]=7 [08]=8 [09]=9 [10]=A
				 [11]=B [12]=C [13]=D [14]=E [15]=F [16]=G [17]=H [18]=I [19]=J [20]=K
				 [21]=L [22]=M [23]=N [24]=O [25]=P [26]=Q [27]=R [28]=S [29]=T [30]=U [31]=V )
declare -A hour=([01]=1 [02]=2 [03]=3 [04]=4 [05]=5 [06]=6 [07]=7 [08]=8 [09]=9 [10]=A
				 [11]=B [12]=C [13]=D [14]=E [15]=F [16]=G [17]=H [18]=I [19]=J [20]=K
				 [21]=L [22]=M [23]=N [24]=O )
declare -A year=([26]=X [27]=Y [28]=Z [29]=R [30]=S [31]=T)

todaymon=$(date +%m)
todayday=$(date +%d)
todayhou=$(date +%H)
todayyea=$(date +%y)

pre=${upcstr: -5}${year[$todayyea]}${mons[$todaymon]}${days[$todayday]}${hour[$todayhou]}

echo "  print for:" $inputo $upcstr $partnm $counts $redate $pre
echo

for (( i=${counts}; i >=1 ; i-- )); do
	seq=${pre}$(printf "%03d" ${i})
	printf "${BCY}${seq}${NCL}\n"

curl -s 'http://'${printr}':9100/' -m 3 \
  -H 'Accept: */*' \
  -H 'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36' \
  --data-raw $'^XA\n^PW380\n^LL200\n^CF0,19\n^BY1,2.5,24\n^FO28,48^BCN,24,N,N,N^FD'${upcstr}'^FS\n^FO25,82^FDUPC: '${upcstr}'^FS\n^FO25,106^FDSUPER MICRO COO:CHN^FS\n^FO25,130^FD'${partnm}'^FS\n^FO25,154^FDREV 1.0 '"${redate}"'^FS\n^FO25,178^FDSN: '${seq}'^FS\n^BY1,2.5,24\n^FO28,198^BCN,24,N,N,N^FD'${seq}'^FS\n^FO25,232^FDOracle PN: '${oracle}'^FS^XZ'

done

# example
e="
curl 'http://172.30.191.54:9100/' \
  -H 'Accept: */*' \
  -H 'Accept-Language: en-US,en;q=0.9,zh-CN;q=0.8,zh;q=0.7' \
  -H 'Connection: keep-alive' \
  -H 'Content-Type: text/plain' \
  -H 'Origin: http://10.18.67.144:3000' \
  -H 'Referer: http://10.18.67.144:3000/' \
  -H 'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36' \
  -m 5 \
  --data-raw $'^XA\n^PW380\n^LL200\n^CF0,19\n^BY1,2.5,24\n^FO28,48^BCN,24,N,N,N^FD'${upcstr}'^FS\n^FO25,82^FDUPC: '${upcstr}'^FS\n^FO25,106^FDSUPER MICRO COO:CHN^FS\n^FO25,130^FDCBL-MCIO-12MMM5-OC018^FS\n^FO25,154^FDREV 1.0 11/11^FS\n^FO25,178^FDSN: 826995E00063^FS\n^BY1,2.5,24\n^FO28,198^BCN,24,N,N,N^FD826995E00063^FS\n^XZ'
"
