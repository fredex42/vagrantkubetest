#!/bin/bash

modprobe br_netfilter
swapoff -a

echo 1 > /proc/sys/net/ipv4/ip_forward
echo br_netfilter > /etc/modules-load.d/br_netfilter
sysctl -p
