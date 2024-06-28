#!/bin/bash

pdu_ip=${1-"172.24.189.15"}
passwd=${2-"smc123"}

printf "  energy/kWh    power/kW    appower/kVA    current/A    voltage/V    id-pdu\n"

# PDU ID in array, order not matter
declare -a pdu=(2 4 3 1)

while [ 1 ]
do
	/usr/bin/expect mon-pdu-status.exp $pdu_ip $passwd ${pdu[@]} | tee _exp &>/dev/null

	for  i in ${!pdu[@]}; do
		eng=`grep "devReading ${pdu[$i]}:energy"      _exp -A 2 | tail -n 1 | awk '{print $1}' | grep -v Usage`
		pow=`grep "phReading  ${pdu[$i]}:all power"   _exp -A 2 | tail -n 1 | awk '{print $2}' | grep -v phReading`
		app=`grep "phReading  ${pdu[$i]}:all appower" _exp -A 2 | tail -n 1 | awk '{print $2}' | grep -v phReading`
		cur=`grep "phReading  ${pdu[$i]}:all current" _exp -A 2 | tail -n 1 | awk '{print $2}' | grep -v phReading`
		vtg=`grep "phReading  ${pdu[$i]}:all voltage" _exp -A 2 | tail -n 1 | awk '{print $2}' | grep -v phReading`

		if [[ ! -z $eng ]]; then
			printf "%8s     %8s      %8s       %8s     %8s  %6s\n" $eng  $pow  $app  $cur  $vtg  ${pdu[$i]}
		fi
	done
	rm -rf _exp
	sleep 10
done

# Rack
#Inner PDU	   3     1 		 Gaudi3, upper rack
#Outer PDU 	2			4	 Gaudi3, lower rack
