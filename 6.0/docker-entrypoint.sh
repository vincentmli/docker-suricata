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

ARGS=""

exec /usr/bin/suricata ${ARGS} ${SURICATA_OPTIONS} $@
