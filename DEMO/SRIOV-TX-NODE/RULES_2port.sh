#!/bin/bash

local_ip1=10.10.10.10
local_ip2=20.20.20.20

remote_ip1=10.10.10.100
remote_ip2=20.20.20.200

bridge=br0
mac_repr1=ens1np0
mac_repr2=ens1np1

ifconfig ens1 mtu 9100

ovs-vsctl del-br ${bridge}
ovs-vsctl add-br ${bridge}

ovs-ofctl del-flows ${bridge}
## Tunnel ports, with key = flow
ovs-vsctl add-port ${bridge} tun0 -- set Interface tun0 type=vxlan options:local_ip=$local_ip1 options:remote_ip=$remote_ip1 options:key=flow ofport_request=1000
ovs-vsctl add-port ${bridge} tun1 -- set Interface tun1 type=vxlan options:local_ip=$local_ip2 options:remote_ip=$remote_ip2 options:key=flow ofport_request=1001

## VF representors
# Loop over all reprs

VF0=$(ip -d link show | grep -B 1 'pf0vf11 ' | awk '/: eth/ {print $2}'| tr -d ':') 
VF1=$(ip -d link show | grep -B 1 'pf0vf12 ' | awk '/: eth/ {print $2}'| tr -d ':')

ovs-vsctl add-port ${bridge} ${VF0} -- set Interface ${VF0} ofport_request=12
ifconfig ${VF0} up mtu 9100
ovs-vsctl add-port ${bridge} ${VF1} -- set Interface ${VF1} ofport_request=13
ifconfig ${VF1} up mtu 9100

## MAC representors
# NOTE: Here is how we will swap to a flat network, we just add these ports into
# the bridge instead of the tunnel ports above. Then drop the 'set_tunnel' actions
# from the rules below.
ifconfig $mac_repr1 $local_ip1/24 up mtu 9100
ifconfig $mac_repr2 $local_ip2/24 up mtu 9100


##########
# EGRESS #
##########

rm -f /tmp/flows.txt

for match_val in $(seq 1 16383); do
  echo "in_port=12,tcp,tcp_dst=$match_val,actions=set_tunnel:$match_val,output:1000" >> /tmp/flows.txt
#  echo "in_port=13,tcp,tcp_dst=$match_val,actions=set_tunnel:$match_val,output:1000" >> /tmp/flows.txt
done

for match_val in $(seq 16384 32767); do
#  echo "in_port=12,tcp,tcp_dst=$match_val,actions=set_tunnel:$match_val,output:1001" >> /tmp/flows.txt
  echo "in_port=13,tcp,tcp_dst=$match_val,actions=set_tunnel:$match_val,output:1001" >> /tmp/flows.txt
done


###########
# INGRESS #
###########

for match_val in $(seq 1 16383); do
  echo "in_port=1000,tun_id=$match_val,actions=12" >> /tmp/flows.txt
  echo "in_port=1001,tun_id=$match_val,actions=12" >> /tmp/flows.txt
done

for match_val in $(seq 16384 32767); do
  echo "in_port=1000,tun_id=$match_val,actions=13" >> /tmp/flows.txt
  echo "in_port=1001,tun_id=$match_val,actions=13" >> /tmp/flows.txt
done

ovs-ofctl replace-flows --bundle ${bridge} /tmp/flows.txt



