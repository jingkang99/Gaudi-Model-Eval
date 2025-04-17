alias gdl='tail -n 1 /var/log/habana_logs/qual/*.log  | grep -v == | grep .'

export GREP_COLORS='ms=01;33'
export __python_cmd=python3
GAUD=gaudi2

function check_hl_qual_log(){
	SUMMARY=''
	for f in $(ls /var/log/habana_logs/qual/*.log); do
		RESULT=$(tail -n 1   $f)
		COMMDQ=$(grep \.\/hl $f)
		echo -e "$RESULT    $COMMDQ"
		if [[ $RESULT =~ "FAILED" ]]; then
			SUMMARY+="retest    ${f}    $COMMDQ\n"
		fi
	done
	echo -e "\n"${SUMMARY}
}

if [[ "$1" == "log" ]]; then
	check_hl_qual_log
	exit 0
fi

lspci | grep --color -P "accelerators.*1020"
if [[ $? != 0 ]]; then
  # for RH
  lspci | grep --color -P "accelerators.*Gaudi2"
fi

if [[ $? == 0 ]]; then
    SECONDS=0
    echo -e " \n  hl_qual tests on ${GAUD}"

    rmmod habanalabs
    modprobe habanalabs timeout_locked=0

    rm -rf /var/log/habana_logs/qual/*.log

    cd /opt/habanalabs/qual/${GAUD}/bin
    ./manage_network_ifs.sh --up
    ./manage_network_ifs.sh --status

    ./hl_qual -${GAUD} -rmod parallel -c all -t 240 -f2 -l extreme -serdes int
    ./hl_qual -${GAUD} -rmod parallel -c all -t 240 -f2 -l extreme
    ./hl_qual -${GAUD} -rmod parallel -c all -t 240 -f2 -l high
    ./hl_qual -${GAUD} -rmod parallel -c all -t 240 -f2
    ./hl_qual -${GAUD} -rmod parallel -c all -t 240 -s
    ./hl_qual -${GAUD} -rmod parallel -c all -t 240 -p -b -gen gen4
    ./hl_qual -${GAUD} -rmod parallel -c all -t 240 -e2e_concurrency -disable_ports 8,22,23
    ./hl_qual -${GAUD} -rmod parallel -c all -mb -memOnly
    ./hl_qual -${GAUD} -rmod parallel -c all -ser
    ./hl_qual -${GAUD} -rmod parallel -c all -i 3 -full_hbm_data_check_test
    ./hl_qual -${GAUD} -rmod parallel -c all -i 3 -hbm_dma_stress
    ./hl_qual -${GAUD} -rmod parallel -c all -i 3 -hbm_tpc_stress

    ./hl_qual -${GAUD} -rmod parallel -c all -t 240 -e -Tw 1 -Ts 2 -sync -enable_ports_check int
    ./hl_qual -${GAUD} -rmod parallel -c all -t 240 -s -enable_ports_check int -l extreme -sensors 10 -toggle

    ./hl_qual -${GAUD} -rmod parallel -c all -nic_base -enable_ports_check int -i 100 -sensors 10 -ep 50 -sz 134217728 -test_type allreduce
    ./hl_qual -${GAUD} -rmod parallel -c all -nic_base -enable_ports_check int -i 100 -sensors 10 -ep 50 -sz 134217728 -test_type allgather

    ./hl_qual -${GAUD} -rmod parallel -c all -nic_base -enable_ports_check int -i 100 -sensors 10 -sz 134217728 -toggle -test_type pairs
    ./hl_qual -${GAUD} -rmod parallel -c all -nic_base -enable_ports_check int -i 100 -sensors 10 -sz 134217728 -toggle -test_type allreduce
    ./hl_qual -${GAUD} -rmod parallel -c all -nic_base -enable_ports_check int -i 100 -sensors 10 -sz 134217728 -toggle -test_type allgather
    ./hl_qual -${GAUD} -rmod parallel -c all -nic_base -enable_ports_check int -i 100 -sensors 10 -sz 134217728 -toggle -test_type bandwidth
    ./hl_qual -${GAUD} -rmod parallel -c all -nic_base -enable_ports_check int -i 100 -sensors 10 -sz 134217728 -toggle -test_type dir_bw
    ./hl_qual -${GAUD} -rmod parallel -c all -nic_base -enable_ports_check int -i 100 -sensors 10 -sz 134217728 -toggle -test_type loopback

    echo
    echo -e "  tested in $SECONDS seconds"
else
    echo "  this is NOT a gaudi2 server"
fi

cd -

