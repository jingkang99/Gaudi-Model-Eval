# sda or nvme0n1

RED='\033[0;31m'
YLW='\033[0;33m'
BLU='\033[0;34m'
GRN='\033[0;32m'
BCY='\033[1;36m'
CYA='\033[0;36m'
NCL='\033[0m' 

# ------------------------- create partitions

HD_NEW=$1
HDSIZE=$(lsblk | grep $HD_NEW | awk '{print $4}' | head -n 1)

echo -e "$YLW"
read -r -p "  Confirm to Create Partitions on $HD_NEW - ${HDSIZE} (y/n)?" response
response=${response,,}
echo -e "$NCL"
if [[ $response =~ ^(y| ) ]] || [[ -z $response ]]; then
    echo "  continue ..."
else
    exit
fi

SECONDS=0
HD_DEV=/dev/${HD_NEW}

if [[ $HD_NEW =~ "sd" ]]; then
	PT1=${HD_NEW}1
	PT2=${HD_NEW}2
	PT3=${HD_NEW}3
elif [[ $HD_NEW =~ "nvme" ]]; then
	PT1=${HD_NEW}p1
	PT2=${HD_NEW}p2
	PT3=${HD_NEW}p3
fi
echo -e "  work on ${PT1} ${PT2}"
echo -e "$CYA"

# delete all partitions
# dd if=/dev/zero of=${HD_DEV} bs=512 count=1
wipefs -a ${HD_DEV}
echo "  delete all partitions"
sync; sleep 1

# create partition table
parted -s ${HD_DEV} mklabel gpt
echo "  create partition table"

# create 1st partition for uefi
parted -s ${HD_DEV} mkpart primary fat32 1      200
echo "  create partition: uefi"

if [[ $HD_NEW =~ "sd" ]]; then
	# on usb create a 3rd partition for Windows
	parted -s ${HD_DEV} mkpart primary ext4  200    10240
	parted -s ${HD_DEV} mkpart primary ntfs  10240  100%
elif [[ $HD_NEW =~ "nvme" ]]; then
	parted -s ${HD_DEV} mkpart primary ext4  200    100%
fi
echo "  create partition: /"
sync; sleep 1

parted -s ${HD_DEV} set 1 boot on
echo "  set boot flag"
sync; sleep 1

mkfs.fat /dev/${PT1}
echo -e  "  mkfs.fat /dev/${PT1}"
sync; sleep 1

mkfs.ext4 /dev/${PT2}
echo -e  "  mkfs.ext4 /dev/${PT2}"
sync; sleep 1

[[ $HD_NEW =~ "sd" ]] && mkfs.ntfs /dev/${PT3}

parted -s ${HD_DEV} print
echo -e "$NCL"

# ------------------------- restore data
#
[[ ! -f sdb1.tgz ]] && exit 1
[[ ! -f sdb2.tgz ]] && exit 1

rm -rf   ${PT1} ${PT2} 
mkdir -p ${PT1} ${PT2}

echo -e "  mount ${PT1} ${PT2}"
mount /dev/${PT1} ${PT1}
mount /dev/${PT2} ${PT2}

echo -e "  untar to  ${PT1}"
tar xzf sdb1.tgz -C ${PT1}

echo -e "  untar to  ${PT2}"
tar xzf sdb2.tgz -C ${PT2}

mkdir -p ${PT2}/proc ${PT2}/run ${PT2}/sys ${PT2}/dev ${PT2}/srv ${PT2}/tmp
chmod 777 ${PT2}/tmp
echo

lsblk -f ${HD_DEV}
echo
sync;sync
# took 14m on usb

echo -e "${BCY}"
cat ${PT1}/EFI/ubuntu/grub.cfg
echo -e "${BLU}"
cat ${PT2}/boot/grub/x86_64-efi/load.cfg
echo -e "${BCY}"
cat ${PT2}/etc/fstab | grep -v ^#
echo
echo -e "${NCL}"

UUID_O1=$(grep ^UUID.*efi ${PT2}/etc/fstab | awk '{print $1}' | awk -F= '{print $2}')
UUID_O2=$(head -n 1 ${PT1}/EFI/ubuntu/grub.cfg | awk '{print $2}')
echo -e "  UUID_O1  $UUID_O1"
echo -e "  UUID_O2  $UUID_O2"
echo

# get id from 
UUID_N1=$(lsblk -f | grep ${PT1} | awk '{print $4}')
UUID_N2=$(lsblk -f | grep ${PT2} | awk '{print $4}')
echo -e "  UUID_N1  $UUID_N1"
echo -e "  UUID_N2  $UUID_N2"
echo

sed -i "s/${UUID_O2}/${UUID_N2}/g" ${PT1}/EFI/ubuntu/grub.cfg
sed -i "s/${UUID_O2}/${UUID_N2}/g" ${PT2}/boot/grub/x86_64-efi/load.cfg
sed -i "s/${UUID_O2}/${UUID_N2}/g" ${PT2}/boot/grub/grub.cfg

sed -i "s/${UUID_O2}/${UUID_N2}/g" ${PT2}/etc/fstab
sed -i "s/${UUID_O1}/${UUID_N1}/g" ${PT2}/etc/fstab

if [[ $HD_NEW =~ "sd" ]]; then
	UUID_O3=$(grep ^UUID.*ntf ${PT2}/etc/fstab | awk '{print $1}' | awk -F= '{print $2}')
	UUID_N3=$(lsblk -f | grep ${PT3} | awk '{print $3}')
	sed -i "s/${UUID_O3}/${UUID_N3}/g" ${PT2}/etc/fstab
	echo -e "  $UUID_O3 -> $UUID_N3"
fi

# checking
grep $UUID_N2 ${PT1}/EFI/ubuntu/grub.cfg >/dev/null
[[ $? -eq 0 ]] && echo "  grub.cfg  OK!" || echo "ERR"

grep $UUID_N2 ${PT2}/boot/grub/x86_64-efi/load.cfg >/dev/null
[[ $? -eq 0 ]] && echo "  load.cf   OK!" || echo "ERR"

grep $UUID_N2 ${PT2}/boot/grub/grub.cfg >/dev/null
[[ $? -eq 0 ]] && echo "  grub.grub OK!" || echo "ERR"

grep $UUID_N2 ${PT2}/etc/fstab >/dev/null
[[ $? -eq 0 ]] && echo "  fstabg    OK!" || echo "ERR"
grep $UUID_N1 ${PT2}/etc/fstab >/dev/null
[[ $? -eq 0 ]] && echo "  fstab/    OK!" || echo "ERR"

umount ${PT1}
umount ${PT2}
sync;sync

fsck -f /dev/${PT1}
fsck -f /dev/${PT2}

echo -e "\n$CYA  patitions restored on ${HD_NEW} in ${SECONDS}s\n$NCL"
