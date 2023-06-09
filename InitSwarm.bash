#!/bin/bash

# ==========================================================================
#	Local Env var
# ==========================================================================

#	Master
ipv4_master="`hostname -I | awk '{print $1}'`"

#	File var shared with other file(s)
config_file="./honeypot.conf"

#	Service
services_name="honeypots"
#replicas="`grep -i ":y" honeypot.conf | wc -l`"
#image="busybox"

#	Colors table
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

function InitSwarm {
	echo -e "${BGreen}[+] ${BYellow}Initing swarm.. ----------------------------------------------------${Color_Off}"
	command="sudo docker swarm init --advertise-addr=$ipv4_master"
	$command
}

function CreateServiceExceptionHandle {
	service_name=$1
	create_service_command_str=$2
	
	has_exist=`sudo docker service ls --filter name=$service_name --format "{{.Name}}"`
	if [ "$has_exist" == "$service_name" ]
	then
		echo -e "${BCyan}[i] ${Cyan}Service ${service_name} already exists.${Color_Off}\n"
	else
		$create_service_command_str
	fi
}

function CreateService {
	service_name="$1"
	replicas="$2"
	image="$3"
	image_tag="$4"
	
	echo -e "${BGreen}[+] ${BYellow}Service $service_name is being created.. ----------------------------------------------------${Color_Off}"
	create_service_command_str="sudo docker service create \
											--name $service_name \
											--replicas $replicas \
											-t $image:$image_tag"
	CreateServiceExceptionHandle "$service_name" "$create_service_command_str"
	#echo -e "${BGreen}[✔] ${Green}Service ${service_name} is created successfully.${Color_Off}\n"
}

function CreateServices {
	while IFS= read -r line
	do
		is_y="$(echo "$line" | cut -d ":" -f 5)"
  		if [ "$is_y" == "y" ] || [ "$is_y" == "Y" ]
  		then
  			service_name="$(echo "$line" | cut -d ":" -f 1)"
  			replicas="$(echo "$line" | cut -d ":" -f 2)"
  			image="$(echo "$line" | cut -d ":" -f 3)"
  			image_tag="$(echo "$line" | cut -d ":" -f 4)"
  			CreateService "$service_name" "$replicas" "$image" "$image_tag"
  		fi
	done < "$config_file"
}




#**************************************************************************************************
#**************************************************************************************************
#**************************************************************************************************
#	main
#**************************************************************************************************
#**************************************************************************************************
#**************************************************************************************************

sudo -S echo -e "\n" <<< "1"  

# Init docker swarm
InitSwarm

# Create service
CreateServices


