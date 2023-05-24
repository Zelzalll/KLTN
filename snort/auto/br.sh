#!/bin/sh

# ===================================
#	Change the following vars if need
# ===================================

if_1="eth0"
if_2="eth1"

#==========================================================================
#	CLI Argument Input(s)
#==========================================================================

while getopts "c:" flag
do
    case "${flag}" in
        c) container_name=${OPTARG};;
    esac
done

#==========================================================================
#	Env var
#==========================================================================

# ===================================
#	No change the following vars
# ===================================

br1_name="ovs-br1"
br2_name="ovs-br2"

# Interface of container OVS will bridge
container_if_1="eth10"
container_if_2="eth11"

stdout_file="./.stdout"
stderr_file="./.stderr"
stdout=""
stderr=""

# =========================================
#	Colors table
# =========================================

# Reset
Color_Off='\033[0m'       # Text Reset

# Regular Colors
Black='\033[0;30m'        # Black
Red='\033[0;31m'          # Red
Green='\033[0;32m'        # Green
Yellow='\033[0;33m'       # Yellow
Blue='\033[0;34m'         # Blue
Purple='\033[0;35m'       # Purple
Cyan='\033[0;36m'         # Cyan
White='\033[0;37m'        # White

# Bold
BBlack='\033[1;30m'       # Black
BRed='\033[1;31m'         # Red
BGreen='\033[1;32m'       # Green
BYellow='\033[1;33m'      # Yellow
BBlue='\033[1;34m'        # Blue
BPurple='\033[1;35m'      # Purple
BCyan='\033[1;36m'        # Cyan
BWhite='\033[1;37m'       # White

#==========================================================================
#	Function
#==========================================================================

function CreateBridgeExceptionHandling {
	bridge_name=$1
	list_bridge=`ovs-vsctl list-br`
	
	if grep -q "$bridge_name" <<< "$list_bridge"
	then
		echo -e "${BCyan}[i] ${Cyan}Bridge named ${BCyan}${bridge_name} ${Cyan}already exists.${Color_Off}"
	else
		ovs-vsctl add-br $bridge_name
		ifconfig $bridge_name up
	fi
}

function CreateBridge {
	CreateBridgeExceptionHandling $br1_name
	CreateBridgeExceptionHandling $br2_name
}

function AddPortOVSDOckerExceptionHandling {
	bridge_name=$1
	container_if=$2
	
	list_net_command_str="ls /sys/class/net"
	container_net_list="`docker exec -it $container_name $list_net_command_str`"
	
	if grep -q "$container_if" <<< "$container_net_list"
	then
		echo -e "${BCyan}[i] ${Cyan}Port already attached for ${BCyan}CONTAINER=${container_name} ${Cyan}and ${BCyan}INTERFACE=${container_if}${Color_Off}"
	else
		ovs-docker add-port $bridge_name $container_if $container_name
		echo -e "${BGreen}[✔] ${Green}Port INTERFACE=${container_if} is created for CONTAINER=${container_name} successfully.${Color_Off}"
	fi
}

function AddPortOVSDOcker {
	AddPortOVSDOckerExceptionHandling $br1_name $container_if_1
	AddPortOVSDOckerExceptionHandling $br2_name $container_if_2
}

function AddPortOVSHostExceptionHandling {
	bridge_name=$1
	port_name=$2
	list_port_of_bridge=`ovs-vsctl list-ports $bridge_name`
	
	if grep -q "$port_name" <<< "$list_port_of_bridge"
	then
		echo -e "${BCyan}[i] ${Cyan}A port named ${BCyan}${port_name} ${Cyan}already exists on bridge ${BCyan}${bridge_name}${Cyan}.${Color_Off}"
	else
		ovs-vsctl add-port $bridge_name $port_name
	fi
}

function AddPortOVSHost {
	AddPortOVSHostExceptionHandling $br1_name $if_1
	AddPortOVSHostExceptionHandling $br2_name $if_2
}

#==========================================================================
#	main
#	Begin the script
#==========================================================================

#	Create bridge #1 and bridge #2
CreateBridge
#	Add port ovs to docker container
AddPortOVSDOcker
#	Add host port to bridge
AddPortOVSHost
