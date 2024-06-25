#!/bin/bash

cnf="apc-pdu.cnf"

pdu_ip=$(head -n 1 $cnf)
passwd=$(tail -n 1 $cnf)

printf "  energy/kWh    power/kW    appower/kVA    current/A    voltage/V\n"

while [ 1 ]
do
	/usr/bin/expect retrieve-pdu-status.exp $pdu_ip $passwd | tee _exp  &>/dev/null

	eng=`grep "devReading energy"  _exp -A 2 | tail -n 1 | awk '{print $1}'`
	pow=`grep "devReading power"   _exp -A 2 | tail -n 1 | awk '{print $1}'`
	app=`grep "devReading appower" _exp -A 2 | tail -n 1 | awk '{print $1}'`
	cur=`grep "phReading all current" _exp -A 2 | tail -n 1 | awk '{print $2}'`
	vtg=`grep "phReading all voltage" _exp -A 2 | tail -n 1 | awk '{print $2}'`

	printf "%8s     %8s      %8s       %8s     %8s\n" $eng  $pow  $app  $cur  $vtg

	rm -rf _exp
	sleep 10
done
