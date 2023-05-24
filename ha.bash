#!/bin/bash

# --------------------------------------------------------------------------------------------------------------------------------
#	Env var. No make any change this vars.
# --------------------------------------------------------------------------------------------------------------------------------

# Count var
count=0

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
run_snort_script="`grep "run_snort_script" ${var_list_file} | cut -d : -f 2`"

# Working dir when ssh to Worker node
workdir_in_worker="`grep "workdir_in_worker" ${var_list_file} | cut -d : -f 2`"

task_map_current_tmp_file="`grep "task_map_current_tmp_file" ${var_list_file} | cut -d : -f 2`"
task_map_current=()

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
function AddCurrentTasksFromFileToVar {
	unset task_map_current
	
	while ! [ -s ${task_map_current_tmp_file} ]	# The file is empty.
	do
		:
	done
	
	# The file is not-empty.
	while IFS= read -r line
	do
		task_map_current+=("${line}")
	done < "$task_map_current_tmp_file"
}

function RunSnort {
	task_name="${task_map_current[${count}]%%:*}"
	task_ID="${task_map_current[${count}]##*:}"
	task_stt="$(($count+1))"

	container_name="${task_name}.${task_ID}"
	ipv4=""
	user=""
	pw=""
	node_which_task_running_in=`docker service ps $service_name --filter desired-state=running --filter id=$task_ID --format "{{.Node}}"`

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
	
	# Run snort
	echo -e "${BGreen}[+] ${BYellow}Run A Task of ${service_name} service: ${container_name}.. ----------------------------------------------------${Color_Off}"
	run_snort_command_str="bash ${workdir_in_worker}/${run_snort_script} -c $container_name"
	remote_command_str="ssh -q $user@$ipv4 -t -o StrictHostKeyChecking=no \"
		sudo -S -i echo \"\" <<< \"${pw}\";
		sudo ${run_snort_command_str};
		bash;
		\"
	"
	gnome-terminal --title="TASK ${task_stt} : ${container_name}" -- bash -c "$remote_command_str;"
	echo -e "${BYellow}Done!${Color_Off}"
}

function KillTask {
	task_name="$1"
	task_ID="$2"
	container_name="${task_name}.${task_ID}"
	
	ipv4=""
	user=""
	pw=""
	node_which_task_running_in=`docker service ps $service_name --filter desired-state=running --filter id=$task_ID --format "{{.Node}}"`
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
	
	ssh -q $user@$ipv4 -t -o StrictHostKeyChecking=no "
		sudo -S -i echo \"\" <<< \"${pw}\";
		sudo docker stop ${container_name};
	"
}

function CheckSnortProcessIsRunning {
	task_name="$1"
	task_ID="$2"
	container_name="${task_name}.${task_ID}"
	
	# Check snort process of container/task is running or not
	ipv4=""
	user=""
	pw=""
	node_which_task_running_in=`docker service ps $service_name --filter desired-state=running --filter id=$task_ID --format "{{.Node}}"`
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
	
	snort_process_PID=`ssh -q $user@$ipv4 -t -o StrictHostKeyChecking=no -o ConnectTimeout=3 "
		sudo -S -i echo \"\" <<< \"${pw}\";
		sudo docker exec -t ${container_name} pidof snort;
		" | sed "1d"
	`
	
	if [ "${snort_process_PID}" != "" ]
	then
		echo "Snort process of task ${container_name} is running."
		return 1
	else
		echo "Snort process of task ${container_name} is dead."
		echo -e "${BGreen}[ ------------- Time start here ------------- ]${Color_Off}"
		# Process in Service task was detected is not running at this time.
		start2=`date +%s%N`	# Start Clock
		return 0
	fi
}

function CheckSnortTaskIsRunning {
	task_name="${task_map_current[${count}]%%:*}"
	task_ID="${task_map_current[${count}]##*:}"
	container_name="${task_name}.${task_ID}"
	
	#Check Container of Snort is shutdown or not
	check_snort_command_str="`docker service ps $service_name --filter id=${task_ID} | grep Shutdown`"
	while [ -z "$check_snort_command_str" ];
	do
		echo "${container_name} is running."
		CheckSnortProcessIsRunning "${task_name}" "${task_ID}"
		if [ $? -eq 0 ]
		then
			break
		fi
		sleep 3
		check_snort_command_str=`docker service ps $service_name --filter id=${task_ID} | grep Shutdown`
	done
	
	echo -e "Killing this task.."
	KillTask "${task_name}" "${task_ID}"
	echo -e "${container_name} is dead.\n"
}

# ----------------------------------------------------------------
#	main
# ----------------------------------------------------------------

echo -e "Running High Availability script..\n"
start1=`date +%s%N`	# Start Clock
AddCurrentTasksFromFileToVar
RunSnort
end1=`date +%s%N`	# End Clock
time=`bc <<< "scale=9;(${end1} - $start1)/(10^9)"`
echo -e "${BGreen}It takes ${time} second(s) to run first task service.${Color_Off}\n"

while :
do
	CheckSnortTaskIsRunning
	AddCurrentTasksFromFileToVar
	count=$((++count%${task_num}))
	RunSnort
	
	echo -e "${BGreen}[ ------------- Time stop here ------------- ] ${Color_Off}"
	# New service task is being run.
	end2=`date +%s%N`	# End Clock
	time=`bc <<< "scale=9;(${end2} - $start2)/(10^9)"`
	echo -e "${BGreen}It takes ${time} second(s) to run a new service task.${Color_Off}\n"
	
	sleep 3
done
