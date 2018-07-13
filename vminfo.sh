#!/usr/bin/env bash
set -o nounset -o pipefail

KVM_USER=${KVM_USER:-root}
KVM_HOST=${KVM_HOST:-10.4.38.8}
KVM_PORT=${KVM_PORT:-60022}
VIRSH_OPT="-q -c qemu+ssh://${KVM_USER}@${KVM_HOST}:${KVM_PORT}/system"

if [ "${DEBUG:=false}" = "true" ]; then
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi

function Get_Vcpuvmems() {
    echo -n "cpu/mem:"
    LANG=C virsh ${VIRSH_OPT} dominfo "$1" | awk '/^CPU\(s\)/{print $2"C"}/^Used memory/{print $3/1024/1024"G"}' | xargs
}

function Get_Vmblk() {
    vols=$(virsh ${VIRSH_OPT} domblklist $1 --details | awk '{print $4}')
    for vol in $vols
    do
        echo -n "disk:"
        LANG=C virsh ${VIRSH_OPT} vol-info $vol | awk '/Type/{print $2} /Name/{print $2} /Capacity/{print $2 $3}' | xargs
    done
}

function Get_Vmip() {
    for nic in $(virsh ${VIRSH_OPT} domiflist $1 | awk '{print $5}')
    do
    {
        echo -n "network:"
        virsh ${VIRSH_OPT} domifaddr --source agent $1 | grep "${nic}"
        vif=$(virsh ${VIRSH_OPT} domiflist $1 | grep "${nic}" | awk '{print $1}')
        virsh ${VIRSH_OPT} domifstat $1 $vif | awk '/rx_bytes/{printf("RX: %.2f MB",$3/1024/1024)} /tx_bytes/{printf(" TX: %.2f MB", $3/1024/1024)}'
    } | xargs
    done
}

function Get_Vmfs() {
    virsh ${VIRSH_OPT} domfsinfo $1
    #virsh domstats
}
function main() {
    for dom in $(LANG=C virsh ${VIRSH_OPT} list  --all | grep running | awk '{print $2}')
    do
        echo "domain:${dom}"
        Get_Vcpuvmems ${dom}
        Get_Vmblk ${dom}
        Get_Vmip ${dom}
        echo "========================================================="
    done
    return 0
}

[[ ${BASH_SOURCE[0]} = $0 ]] && main "$@"

cat >> /dev/null << 'EOFAA'
#!/usr/bin/env bash
set -o nounset -o pipefail

if [ "${DEBUG:=false}" = "true" ]; then
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi


TBL_NAME=${1%.*}
TBL_NAME=${TBL_NAME//-/}
exec 7<$1
:> ${TBL_NAME}

domain=
cpu=
disk=
network=

while read oneline <&7
do
    if [[ ${oneline} =~ ^=*$ ]]; then
        if [[ ${domain} =~ ^apt-43539bab-73ae-48bd-b827-3108a06ee91f$ ]]; then
            domain=
            cpu=
            disk=
            network=
            continue
        fi
        if [[ ${domain} =~ ^timesrv-f0ee2dba-ec0c-4e26-9a84-078a7e79c9bd$ ]]; then
            domain=
            cpu=
            disk=
            network=
            continue
        fi
        echo "${network}" >> ${TBL_NAME}
        domain=
        cpu=
        disk=
        network=
    else
        if [[ ${oneline} =~ ^domain:.*$ ]]; then
            domain="${oneline#*:}" 
        fi 
        if [[ ${oneline} =~ ^cpu/mem:.*$ ]]; then
            cpu="${oneline#*:}"
        fi 
        if [[ ${oneline} =~ ^disk:.*$ ]]; then
            disk="${disk}#${oneline#*:}" 
        fi 
        if [[ ${oneline} =~ ^network:\ eth1.*$ ]]; then
            network=$(echo "${oneline#*:}" | awk '{printf("%s %.2f",$4, $6+$8)}')
        fi 
    fi
done 
exec 7<&-

cat <<- EOF | sqlite3 vmstats.db
CREATE TABLE stat_${TBL_NAME}(dip varchar(18), netflow double);
.separator " "
.import ${TBL_NAME} stat_${TBL_NAME}
.quit
EOF

echo "select t1.dip,  t2.netflow-t1.netflow from stat_20180713130359 as t1, stat_20180714130359 as t2 where t1.dip=t2.dip;"
EOFAA
