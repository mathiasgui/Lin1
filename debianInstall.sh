#! /bin/bash

apt update -y

# Configuration réseau
cat <<EOL > /etc/network/interfaces
# Interface ens33 WAN
allow-hotplug ens33
iface ens33 inet DHCP

# Interface ens34 LAN
auto ens34
iface ens34 inet static
address 10.10.10.11/24
dns-nameservers 10.10.10.11
EOL

hostnamectl set-hostname srv-lin1-01.lin1.local

cat <<EOL > /etc/resolv.conf
search lin1.local
nameserver 10.10.10.11
nameserver 1.1.1.1
EOL

systemctl restart networking.service
apt -y update && apt upgrade

# Configuration NAT
echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
sysctl -p /etc/sysctl.conf

apt install -y iptables
iptables -t nat -A POSTROUTING -o ens32 -j MASQUERADE

apt install -y iptables-persistent
/sbin/iptables-save > /etc/iptables/rules.v4

# Configuration DNS dnsmasq
apt -y install dnsmasq

cat <<EOL > /etc/dnsmasq.conf
address=/srv-lin1-01.lin1.local/srv-lin1-01/10.10.10.11
address=/srv-lin1-02.lin1.local/srv-lin1-02/10.10.10.22
address=/nas-lin1-01.lin1.local/nas-lin1-01/10.10.10.33

ptr-record=11.10.10.10.in-addr.arpa.,"srv-lin1-01"
ptr-record=22.10.10.10.in-addr.arpa.,"srv-lin1-02"
ptr-record=33.10.10.10.in-addr.arpa.,"nas-lin1-01"

domain=lin1.local
dhcp-authoritative
dhcp-leasefile=/tmp/dhcp.leases
read-ethers

# Scope DHCP
dhcp-range=10.10.10.110,10.10.10.119,12h

# Netmask
dhcp-option=1,255.255.255.0

# DNS
dhcp-option=6,10.10.10.11
# Route
dhcp-option=3,10.10.10.11

# Bind Interface LAN
interface=ens34
EOL

systemctl restart dnsmasq.service
