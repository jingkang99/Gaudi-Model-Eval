# JK, 9/24
# https://www.digitalocean.com/community/tutorials/how-to-install-and-use-docker-on-ubuntu-22-04

CODEN=$(grep UBUNTU_CODENAME /etc/os-release | awk -F'=' '{print $2}')

[[ $CODEN != 'jammy' ]] && { echo "OS not jammy";   exit 2; }

pgrep dockerd
[[ $? == 0 ]] && { echo "docker already installed"; exit 2; }

apt update

apt install apt-transport-https ca-certificates curl software-properties-common

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

apt update

apt-cache policy docker-ce

apt install docker-ce

systemctl status docker
