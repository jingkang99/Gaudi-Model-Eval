# sda or nvme0n1

RED='\033[0;31m'
YLW='\033[0;33m'
BLU='\033[0;34m'
GRN='\033[0;32m'
BCY='\033[1;36m'
CYA='\033[0;36m'
NCL='\033[0m'

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
	echo -e "\n  ${GRN}bash $0 [sdb|nvme1n1] [-current]${NCL}\n"
	exit 0
elif [[ ! "$1" =~ ^sd ]] && [[ ! "$1" =~ ^nv ]]; then
	echo  -e "\n  ${RED}please specify proper drive name, $1 invalid${NCL}\n"
	exit 1
fi

HD_NEW=$1
HDSIZE=$(lsblk | grep $HD_NEW | awk '{print $4}' | head -n 1)

echo -e "$BLU"
read -r -p "  Confirm to Backup Partitions on $HD_NEW - ${HDSIZE} (y/n)?" response
response=${response,,}
echo -e "$NCL"
if [[ $response =~ ^(y| ) ]] || [[ -z $response ]]; then
    echo "  continue ..."
else
	echo -e $NCL
    exit
fi

if [[ $HD_NEW =~ "sd" ]]; then
	PT1=${HD_NEW}1
	PT2=${HD_NEW}2
elif [[ $HD_NEW =~ "nvme" ]]; then
	PT1=${HD_NEW}p1
	PT2=${HD_NEW}p2
fi

echo -e "  work on ${PT1} ${PT2}"
echo -e "$CYA"

PWW=`pwd`
if [[ "$2" =~ current ]]; then
	echo "  back up current partitions"
	cd /boot/efi
	echo -e "  backup /boot/efi"
	tar czf ${PWW}/${PT1}.tgz *

	cd /
	echo -e "  backup /"
	tar cvzf ${PWW}/${PT2}.tgz /bin /boot/* /etc /lib /lib64 /mnt /opt/* /root/* /sbin /sox/* /usr/* /var/*

	cd ${PWW}
else
	rm -rf   ${PT1} ${PT2} &>/dev/null
	mkdir -p ${PT1} ${PT2}

	# mount source drive sdb1 and sdb2
	mount /dev/${PT1} ${PT1}
	mount /dev/${PT2} ${PT2}
	echo "  mounted"

	du -sh ${PT1} ${PT2} 

	cd ${PT1}
	echo -e "  backup /dev/${PT1}"
	tar czf ../${PT1}.tgz *

	cd -
	cd ${PT2}
	echo -e "  backup /dev/${PT2}"
	tar czf ../${PT2}.tgz *
	cd -
fi

echo
ls -l ${PT1}.tgz ${PT2}.tgz
