#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("initver[2022-05-21T12:39:05+08:00]:mini.sh")
################################################################################
source ${DIRNAME}/os_debian_init.sh

chroot ${DIRNAME}/buildroot/ /bin/bash -s <<EOF
    debian_minimum_init
EOF
macaddr=
case "$(cat ${DIRNAME}/buildroot/etc/hostname)" in
    s905d2) macaddr=b8:be:ef:90:5d:02;;
    s905d3) macaddr=b8:be:ef:90:5d:03;;
    *)      macaddr=b8:be:ef:90:5d:99;;
esac
cat << EOF > ${DIRNAME}/buildroot/etc/hosts
127.0.0.1       localhost $(cat ${DIRNAME}/buildroot/etc/hostname)
EOF
sed -i "s/^macaddr=.*/macaddr=${macaddr}/g" ${DIRNAME}/buildroot/usr/lib/firmware/brcm/brcmfmac43455-sdio.txt
grep "^macaddr=" ${DIRNAME}/buildroot/usr/lib/firmware/brcm/brcmfmac43455-sdio.txt
echo "rsync -avzP --numeric-ids -e 'ssh -p60022' --exclude=boot --delete ${DIRNAME}/buildroot/* root@192.168.168.IP:/overlay/lower/"
echo "rsync -avzP --numeric-ids -e 'ssh -p60022' --delete ${DIRNAME}/buildroot/boot/* root@192.168.168.IP:/boot/"