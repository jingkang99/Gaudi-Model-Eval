service snapd stop 
service fwupd stop
service polkit stop
service upower stop
service packagekit stop 
service cloud-init stop

apt purge -y cloud-init cloud-guest-utils snapd packagekit fwupd polkitd

apt install -y ipmitool expect sqlite3 postgresql-client toilet lrzsz unzip libboost-dev net-tools

apt autoremove -y
apt autoclean  -y

