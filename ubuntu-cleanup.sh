service snapd stop 	&>/dev/null
service fwupd stop	&>/dev/null
service polkit stop	&>/dev/null
service upower stop	&>/dev/null
service packagekit stop &>/dev/null
service cloud-init stop &>/dev/null

apt purge   -y cloud-init cloud-guest-utils snapd packagekit fwupd polkitd

apt install -y ipmitool expect sqlite3 postgresql-client toilet lrzsz unzip libboost-dev net-tools sysstat jq

apt autoremove -y
apt autoclean  -y

mkdir -p bert-perf-result resnet-perf-result
