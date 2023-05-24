#!/bin/bash

for bridge in `ovs-vsctl list-br`
do
	ovs-vsctl del-br $bridge
done
