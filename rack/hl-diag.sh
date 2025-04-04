#!/bin/bash
# This script is provided by Habana Taiwan Software Team

LOGPATH="$HOME/habana-diag-log"
DATESTR=`date +%Y%m%d%H%M`

check_hl_packages()
{
    echo -e "Kernel Version:"
    uname -a
    echo -e "\nOS Version:"
    cat /etc/os-release
    echo -e "\nHabana packages:"
    dpkg -l | grep -i habana
    echo -e "\nOpenMPI packages:"
    dpkg -l | grep -i openmpi
    echo -e "\nMemory info:"
    cat /proc/meminfo
}

check_hl_smi()
{
    echo "Driver status:"
    for i in {0..7}; do echo  "accel$i: " `cat /sys/class/accel/accel$i/device/status` ; done
    echo "OAM map:"
    hl-smi -Q bus_id,module_id,serial -f csv
    echo "FW versions:"
    hl-smi --fw-version
    echo "Detail:"
    hl-smi -q
    echo "Internal port stats:"
    OAM_ADDR=`lspci | grep accel | awk '{print $1}'`
    for i in $OAM_ADDR; do
		echo "OAM $i"
		hl-smi -n link -i $i
    done

    echo "External port stats:"
    /opt/habanalabs/qual/gaudi3/bin/manage_network_ifs.sh --status
}


smc_dump_cpld()
{
    echo "UBB Pri CPLD dump"
    echo "     0   1   2   3   4   5   6   7   8   9   a   b   c   d   e   f"
    for i in {0..15}; do
	ROW=$(echo "obase=16;$i" | bc)
	echo -n "$ROW: "
	for j in {0..15}; do
	    ADDR=$(echo "obase=16;$((i*16+j))" | bc)
	    REG=`ipmitool raw 0x30 0x70 0xef 2 0xec 0x43 12 0x9e 1 0x$ADDR`
	    echo -n "$REG "
	done
	echo ""
    done

    for k in {0..3}; do
	echo "OAM $k CPLD dump"
	echo "     0   1   2   3   4   5   6   7   8   9   a   b   c   d   e   f"
	for i in {0..15}; do
	    ROW=$(echo "obase=16;$i" | bc)
	    echo -n "$ROW: "
	    for j in {0..15}; do
		ADDR=$(echo "obase=16;$((i*16+j))" | bc)
		REG=`ipmitool raw 0x30 0x70 0xef 2 0xe6 0x4$k 9 0x4a 1 0x$ADDR`
		echo -n "$REG "
	    done
	    echo ""
	done
    done

    for k in {0..3}; do
	echo "OAM $((k+4)) CPLD dump"
	echo "     0   1   2   3   4   5   6   7   8   9   a   b   c   d   e   f"
	for i in {0..15}; do
	    ROW=$(echo "obase=16;$i" | bc)
	    echo -n "$ROW: "
	    for j in {0..15}; do
		ADDR=$(echo "obase=16;$((i*16+j))" | bc)
		REG=`ipmitool raw 0x30 0x70 0xef 2 0xe6 0x4$k 11 0x4a 1 0x$ADDR`
		echo -n "$REG "
	    done
	    echo ""
	done
    done
}

dump_cpld()
{
    # Need to customized for customers
    echo "Dump UBB and OAM CPLD"
    smc_dump_cpld
}

oam_pci_speed()
{
    echo -e "\nOAM PCI Speed:"
    dev_list=`lspci -d 1da3: | awk -F' ' '{print $1}'`

    for dev_ in $dev_list; do
	sts=$(sudo lspci -s $dev_ -vv | grep "LnkSta:" | awk -F ':' '{print $2}')
	echo "---------------------------------------------------------------------------------"
	echo "[$dev_] (Habana device) PCIe link status: $sts"
	echo "parent ports:"
	tmp_bdf="0000:$dev_"
	while true; do
	    port=$(basename $(dirname $(readlink "/sys/bus/pci/devices/$tmp_bdf")))
	    div=$(echo $port | awk -F ':' '{print $1}' | cut -f1 -d"0")
	    if [ "$div" == "pci" ]; then
		break;
	    fi
	    sts=$(sudo lspci -s $port -vv | grep "LnkSta:" | awk -F ':' '{print $2}')
	    echo "[$port] (parent of $tmp_bdf) $sts"
	    tmp_bdf=$port
	done
    done
}

