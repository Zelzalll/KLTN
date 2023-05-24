#!/bin/bash

# --------------------------------------------------------------------------------------------------------------------------------
#	Env var. No make any change this vars.
# --------------------------------------------------------------------------------------------------------------------------------

# File vars
var_list_file="./var_list.txt"

# Worker 1
ipv4_worker1="`grep "ipv4_worker1" ${var_list_file} | cut -d : -f 2`"
user_worker1="`grep "user_worker1" ${var_list_file} | cut -d : -f 2`"
password_worker1="`grep "password_worker1" ${var_list_file} | cut -d : -f 2`"
hostname_worker1="`ssh -q $user_worker1@$ipv4_worker1 "hostname"`"

# Worker 2
ipv4_worker2="`grep "ipv4_worker2" ${var_list_file} | cut -d : -f 2`"
user_worker2="`grep "user_worker2" ${var_list_file} | cut -d : -f 2`"
password_worker2="`grep "password_worker2" ${var_list_file} | cut -d : -f 2`"
hostname_worker2="`ssh -q $user_worker2@$ipv4_worker2 "hostname"`"

# Service
service_name="`grep "service_name" ${var_list_file} | cut -d : -f 2`"
task_num="`grep "task_num" ${var_list_file} | cut -d : -f 2`"

# Script file(s)
bridge_script="`grep "bridge_script" ${var_list_file} | cut -d : -f 2`"

# Working dir when ssh to Worker node
workdir_in_worker="`grep "workdir_in_worker" ${var_list_file} | cut -d : -f 2`"

task_map_queue=()
task_map_current=()
# task_map_current constructor
#	task_map_current=(
#		"<service_name>:<i>:_"
#	)
for (( i=1; i<=$task_num; i++ ))
do
	task_map_current+=("$service_name.$i:_")
done

task_map_current_tmp_file="`grep "task_map_current_tmp_file" ${var_list_file} | cut -d : -f 2`"

# ------------------------------
#	Colors table
# ------------------------------

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

# ----------------------------------------------------------------
#	Function
# ----------------------------------------------------------------

#	Initial task_map_queue
#	<task name>:<task ID>
function AddRunningTaskToQueue {
	task_ID_array_raw=`docker service ps $service_name --filter desired-state=running -q --no-trunc`
	
	readarray -t task_ID_array <<< $task_ID_array_raw; IFS='';
	#declare -p task_ID_array;

	for (( i=1; i<=$task_num; i++ ))
	do
		task_name="${service_name}.${i}"
		task_ID="${task_ID_array[$(($i-1))]}"
		task_map_queue+=("${task_name}:${task_ID}")
	done
}

function BridgeForTask {
	task_name="$1"
	task_ID="$2"
	task_stt="$3"

	container_name="${task_name}.${task_ID}"
	node_which_task_running_in=`docker service ps $service_name --filter desired-state=running --filter name=$task_name --format "{{.Node}}"`

	ipv4=""
	user=""
	pw=""

	case $node_which_task_running_in in
	   "${hostname_worker1}")
		  ipv4=$ipv4_worker1
		  user=$user_worker1
		  pw=$password_worker1
		  ;;

	   "${hostname_worker2}")
		  ipv4=$ipv4_worker2
		  user=$user_worker2
		  pw=$password_worker2
		  ;;

	   *)
		  ipv4=""
		  user=""
		  pw=""
		  ;;
	esac
	
	# Bridge
	bridge_remote_command_str="bash ${workdir_in_worker}/${bridge_script} -c $container_name"
	echo -e "\n${BGreen}[+] ${Green}Task ${task_stt} is being bridged..${Color_Off}\n"
	ssh -q $user@$ipv4 -t -o StrictHostKeyChecking=no "
		sudo -S -i echo \"\" <<< \"${pw}\";
		sudo ${bridge_remote_command_str};
	"
}

#	Compare task_map_queue[i] with task_map_current[i].
#	Create bridge for task_map_queue[i] if compare result is "not same".
#	Update task_map_current[i].
function CompareAndAddBridgeToTaskQueue {
	for (( i=0; i<$task_num; i++ ))
	do
		if [ "${task_map_queue[$i]}" != "${task_map_current[$i]}" ]
		then
			# Bridge task_map_queue[i]
			task_name="${task_map_queue[$i]%%:*}"
			task_ID="${task_map_queue[$i]##*:}"
			BridgeForTask "${task_name}" "${task_ID}" "$(($i+1))"
			
			# Update task_map_current[i]
			# task_map_current[i] = task_map_queue[i] |OR| task_map_current[i] <- task_map_queue[i]
			task_map_current[$i]=${task_map_queue[$i]}
		fi
	done
	unset task_map_queue
}

function UpdateTaskCurrentToFile {
	: > ${task_map_current_tmp_file}
	for element in ${task_map_current[@]}
	do
		echo -e $element >> ${task_map_current_tmp_file}
	done
}

# ----------------------------------------------------------------
#	main
# ----------------------------------------------------------------

echo -e "Running auto bridge script.."

# Auto bridge
while :
do
	AddRunningTaskToQueue
	CompareAndAddBridgeToTaskQueue
	UpdateTaskCurrentToFile
	sleep 3
done
