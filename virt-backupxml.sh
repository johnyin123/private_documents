#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [ "${DEBUG:=false}" = "true" ]; then
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || true
################################################################################
main() {
    #BJ PROD
    node="10.4.38.2 10.4.38.3 10.4.38.4 10.4.38.5 10.4.38.6 10.4.38.7 10.4.38.8 10.4.38.9 10.4.38.10 10.4.38.11 10.4.38.12 10.4.38.13  10.4.38.14 10.4.38.15"
    #DL XK/ZB
    node="$node 10.5.38.100 10.5.38.101 10.5.38.102 10.5.38.103 10.5.38.104 10.5.38.105 10.5.38.106 10.5.38.107"
    #BJ BIGDATA
    node="$node 10.3.60.2 10.3.60.3 10.3.60.4 10.3.60.5 10.3.60.6 10.3.60.7 10.3.60.8"
    for n in ${node}
    do
        rm -rf ${n}
        mkdir -p ${n}
        rsync -avzP -e "ssh -p60022" root@${n}:/etc/libvirt/qemu ${n} > /dev/null 2>&1
        echo "========================================================================"
        xml=$(virsh -c qemu+ssh://root@${n}:60022/system sysinfo)
        manufacturer=$(printf "%s" "$xml" | xmlstarlet sel -t -v "/sysinfo/system/entry[@name='manufacturer']")
        prod=$(printf "%s" "$xml" | xmlstarlet sel -t -v "/sysinfo/system/entry[@name='product']")
        serial=$(printf "%s" "$xml"  | xmlstarlet sel -t -v "/sysinfo/system/entry[@name='serial']")
        echo "${n} serial=${serial} ${manufacturer} ${prod}"
        virsh -c qemu+ssh://root@${n}:60022/system nodeinfo

        for it in $(virsh -c qemu+ssh://root@${n}:60022/system pool-list --all --name)
        do
            echo "${n}  pool  $it"
        done
        for it in $(virsh -c qemu+ssh://root@${n}:60022/system net-list --all --name)
        do
            echo "${n}  net   $it"
        done
    done
    find . -type d -name networks | xargs -i@ rm -rf @
    find . -type d -name autostart| xargs -i@ rm -rf @
    return 0
}
main "$@"


