#! /bin/sh

set -e

if [ "${TRACE}" != "" ]; then
    set -x
fi

for src in /etc/suricata.dist/*; do
    filename=$(basename ${src})
    dst="/etc/suricata/${filename}"
    if ! test -e "${dst}"; then
        echo "Creating ${dst}."
        cp -a "${src}" "${dst}"
    fi
done

#libxdp requires bpf fs mounted in container

mount bpffs /sys/fs/bpf -t bpf
mount  --make-shared /sys/fs/bpf

ARGS="-c /etc/suricata/suricata-xdp.yaml"

#set up iptables SYNPROXY rules for xdp synproxy protected ports
#xdp_synproxy add ports in allowed_ports map from xdp synproxy
# program id, but should be after suricata is started to get
# the program id.

sysctl -w net.ipv4.tcp_syncookies=2
sysctl -w net.ipv4.tcp_timestamps=1
sysctl -w net.netfilter.nf_conntrack_tcp_loose=0

SYNPROXY="-m state --state INVALID,UNTRACKED -j SYNPROXY --sack-perm --timestamp --wscale 7 --mss 1460"
CT="-j CT --notrack"

INTERFACE=$(echo $SURICATA_OPTIONS | sed -e 's/^.*af-packet=//g' -e 's/\s.*$//g')

for p in $(echo $SYNPROXY_PORTS)
do
     iptables -t raw -I PREROUTING -i $INTERFACE -p tcp -m tcp --syn --dport $p $CT
     iptables -t filter -A INPUT -i $INTERFACE -p tcp -m tcp --dport $p $SYNPROXY
done

iptables -t filter -A INPUT -i $INTERFACE -m state --state INVALID -j DROP

exec /usr/bin/suricata ${ARGS} ${SURICATA_OPTIONS} $@
