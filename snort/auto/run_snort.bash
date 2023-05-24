#!/bin/bash

while getopts "c:l:r:" flag
do
    case "${flag}" in
        c) container_name=${OPTARG};;
        l) container_if_1=${OPTARG};;
        r) container_if_2=${OPTARG};;
    esac
done

if [ -z "${container_if_1}" ]
then
    container_if_1="eth10"
fi

if [ -z "${container_if_2}" ]
then
    container_if_2="eth11"
fi

workdir_in_container="/opt/snort_volumes/"
config_file_path="${workdir_in_container}/snort.conf"
log_folder_path="${workdir_in_container}/log"
cmd="snort -c ${config_file_path} -l ${log_folder_path} -Q -i ${container_if_1}:${container_if_2} -v"
docker exec -it --user root --workdir ${workdir_in_container} ${container_name} bash -c "$cmd"
