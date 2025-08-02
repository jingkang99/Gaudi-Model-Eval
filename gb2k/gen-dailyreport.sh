# generate 2 reports
# jk,  8/1/25

RED='\033[0;31m'
YLW='\033[0;33m'
BLU='\033[0;34m'
GRN='\033[0;32m'
BCY='\033[1;36m'
CYA='\033[0;36m'
NCL='\033[0m' 

SECONDS=0
ROOT='/home/spm/hl_qual_test_results/GB200-rBurnL10-Test'

read YYYY MM DD <<<$(date +'%Y %m %d')

BRGUP_RPT=${MM}${DD}-bringup
RBURN_L10=${MM}${DD}-l10test

echo -e "report folder: ${BLU}$BRGUP_RPT ${BCY}$RBURN_L10${NCL}"

cd $ROOT

node save-bgup-tests.js $BRGUP_RPT
echo

node save-rack-tests.js $RBURN_L10
echo

cd $ROOT/$BRGUP_RPT
bash $ROOT/bringup-summary.sh
echo "  bringup report done"
sleep 2

cd $ROOT/$RBURN_L10
bash $ROOT/rburn-l10-tests.sh
echo "  rack L10 report done"

cd $ROOT
echo -e "    ---- ${CYA} Bring-Up  Test Stats ${NCL}"
tail -n 33 $BRGUP_RPT/bup_report.txt
echo

echo -e "    ---- ${CYA} RBurn L10 Test Stats ${NCL}"
tail -n 20 $RBURN_L10/rbn_report.txt
echo
echo -e "done in ${CYA}${SECONDS}${NCL} on" `date`
echo
