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

mount bpffs /sys/fs/bpf -t bpf
mount  --make-shared /sys/fs/bpf

ARGS="-c /etc/suricata/suricata-xdp.yaml"

exec /usr/bin/suricata ${ARGS} ${SURICATA_OPTIONS} $@
