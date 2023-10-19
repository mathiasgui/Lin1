#! /bin/bash

# Installation sous Debian 12

# sudo -s
# apt update -y && apt install git -y
# git clone https://github.com/mathiasgui/Lin1.git
# chmod +x Lin1/srv-lin1-01.sh && Lin1/srv-lin1-01.sh

# Interface réseau WAN
WAN_NIC=$(ip -o -4 route show to default | awk '{print $5}')

# Interface réseau LAN
LAN_NIC=$(ip link | awk -F: '$0 !~ "lo|vir|wl|^[^0-9]"{print $2a;getline}' | grep -v $WAN_NIC)

IPMASK='255.255.255.0'
DOMAIN='lin1.local'
DNSIPADDRESS='10.10.10.11'

SRV01='srv-lin1-01'
SRV02='srv-lin1-02'
SRV03='nas-lin1-01'

IPSRV01='10.10.10.11'
IPSRV02='10.10.10.22'
IPSRV03='10.10.10.33'

# IPREVSRV01 --> IP for reverse search
IFS='.' read -ra octets <<< "$IPSRV01"
for ((i=${#octets[@]}-1; i>=0; i--)); do
  IPREVSRV01+="${octets[i]}"
  if [[ $i -gt 0 ]]; then
    IPREVSRV01+="."
  fi
done

# IPREVSRV02 --> IP for reverse search
IFS='.' read -ra octets <<< "$IPSRV02"
for ((i=${#octets[@]}-1; i>=0; i--)); do
  IPREVSRV02+="${octets[i]}"
  if [[ $i -gt 0 ]]; then
    IPREVSRV02+="."
  fi
done

# IPREVSRV03 --> IP for reverse search
IFS='.' read -ra octets <<< "$IPSRV03"
for ((i=${#octets[@]}-1; i>=0; i--)); do
  IPREVSRV03+="${octets[i]}"
  if [[ $i -gt 0 ]]; then
    IPREVSRV03+="."
  fi
done

DHCP_IPSTART='10.10.10.110'
DHCP_IPSTOP='10.10.10.119'

# En production le les identifiants ne serait pas configurer comme ceci ! 
LDAPPWD='Pa$$w0rd'
LdapAdminCNString='cn=admin,dc=lin1,dc=local'
LdapDCString='dc=lin1,dc=local'
OU='lin1'

######################################################################################
# Configure the network interfaces

net_FILE="/etc/network/interfaces"
cat <<EOM >$net_FILE

source /etc/network/interfaces.d/*

# The loopback network interface
auto lo
iface lo inet loopback

# The WAN network interface
auto $WAN_NIC
iface $WAN_NIC inet dhcp

# The LAN network interface
auto $LAN_NIC
iface $LAN_NIC inet static
address $IPSRV01
netmask $IPMASK

EOM

######################################################################################
# Prevent the DHCP client from rewriting the resolv.conf file
# remove options --> domain-name, domain-name-servers, domain-search, host-name

dhclient_FILE="/etc/dhcp/dhclient.conf"
cat <<EOM >$dhclient_FILE

option rfc3442-classless-static-routes code 121 = array of unsigned integer 8;

send host-name = gethostname();
request subnet-mask, broadcast-address, time-offset, routers,
        dhcp6.name-servers, dhcp6.domain-search, dhcp6.fqdn, dhcp6.sntp-servers,
        netbios-name-servers, netbios-scope, interface-mtu,
        rfc3442-classless-static-routes, ntp-servers;

EOM

######################################################################################
# Configure the hosts file

host_FILE="/etc/hosts"
cat <<EOM >$host_FILE

127.0.0.1       localhost
$IPSRV01       $SRV01.$DOMAIN

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
nameserver $IPSRV01
nameserver 1.1.1.1

EOM

######################################################################################
# Set the hostname

hostnamectl set-hostname $SRV01.$DOMAIN

######################################################################################
# Restart networking service, update and upgrade packages, and install OpenSSH server

systemctl restart networking.service
apt -y update && apt -y upgrade
apt install -y openssh-server

######################################################################################
# Enable IP forwarding and configure iptables for NAT

echo 'net.ipv4.ip_forward=1' > /etc/sysctl.conf
sysctl -p /etc/sysctl.conf

apt install -y iptables
iptables -t nat -A POSTROUTING -o $WAN_NIC -j MASQUERADE

# installation de iptables-persistent sans interaction

debconf-set-selections <<EOF
iptables-persistent iptables-persistent/autosave_v4 boolean true
iptables-persistent iptables-persistent/autosave_v6 boolean true
EOF

apt install -y iptables-persistent
/sbin/iptables-save > /etc/iptables/rules.v4

######################################################################################
# Install dnsmasq and configure it

apt -y install dnsmasq

dnsmasq_FILE="/etc/dnsmasq.conf"
cat <<EOM >$dnsmasq_FILE

address=/$SRV01.$DOMAIN/$SRV01/$IPSRV01
address=/$SRV02.$DOMAIN/$SRV02/$IPSRV02
address=/$SRV03.$DOMAIN/$SRV03/$IPSRV03

ptr-record=$IPREVSRV01.in-addr.arpa.,"$SRV01"
ptr-record=$IPREVSRV02.in-addr.arpa.,"$SRV02"
ptr-record=$IPREVSRV03.in-addr.arpa.,"$SRV03"

domain=$DOMAIN
dhcp-authoritative
dhcp-leasefile=/tmp/dhcp.leases
read-ethers

#Scope DHCP
dhcp-range=$DHCP_IPSTART,$DHCP_IPSTOP,12h

#Netmask
dhcp-option=1,$IPMASK

#DNS
dhcp-option=6,$DNSIPADDRESS

#Route
dhcp-option=3,$IPSRV01

#Bind Interface LAN
interface=$LAN_NIC

EOM

systemctl restart dnsmasq.service

######################################################################################
# Install OpenLDAP and configure it

echo -e " \ 
slapd slapd/password2 password $LDAPPWD
slapd slapd/password1 password $LDAPPWD
slapd slapd/move_old_database boolean true
slapd shared/organization string $OU
slapd slapd/no_configuration boolean false
slapd slapd/purge_database boolean false
slapd slapd/domain string $DOMAIN
" | debconf-set-selections

export DEBIAN_FRONTEND=noninteractive

sudo apt-get install -y slapd ldap-utils

LDAP_FILE_CONF="/etc/ldap/ldap.conf"
cat <<EOM >$LDAP_FILE_CONF

BASE    dc=lin1,dc=local
URI     ldap://$SRV01.$DOMAIN

EOM

######################################################################################
# Update Password OpenLDAP admin

# LDAP Server information
LDAP_SERVER="ldap://"$SRV01.$DOMAIN

# Generate LDIF file for modifying the root password
LDIF_FILE="modify_root_password.ldif"

echo "dn: ${LdapAdminCNString}
changetype: modify
replace: userPassword
userPassword: ${LDAPPWD}" > $LDIF_FILE

# Modify the root password using the LDIF file
ldapmodify -x -H "$LDAP_SERVER" -D "$LdapAdminCNString" -w "$LDAPPWD" -f $LDIF_FILE

# Clean up the LDIF file
rm $LDIF_FILE

######################################################################################
# Create Base, Groups and Users

mkdir /etc/ldap/content

LDAP_FILE="/etc/ldap/content/base.ldif"
cat <<EOM >$LDAP_FILE

dn: ou=users,dc=lin1,dc=local
objectClass: organizationalUnit
objectClass: top
ou: users

dn: ou=groups,dc=lin1,dc=local
objectClass: organizationalUnit
objectClass: top
ou: groups

EOM

LDAP_FILE="/etc/ldap/content/groups.ldif"
cat <<EOM >$LDAP_FILE

dn: cn=Managers,ou=groups,dc=lin1,dc=local
objectClass: top
objectClass: posixGroup
gidNumber: 20000

dn: cn=Ingenieurs,ou=groups,dc=lin1,dc=local
objectClass: top
objectClass: posixGroup
gidNumber: 20010

dn: cn=Devloppeurs,ou=groups,dc=lin1,dc=local
objectClass: top
objectClass: posixGroup
gidNumber: 20020

EOM

LDAP_FILE="/etc/ldap/content/users.ldif"
cat <<EOM >$LDAP_FILE

dn: uid=man1,ou=users,dc=lin1,dc=local
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
objectClass: person
uid: man1
userPassword: {crypt}x
cn: Man 1
givenName: Man
sn: 1
loginShell: /bin/bash
uidNumber: 10000
gidNumber: 20000
displayName: Man 1
homeDirectory: /home/man1
mail: man1@$DOMAIN
description: Man 1 account

dn: uid=man2,ou=users,dc=lin1,dc=local
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
objectClass: person
uid: man2
userPassword: {crypt}x
cn: Man 2
givenName: Man
sn: 2
loginShell: /bin/bash
uidNumber: 10001
gidNumber: 20000
displayName: Man 2
homeDirectory: /home/man1
mail: man2@$DOMAIN
description: Man 2 account

dn: uid=ing1,ou=users,dc=lin1,dc=local
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
objectClass: person
uid: ing1
userPassword: {crypt}x
cn: Ing 1
givenName: Ing
sn: 1
loginShell: /bin/bash
uidNumber: 10010
gidNumber: 20010
displayName: Ing 1
homeDirectory: /home/man1
mail: ing1@$DOMAIN
description: Ing 1 account

dn: uid=ing2,ou=users,dc=lin1,dc=local
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
objectClass: person
uid: ing2
userPassword: {crypt}x
cn: Ing 2
givenName: Ing
sn: 2
loginShell: /bin/bash
uidNumber: 10011
gidNumber: 20010
displayName: Ing 2
homeDirectory: /home/man1
mail: ing2@$DOMAIN
description: Ing 2 account

dn: uid=dev1,ou=users,dc=lin1,dc=local
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
objectClass: person
uid: dev1
userPassword: {crypt}x
cn: Dev 1
givenName: Dev
sn: 1
loginShell: /bin/bash
uidNumber: 10020
gidNumber: 20020
displayName: Dev 1
homeDirectory: /home/man1
mail: dev1@$DOMAIN
description: Dev 1 account

EOM

LDAP_FILE="/etc/ldap/content/addtogroup.ldif"
cat <<EOM >$LDAP_FILE

dn: cn=Managers,ou=groups,dc=lin1,dc=local
changetype: modify
add: memberuid
memberuid: man1

dn: cn=Managers,ou=groups,dc=lin1,dc=local
changetype: modify
add: memberuid
memberuid: man2

dn: cn=Ingenieurs,ou=groups,dc=lin1,dc=local
changetype: modify
add: memberuid
memberuid: ing1

dn: cn=Ingenieurs,ou=groups,dc=lin1,dc=local
changetype: modify
add: memberuid
memberuid: ing2

dn: cn=Devloppeurs,ou=groups,dc=lin1,dc=local
changetype: modify
add: memberuid
memberuid: dev1

EOM

ldapadd -x -D "$LdapAdminCNString" -f /etc/ldap/content/base.ldif -w $LDAPPWD

ldapadd -x -D "$LdapAdminCNString" -f /etc/ldap/content/users.ldif -w $LDAPPWD

ldappasswd -s "$LDAPPWD" -D "$LdapAdminCNString" -x "uid=man1,ou=users,dc=lin1,dc=local" -w $LDAPPWD
ldappasswd -s "$LDAPPWD" -D "$LdapAdminCNString" -x "uid=man2,ou=users,dc=lin1,dc=local" -w $LDAPPWD
ldappasswd -s "$LDAPPWD" -D "$LdapAdminCNString" -x "uid=ing1,ou=users,dc=lin1,dc=local" -w $LDAPPWD
ldappasswd -s "$LDAPPWD" -D "$LdapAdminCNString" -x "uid=ing2,ou=users,dc=lin1,dc=local" -w $LDAPPWD
ldappasswd -s "$LDAPPWD" -D "$LdapAdminCNString" -x "uid=dev1,ou=users,dc=lin1,dc=local" -w $LDAPPWD

ldapadd -x -D "$LdapAdminCNString" -f /etc/ldap/content/groups.ldif -w $LDAPPWD

ldapmodify -x -D "$LdapAdminCNString" -f /etc/ldap/content/addtogroup.ldif -w $LDAPPWD

ldapsearch -x -D "$LdapAdminCNString" -b "$LdapDCString" "(objectclass=*)" -w $LDAPPWD

######################################################################################
# Installation LDAP Account Manager 

apt install -y ldap-account-manager
apt install -f -y

echo "LDAP Account Manager has been successfully installed."
echo "You can access the application using the following address: http://IP/lam (the default password is 'lam')."

rm ldap-account-manager_8.4-1_all.deb

######################################################################################

rm -r Lin1/

