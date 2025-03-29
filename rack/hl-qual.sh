alias gd3='cd /var/log/habana_logs/qual/;tail -n 1 *.log  | grep -v == | grep .'

GAUD=gaudi3
cd /opt/habanalabs/qual/${GAUD}/bin
./manage_network_ifs.sh --up
./manage_network_ifs.sh --status

rm -rf /var/log/habana_logs/qual/*.log

#f2
./hl_qual -gaudi3 -dis_mon -c all -rmod parallel -f2 -l extreme -t 300 -enable_serr 

#power-stress 5400
./hl_qual -gaudi3 -dis_mon -c all -rmod parallel -s -t 240

# 1200 
./hl_qual -gaudi3 -dis_mon -c all -rmod parallel -e -t 240 

#pci-bandwidth-gen
./hl_qual -gaudi3 -c all -dis_mon -rmod serial -t 20 -p -b

#edp 1200
./hl_qual -gaudi3 -dis_mon -c all -rmod parallel -e -t 240

#pci-bandwidth-serial
./hl_qual -gaudi3 -dis_mon -c all -rmod serial -t 20 -b -p

#hbm-tpc-stress
./hl_qual -gaudi3 -dis_mon -c all -rmod parallel -hbm_tpc_stress read -i 2

#hbm-dma-stress
./hl_qual -gaudi3 -dis_mon -c all -rmod parallel -i 2 -hbm_dma_stress

cd /var/log/habana_logs/qual/
tail -n 1 *.log  | grep -v == | grep .
