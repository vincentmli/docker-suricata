#!/bin/bash

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

INTERFACE=$(echo $SURICATA_OPTIONS | sed -e 's/^.*af-packet=//g' -e 's/\s.*$//g')

#file in docker is read-only, can't change
#sed -i 's/interface:\s.*?/interface:\s$INTERFACE/' /etc/suricata/suricata-xdp.yaml

#not use exec to run suricata since we need to handle SIGTERM in entrypoint bash script
#to clean up the iptables SYNPROXY rules and unload syncookie_xdp program when container
#exit, for example docker stop <container>

prep_term()
{
    unset term_child_pid
    unset term_kill_needed
    trap 'handle_term' TERM INT
}

handle_term()
{
#use sleep to avoid potential race condition
    if [ "${term_child_pid}" ]; then
	for l in $(iptables -t raw -n -L --line-numbers | grep XDP | awk '{print $1}')
	do
		if [ ! -z $l ]; then
			iptables -t raw -D PREROUTING 1
			sleep 1
		fi
	done
	for l in $(iptables -n -L --line-numbers | grep XDP | awk '{print $1}')
	do
		if [ ! -z $l ]; then
			iptables -D INPUT 1
			sleep 1
		fi
	done
	iptables -D INPUT -i $INTERFACE -m state --state INVALID -j DROP
	xdp-loader unload $INTERFACE -a
	sleep 5
        kill -TERM "${term_child_pid}" 2>/dev/null
    else
        term_kill_needed="yes"
    fi
}

wait_term()
{
    term_child_pid=$!
    if [ "${term_kill_needed}" ]; then
        kill -TERM "${term_child_pid}" 2>/dev/null
    fi
    wait ${term_child_pid} 2>/dev/null
    trap - TERM INT
    wait ${term_child_pid} 2>/dev/null
}

prep_term

#start suricata in background
/usr/bin/suricata ${ARGS} ${SURICATA_OPTIONS} $@ &
sleep 30 

#check if syncookie_xdp is loaded and attached
prog_id=$(bpftool prog | grep syncookie_xdp | cut -d':' -f1)

if [ ! -z "$prog_id" ]; then
	sysctl -w net.ipv4.tcp_syncookies=2
	sysctl -w net.ipv4.tcp_timestamps=1
	sysctl -w net.netfilter.nf_conntrack_tcp_loose=0
	TCPOPTIONS="--mss4 1460 --mss6 1440 --wscale 7 --ttl 64"
	SYNPROXY="-m state --state INVALID,UNTRACKED -j SYNPROXY --sack-perm --timestamp --wscale 7 --mss 1460"
	CT="-j CT --notrack"
	RULE_COMMENT="-m comment --comment "XDPSYNPROXY""
	LINE=1

	for p in $(echo $SYNPROXY_PORTS | sed 's/,/ /')
	do
		iptables -t raw -I PREROUTING $LINE -i $INTERFACE $RULE_COMMENT -p tcp -m tcp --syn --dport $p $CT
		iptables -I INPUT $LINE -i $INTERFACE $RULE_COMMENT -p tcp -m tcp --dport $p $SYNPROXY
		((LINE=LINE+1))
	done

	iptables -t filter -A INPUT -i $INTERFACE -m state --state INVALID -j DROP
	xdp_synproxy --prog $prog_id $TCPOPTIONS --ports $SYNPROXY_PORTS
else
        echo "syncookie_xdp not attached!"
fi

wait_term