check_pci()
{
    PCI_STR=`lspci -vvv`
    NUM_OAMS=`echo "$PCI_STR" | grep accel | wc | awk '{print $1}'`

    if [ $NUM_OAMS -eq 0 ]; then
	echo "No OAM found!!"
	dump_cpld >& $LOGPATH/cpld-$DATESTR.log
	exit
    fi

    echo "There are $NUM_OAMS found in the system"
    echo  "$PCI_STR" | grep accel
    
    #oam_pci_speed

    echo "PCI detail:"
    echo "$PCI_STR"
}

capture_oam_uart()
{
    OAM_ADDR=`lspci | grep accel | awk '{print $1}'`
    for addr in $OAM_ADDR; do
        echo "Enable virtual console for $addr"
	pre=`echo $addr | awk -F: '{print $1}'`
        if [ $pre == "0000" ]; then
            hl-smi dmon -i $addr > $LOGPATH/hl-smi-tmp.log &
        else
            hl-smi dmon -i 0000:$addr > $LOGPATH/hl-smi-tmp.log &
        fi
        cat $LOGPATH/hl-smi-tmp.log
        oam=`hl-smi -Q bus_id,module_id -f csv | grep $addr | awk '{print $2}'`
        PTS=`cat $LOGPATH/hl-smi-tmp.log | grep "ARC1" | awk -F: '{print $2}'`
        case $oam in
            ''|*[!0-9]*)
                echo "Log $addr virtual console from $PTS"
                cat $PTS > $LOGPATH/OAM-$addr-UART-$DATESTR.log&
                ;;
            *)
                echo "Log OAM $oam virtual console from $PTS"
                cat $PTS > $LOGPATH/OAM$oam-$addr-UART-$DATESTR.log&
                ;;
        esac
	rm $LOGPATH/hl-smi-tmp.log
    done

    echo "Unload driver to capture OAM UART LOG"
    rmmod habanalabs
    rmmod habanalabs_en
    rmmod habanalabs_cn
    rmmod habanalabs_ib
    echo "Reset OAM to capture OAM UART LOG"
    for addr in $OAM_ADDR; do
	hl-fw-loader -R -y -d $addr
    done
    echo "Load driver to capture OAM UART LOG"
    modprobe habanalabs_en
    modprobe habanalabs_cn
    modprobe habanalabs_ib
    modprobe habanalabs

    echo "Stop capturing the OAM UART log"
    CATS=`ps auxw |grep cat | grep "dev/pts" | awk '{print $2}'`
    for i in $CATS; do
	kill -9 $i
    done
    
    killall -9 hl-smi
}

run()
{
    echo "Collecting package information..."
    check_hl_packages >& $LOGPATH/hl-packages-$DATESTR.log
    echo "Collecting PCI information..."
    check_pci >& $LOGPATH/pci-$DATESTR.log
    echo "Dump CPLD..."
    dump_cpld >& $LOGPATH/cpld-$DATESTR.log
    echo "Load drivers..."
    modprobe habanalabs_en
    modprobe habanalabs_cn
    modprobe habanalabs_ib
    modprobe habanalabs
    echo "Slepp 30 seconds..."
    sleep 30
    echo "Collecting hl-smi logs..."
    check_hl_smi >& $LOGPATH/hl-smi-$DATESTR.log
    echo "Start capture OAM UART log and reset the OAM before hl_qual start."
    echo "This will take a while, please wait..."
    capture_oam_uart >& $LOGPATH/capture-uart-$DATESTR.log
    echo "Collect dmesg log..."
    dmesg > $LOGPATH/dmesg-$DATESTR.log
}

rm -rf $LOGPATH
mkdir -p $LOGPATH

echo -e "\n********************************************" | tee -a $LOGPATH/myversion-$DATESTR.log
echo "*" | tee -a $LOGPATH/myversion-$DATESTR.log
echo "* Intel Habana log collector. Version: 20241220" | tee -a $LOGPATH/myversion-$DATESTR.log
echo "*" | tee -a $LOGPATH/myversion-$DATESTR.log
echo -e "********************************************\n" | tee -a $LOGPATH/myversion-$DATESTR.log

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit
fi

run

tar jcf $HOME/hl-diag-log-$DATESTR.tar.bz2 $LOGPATH
rm -rf $LOGPATH
echo -e "\n********************************************"
echo "* Finished"
echo -e "********************************************\n"
echo -e "Please send $HOME/hl-diag-log-$DATESTR.tar.bz2 to Habana team for analysis\n\n"
