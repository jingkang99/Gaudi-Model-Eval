RED='\033[0;31m'
YLW='\033[0;33m'
BLU='\033[0;34m'
GRN='\033[0;32m'
BCY='\033[1;36m'
CYA='\033[0;36m'
NCL='\033[0m' 

echo -e "$YLW"
read -r -p "  Confirm to update OAM CPLD simultaneously using $1 (y/n)?" response
response=${response,,}
echo -e "$NCL"
if [[ $response =~ ^(y| ) ]] || [[ -z $response ]]; then
    echo "  Continue..."
else
    exit
fi

OAM_ID[0]=0000:ba:00.0
OAM_ID[1]=0000:cb:00.0
OAM_ID[2]=0000:a9:00.0
OAM_ID[3]=0000:2c:00.0
OAM_ID[4]=0000:17:00.0
OAM_ID[5]=0000:3d:00.0
OAM_ID[6]=0000:4e:00.0
OAM_ID[7]=0000:97:00.0

# gaudi3-cpld-LFMXO5-15D-HBN-HL325-04-TS67714C1D-production.itb
CPLD_FILE=$1

if [[ ! -f $CPLD_FILE ]]; then
	echo -e "  cannot find $CPLD_FILE"
	exit 1
fi

echo -e "  oam CPLD: $CPLD_FILE"
SECONDS=0
for (( i=1; i < 8; i++ )); do
    nohup hl-fw-loader -y -d ${OAM_ID[$i]} -f ${CPLD_FILE} &
done

sleep 1080
echo -e "\n${GRN}OAM CPLD updated in${NCL} ${YLW}${SECONDS}${NCL}${GRN} s${NCL}"

hl-smi -q | grep SPI 
echo
hl-smi -q | grep "CPLD Ver"
echo
hl-smi -L | grep "CPLD Version" -B 15 | grep -P "accel|Serial|SPI|CPLD"
