#!/usr/bin/env bash

if [ "${DEBUG:=false}" = "true" ]; then
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi

function Get_Vcpuvmems() {
    LANG=C virsh dominfo "$1" | awk '/^CPU\(s\)/{print $2"C"}/^Used memory/{print $3/1024/1024"G"}' | xargs
}

function Get_Vmblk() {
    vols=$(virsh -q domblklist $1 --details | awk '{print $4}')
    for vol in $vols
    do
        LANG=C virsh vol-info $vol | awk '/Type/{print $2} /Name/{print $2} /Capacity/{print $2 $3}' | xargs
    done
}

function Get_Vmip() {
    for nic in $(virsh -q domiflist $1 | awk '{print $5}')
    do
    {
        virsh -q domifaddr --source agent $1 | grep "${nic}"
        vif=$(virsh -q domiflist $1 | grep "${nic}" | awk '{print $1}')
        virsh domifstat $1 $vif | awk '/rx_bytes/{print "RX:"$3/1024/1024"MB"} /tx_bytes/{print "TX:"$3/1024/1024"MB"}'
    } | xargs
    done
}

function Get_Vmfs() {
    virsh domfsinfo $1
    #virsh domstats
}
function main() {
    for dom in $(LANG=C virsh list  --all | grep running | awk '{print $2}')
    do
        echo -n "${dom}:"
        Get_Vcpuvmems ${dom}
        Get_Vmblk ${dom}
        Get_Vmip ${dom}
        echo "========================================================="
    done
    return 0
}

[[ ${BASH_SOURCE[0]} = $0 ]] && main "$@"
