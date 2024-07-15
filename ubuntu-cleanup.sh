service snapd stop 
service fwupd stop
service polkit stop
service upower stop
service packagekit stop 
service cloud-init stop

apt purge -y cloud-init cloud-guest-utils snapd packagekit fwupd polkitd

apt autoremove -y
apt autoclean  -y
