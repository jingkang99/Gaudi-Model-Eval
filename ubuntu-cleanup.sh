echo "stop services"
service snapd stop 	&>/dev/null
service fwupd stop	&>/dev/null
service polkit stop	&>/dev/null
service upower stop	&>/dev/null
service packagekit stop &>/dev/null
service cloud-init stop &>/dev/null
service cloud-init stop &>/dev/null

systemctl disable systemd-networkd.service &>/dev/null
systemctl disable systemd-networkd-wait-online.service &>/dev/null

apt remove unattended-upgrades

apt update
apt upgrade

echo "apt purge"
apt purge   -y cloud-init cloud-guest-utils snapd packagekit fwupd polkitd &>/dev/null

echo "apt install"
apt install -y cifs-utils binutils sysbench ipmitool expect sqlite3 postgresql-client toilet lrzsz unzip libboost-dev net-tools sysstat jq pdsh byobu ubuntu-drivers-common sshpass &>/dev/null

echo "clean up"
apt autoremove -y &>/dev/null
apt autoclean  -y &>/dev/null

mkdir -p bert-perf-result resnet-perf-result
