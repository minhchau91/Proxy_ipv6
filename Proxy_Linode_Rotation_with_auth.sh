#!/bin/sh
random() {
        tr </dev/urandom -dc A-Za-z0-9 | head -c5
        echo
}

array=(1 2 3 4 5 6 7 8 9 0 a b c d e f)
gen64() {
        ip64() {
                echo "${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}"
        }
        echo "$1:$(ip64):$(ip64):$(ip64):$(ip64)"
}

gen_3proxy() {
    cat <<EOF
daemon
maxconn 3000
nserver 1.1.1.1
nserver 1.0.0.1
nserver 2606:4700:4700::64
nserver 2606:4700:4700::6400
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
setgid 65535
setuid 65535
stacksize 6291456
flush
auth strong
users $(awk -F "|" 'BEGIN{ORS="";} {print $1 ":CL:" $2 " "}' ${WORKDATA})
$(awk -F "|" '{print "auth none\n" \
"allow " $1 "\n" \
"proxy -6 -n -a -p" $5 " -i" $4 " -e"$6"\n" \
"flush\n"}' ${WORKDATA})
EOF
}

gen_data() {
    seq $FIRST_PORT $LAST_PORT | while read port; do
        echo "$User|$Pass|$interface|$IP4|$port|$(gen64 $IP6)|$Prefix"
    done
}

gen_iptables() {
    cat <<EOF
    $(awk -F "|" '{print "/sbin/iptables -I INPUT -p tcp --dport " $5 "  -m state --state NEW -j ACCEPT"}' ${WORKDATA})
EOF
}

gen_ifconfig() {
    cat <<EOF
$(awk -F "|" '{print "/sbin/ifconfig " $3 " inet6 add " $6$7}' ${WORKDATA})
EOF
}
/sbin/service network restart
#/sbin/iptables -F INPUT
echo "installing apps"
rm -fv /usr/local/etc/3proxy/3proxy.cfg
rm -fv /home/proxy-installer/data.txt
rm -fv /home/proxy-installer/boot_iptables.sh
rm -fv /home/proxy-installer/boot_ifconfig.sh
echo "working folder = /home/proxy-installer"
WORKDIR="/home/proxy-installer"
WORKDATA="${WORKDIR}/data.txt"
WORKDATA2="${WORKDIR}/ipv6-subnet.txt"

#mkdir $WORKDIR && cd $_

IP4=$(curl -4 -s icanhazip.com)
IP6=$(awk -F "|" '{print $1}' ${WORKDATA2})
Prefix=$(awk -F "|" '{print $2}' ${WORKDATA2})
User=$(awk -F "|" '{print $3}' ${WORKDATA2})
Pass=$(awk -F "|" '{print $4}' ${WORKDATA2})

interface=$(ip addr show | awk '/inet.*brd/{print $NF}')
echo "Internal ip = ${IP4}. Exteranl sub for ip6 = ${IP6}"

FIRST_PORT=40000
LAST_PORT=40499

gen_data >$WORKDIR/data.txt
#gen_iptables >$WORKDIR/boot_iptables.sh
gen_ifconfig >$WORKDIR/boot_ifconfig.sh
chmod +x $WORKDIR/boot_*.sh /etc/rc.local

gen_3proxy >/usr/local/etc/3proxy/3proxy.cfg

rm -fv /etc/rc.local

cat >>/etc/rc.local <<EOF
touch /var/lock/subsys/local
systemctl start NetworkManager.service
ifup ${interface}
bash ${WORKDIR}/boot_ifconfig.sh
/usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg &
EOF

bash /etc/rc.local
/sbin/reboot
