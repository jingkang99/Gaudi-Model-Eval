# Query SPM by sysSN and update the FRU

SYSSN=$1	#S973606X5C21810	
BMCIP=$2	#172.30.100.104
BMCPW="${3:-ADMIN}"

echo "query spm for $SYSSN"

function query_spm() {
	curl -s 'http://172.31.0.200/bin/spm' \
	-H 'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7' \
	-H 'Accept-Language: en-US,en;q=0.9,zh-CN;q=0.8,zh;q=0.7' \
	-H 'Cache-Control: max-age=0' \
	-H 'Connection: keep-alive' \
	-H 'Content-Type: application/x-www-form-urlencoded' \
	-H 'Origin: http://172.31.0.200' \
	-H 'Referer: http://172.31.0.200/bin/spm' \
	-H 'Upgrade-Insecure-Requests: 1' \
	-H 'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/144.0.0.0 Safari/537.36' \
	--data-raw 'id='$1'&type=spm' \
	--insecure | tee "_"$1".html"
	lynx -dump "_"$1".html" | grep -P "Part Number\s+Serial Number" -A 500 \
	| grep -i "No Data Found on Sever" -B 500 | grep -v "No Data Found" \
	| tee "_"$1".txt" | awk '{print $2}' | tee "_"$1".col"
}

query_spm $SYSSN >/dev/null
echo

SPMFL="_"$SYSSN".txt"
CSESN=`grep CSE-MG401TS $SPMFL | awk '{print $2}'`
MBDSN=`grep MBD-X14DBG  $SPMFL | awk '{print $2}'`
CX8SN=`grep AOM-CX8-GP  $SPMFL | awk '{print $2}'`
DATEU=`date '+%Y/%m/%d %T'`

SKUPN="SYS-422GL-NR2-N1-OC018"
grep AOC-NIC-DSC2Q200 $SPMFL >/dev/null
if [ $? -eq 0 ]; then
	SKUPN="SYS-422GL-NR2-P1-OC018"
fi

echo $SKUPN  $CSESN  $MBDSN  $CX8SN  $DATEU

./MGXCX8_S_FNP_CXx_To_Low.sh $BMCIP ADMIN $BMCPW p04 set low >/dev/null

saa -i $BMCIP -u ADMIN -p $BMCPW -c ChangeFruInfo --item CP --value "CSE-MG401TS-RBNDFP-OC018"
saa -i $BMCIP -u ADMIN -p $BMCPW -c ChangeFruInfo --item CS --value $CSESN

saa -i $BMCIP -u ADMIN -p $BMCPW -c ChangeFruInfo --item BM  --value "Supermicro"
saa -i $BMCIP -u ADMIN -p $BMCPW -c ChangeFruInfo --item BPN --value "X14DBG-MAP"
saa -i $BMCIP -u ADMIN -p $BMCPW -c ChangeFruInfo --item BP  --value "MBD-X14DBG-MAP-OC018-P"
saa -i $BMCIP -u ADMIN -p $BMCPW -c ChangeFruInfo --item BS  --value $MBDSN

exe="saa -i $BMCIP -u ADMIN -p $BMCPW -c ChangeFruInfo --item BDT --value \"${DATEU}\""
echo "$exe"
eval "$exe"

saa -i $BMCIP -u ADMIN -p $BMCPW -c ChangeFruInfo --item BDT --value "$DATEU"

saa -i $BMCIP -u ADMIN -p $BMCPW -c ChangeFruInfo --item PM  --value "Supermicro"
saa -i $BMCIP -u ADMIN -p $BMCPW -c ChangeFruInfo --item PN  --value "Oracle MGX"
saa -i $BMCIP -u ADMIN -p $BMCPW -c ChangeFruInfo --item PPM --value $SKUPN
saa -i $BMCIP -u ADMIN -p $BMCPW -c ChangeFruInfo --item PS  --value $SYSSN

# ----- 
#update cx8 fru bin
./ModifyFRU -f FRU_AOM_CX8_GP402_OC018_V100_6.bin -s $CX8SN >/dev/null
#checking
./ModifyFRU -f FRU_AOM_CX8_GP402_OC018_V100_6.bin.new.${CX8SN} -c

#update cx8 fru remotely
./fru_cx8.sh FRU_AOM_CX8_GP402_OC018_V100_6.bin.new.${CX8SN} $BMCIP ADMIN $BMCPW >/dev/null

#enable FRU write protect
./MGXCX8_S_FNP_CXx_To_Low.sh $BMCIP ADMIN $BMCPW p04 set high >/dev/null