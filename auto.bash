#!/bin/bash

# ==========================================================================
#	Local Env var
# ==========================================================================

# ===================================
#	Không sửa biến này nhưng phải đặt trên này
# ===================================

#	Manager
ipv4_manager="`hostname -I | awk '{print $1}'`"

#	File var shared with other file(s)
var_list_file="./var_list.txt"

# =================================== =================================== =================================== ===================================
#	Can change value of following vars if need
# =================================== =================================== =================================== ===================================

#	File Server
ipv4_node_share_volumes="$ipv4_manager"	# Filer Server is placed at the same with Manger node. If File Server placed at another mnachine, change this var

# ===================================
#	No change the follow vars
# ===================================

#	Shared volumes | File Server
user_samba="`grep "user_samba" ${var_list_file} | cut -d : -f 2`"
password_samba="`grep "password_samba" ${var_list_file} | cut -d : -f 2`"
shared_volumes_name="snort"
volumes_path_on_worker_host="/home/snort"
volumes_path_in_container="/opt/snort_volumes"

#	Worker 1
ipv4_worker1="`grep "ipv4_worker1" ${var_list_file} | cut -d : -f 2`"
user_worker1="`grep "user_worker1" ${var_list_file} | cut -d : -f 2`"
password_worker1="`grep "password_worker1" ${var_list_file} | cut -d : -f 2`"
hostname_worker1=`ssh -q $user_worker1@$ipv4_worker1 "hostname"`

#	Worker 2
ipv4_worker2="`grep "ipv4_worker2" ${var_list_file} | cut -d : -f 2`"
user_worker2="`grep "user_worker2" ${var_list_file} | cut -d : -f 2`"
password_worker2="`grep "password_worker2" ${var_list_file} | cut -d : -f 2`"
hostname_worker2=`ssh -q $user_worker2@$ipv4_worker2 "hostname"`

#	Script file(s)
auto_bridge_script="auto_bridge.bash"
high_available_script="ha.bash"

#	Exception handle file
stdout_file="`grep "stdout_file" ${var_list_file} | cut -d : -f 2`"
stderr_file="`grep "stderr_file" ${var_list_file} | cut -d : -f 2`"
stdout=""
stderr=""

#	Service
task_num="`grep "task_num" ${var_list_file} | cut -d : -f 2`"
service_name="`grep "service_name" ${var_list_file} | cut -d : -f 2`"
image_repo="azazelzal/snort_test"
tag="v2"
image="$image_repo:$tag"
workdir_inside_container="${volumes_path_in_container}"

# =========================================
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

function ConnectWorkersToSharedVolumes {
	user_node="$1"
	ipv4_node="$2"
	password_node="$3"
	
	echo -e "Checking shared volumes directory is exist or not.."
	if ! ssh -q ${user_node}@${ipv4_node} "ls ${volumes_path_on_worker_host}/.. | grep -q ${shared_volumes_name}"
	then
		echo -e "${BCyan}[i] ${Cyan}Directory is not existed. Creating new directory.${Color_Off}"
		ssh -q ${user_node}@${ipv4_node} -t -o StrictHostKeyChecking=no "sudo -S mkdir ${volumes_path_on_worker_host} <<< \"${password_node}\""
	else
		echo -e "${BCyan}[i] ${Cyan}Directory is existed.${Color_Off}"
	fi
	
	ssh -q ${user_node}@${ipv4_node} -t -o StrictHostKeyChecking=no "sudo -S mount -o user=${user_samba},password=${password_samba} //${ipv4_node_share_volumes}/${shared_volumes_name} ${volumes_path_on_worker_host} <<< \"${password_node}\"" 1>$stdout_file 2>$stderr_file

	stdout=`cat $stdout_file`
	stderr=`cat $stderr_file`
	
	if grep -q "mount error(16): Device or resource busy" <<< $stdout
	then
		echo -e "${BCyan}[i] ${Cyan}Volumes/File Server already shares ${BCyan}OR ${Cyan}This directory is being used by another ???.${Color_Off}"
	else
		echo -e "$stdout"
	fi
	echo -e "${stderr}"
}

function SetupSharedVolumes {
	# Worker node 1
	echo -e "${BGreen}[+] ${Green}Node ${hostname_worker1} is connecting to shared volumes.. ----------------------------------------------------${Color_Off}"
	ConnectWorkersToSharedVolumes "${user_worker1}" "${ipv4_worker1}" "${password_worker1}"
	
	# Worker node 2
	echo -e "${BGreen}[+] ${Green}Node ${hostname_worker2} is connecting to shared volumes.. ----------------------------------------------------${Color_Off}"
	ConnectWorkersToSharedVolumes "${user_worker2}" "${ipv4_worker2}" "${password_worker2}"
}

