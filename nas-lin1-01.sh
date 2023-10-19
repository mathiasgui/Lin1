#! /bin/bash

# Installation OnpenMediaVault

# sudo -s
# apt update -y && apt install git -y
# git clone https://github.com/mathiasgui/Lin1.git
# chmod +x Lin1/nas-lin1-01.sh && Lin1/nas-lin1-01.sh

# Interface réseau LAN
LAN_NIC=$(ip -o -4 route show to default | awk '{print $5}')

IPMASK='255.255.255.0'
DOMAIN='lin1.local'
DNSIPADDRESS='10.10.10.11'
GATEWAYIPADDRESS='10.10.10.11'

SRVNAME='nas-lin1-01'
IPSRV='10.10.10.33'

######################################################################################
# Configure the network interfaces

net_FILE="/etc/network/interfaces"
cat <<EOM >$net_FILE

source /etc/network/interfaces.d/*

# The loopback network interface
auto lo
iface lo inet loopback

# The LAN network interface
auto $LAN_NIC
iface $LAN_NIC inet static
address $IPSRV
netmask $IPMASK
gateway $GATEWAYIPADDRESS

EOM

######################################################################################
# Configure the hosts file

host_FILE="/etc/hosts"
cat <<EOM >$host_FILE

127.0.0.1       localhost
$IPSRV       $SRVNAME.$DOMAIN

# The following lines are desirable for IPv6 capable hosts
::1     localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters

EOM

######################################################################################
# Configure the resolv.conf file

resolve_FILE="/etc/resolv.conf"
cat <<EOM >$resolve_FILE

domain $DOMAIN
search $DOMAIN
nameserver $DNSIPADDRESS

EOM

######################################################################################
# Set the hostname

hostnamectl set-hostname $SRVNAME.$DOMAIN

######################################################################################
# Restart networking service, update and upgrade packages, and install OpenSSH server

systemctl restart networking.service
apt -y update && apt -y upgrade
apt install -y openssh-server

######################################################################################

rm -r Lin1/
reboot
