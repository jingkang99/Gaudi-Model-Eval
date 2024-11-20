apt update
apt upgrade
export HABANALABS_VIRTUAL_DIR=/opt/python-llm
export PYTHON=/opt/python-llm/bin/python

mkdir /sox;cd /sox
git clone --depth=1  https://github.com/jingkang99/Gaudi-Model-Eval
cd Gaudi-Model-Eval
bash ubuntu-cleanup.sh 
cd
wget -nv https://vault.habana.ai/artifactory/gaudi-installer/1.18.0/habanalabs-installer.sh
chmod 700 habanalabs-installer.sh
./habanalabs-installer.sh install -t base
./habanalabs-installer.sh install -t dependencies
./habanalabs-installer.sh install -t pytorch --venv