function InitSwarmExceptionHandling {
	command=$1
	$command 1>$stdout_file 2>$stderr_file

	stdout=`cat $stdout_file`
	stderr=`cat $stderr_file`
	
	already_exists_case="Error response from daemon: This node is already part of a swarm. Use \"docker swarm leave\" to leave this swarm and join another one."
	
	case $stderr in
		"")
			echo -e "${BGreen}[✔] ${Green}Swarm is created successfully.${Color_Off}\n"
		;;

		"$already_exists_case")
			echo -e "${BCyan}[i] ${Cyan}Swarm already exists. This node is already part of a swarm. Use \"docker swarm leave\" to leave this swarm and join another one.${Color_Off}\n"
		;;

		*)
			echo -e "${BRed}[ERROR] ${Red}${stderr}${Color_Off}\n"
		;;
	esac
}

function InitSwarm {
	command="docker swarm init --advertise-addr=$ipv4_manager"
	InitSwarmExceptionHandling "${command}"
}

function JoinAsWorkerExceptionHandling {
	user="$1"
	ipv4="$2"
	password="$3"
	
	join_as_worker_command_str="$(docker swarm join-token worker | grep "docker swarm join --token ")"
	
	success_case="This node joined a swarm as a worker."
	already_exists_case="Error response from daemon: This node is already part of a swarm. Use \"docker swarm leave\" to leave this swarm and join another one."

	ssh -q $user@$ipv4 -t -o StrictHostKeyChecking=no "sudo -S $join_as_worker_command_str <<< \"$password\"" 1>$stdout_file 2>$stderr_file
	
	stdout=`cat $stdout_file`
	stderr=`cat $stderr_file`
	
	case $stdout in
		*"${success_case}"*)
		   	echo -e "${BGreen}[✔] ${Green}${stdout}${Color_Off}\n"
		;;

		*"${already_exists_case}"*)
		   	echo -e "${BCyan}[i] ${Cyan}Node ${BCyan}${hostname_worker1} ${Cyan}is already part of a swarm. Use \"docker swarm leave\" to leave this swarm and join another one.${Color_Off}\n"
		;;

		*)
		   	if [ "$stderr" != "Connection to ${ipv4} closed." ]
			then
				echo -e "${BRed}[ERROR] ${Red}${stderr}${Color_Off}\n"
			fi
		;;
	esac
}

function JoinAsWorker {
	# Worker 1 node join as worker to Manager node
	echo -e "${BGreen}[+] ${Green}Node ${hostname_worker1} is joining.. ----------------------------------------------------${Color_Off}"
	JoinAsWorkerExceptionHandling "${user_worker1}" "${ipv4_worker1}" "${password_worker1}"
	
	# Worker 2 node join as worker to Manager node
	echo -e "${BGreen}[+] ${Green}Node ${hostname_worker2} is joining.. ----------------------------------------------------${Color_Off}"
	JoinAsWorkerExceptionHandling "${user_worker2}" "${ipv4_worker2}" "${password_worker2}"
}

function CreateServiceAndExceptionHandling {
	has_service_exist=`docker service ls --filter name=$service_name --format "{{.Name}}"`
	if [ "$has_service_exist" == "$service_name" ]
	then
		echo -e "${BCyan}[i] ${Cyan}Service ${service_name} already exists.${Color_Off}\n"
	else
		docker service create \
		--name $service_name \
		--replicas $task_num \
		--mount type=bind,source="${volumes_path_on_worker_host}",destination="${volumes_path_in_container}" \
		--workdir $workdir_inside_container \
		-t ${image}
		
		echo -e "${BGreen}[✔] ${Green}Service ${service_name} is created successfully.${Color_Off}\n"
	fi
}

#========================================================================== ==========================================================================
#	main
#========================================================================== ==========================================================================

# Setting up shared volumes (File Server) on Manager
echo -e "${BGreen}[+] ${BYellow}Setting up volumes.. ----------------------------------------------------${Color_Off}"
SetupSharedVolumes

# Init docker swarm
echo -e "${BGreen}[+] ${BYellow}Initing swarm.. ----------------------------------------------------${Color_Off}"
InitSwarm

# Make Worker join to swarm
echo -e "${BGreen}[+] ${BYellow}Worker joining.. ----------------------------------------------------${Color_Off}"
JoinAsWorker

# Drain Manager node
echo -e "${BGreen}[+] ${BYellow}Draining `hostname`.. ----------------------------------------------------${Color_Off}"
docker node update --availability drain `docker node ls --filter "role=manager" -q`

# Create service
echo -e "${BGreen}[+] ${BYellow}Service $service_name is being created.. ----------------------------------------------------${Color_Off}"
CreateServiceAndExceptionHandling

#==========================================================================
#	Auto bridge Task(s)/Container(s) which is created
#==========================================================================

echo -e "${BGreen}[+] ${BYellow}Auto scripts is running in new terminal.. ----------------------------------------------------${Color_Off}"
gnome-terminal --title="Auto updating task bridge" -- bash -c "bash ${auto_bridge_script}; bash;"
sleep 7
gnome-terminal --title="HA ensure.." -- bash -c "bash ${high_available_script}; bash;"
