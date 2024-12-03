#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("79703e7[2024-11-29T15:15:05+08:00]:iscsi-multipath.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################
usage() {
    R='\e[1;31m' G='\e[1;32m' Y='\e[33;1m' W='\e[0;97m' N='\e[m' usage_doc="$(cat <<EOF
${*:+${Y}$*${N}\n}${R}${SCRIPTNAME}${N}
        --cluster       ${G}<str>${N}       ceph cluster name, default 'ceph'
        --ceph_user     ${G}<str>${N}       ceph user
        --ceph_pool     ${G}<str>${N}       ceph rbd pool 
        --rbd_img       ${G}<str>${N}       rbd image
        --chap_user     ${G}<str>${N}       iscsi chap auth user
        --chap_pass     ${G}<str>${N}       iscsi chap auth password
        -q|--quiet
        -l|--log ${G}<int>${N} log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
        iscsi server: apt -y install tgt tgt-rbd
        iscsi client: apt -y install multipath-tools open-iscsi
                      yum -y install multipath-tools open-iscsi
                      systemctl enable iscsid.service --now
                      systemctl enable multipathd.service --now
        exam:
          # 部署多个iscsi节点,可以识别同一个wwid,组成多路径
          # # check on debian(target), openeuler(iscsi-initiator)
          ${SCRIPTNAME} --cluster armsite --ceph_user k9s --ceph_pool libvirt-pool --rbd_img rbd.img --chap_user testuser --chap_pass password123
    cat <<EO_CFG > ceph.conf
[global]
fsid = fa0a4156-7196-416e-8ef2-b7c7328a4458
mon_host = 172.16.16.2,172.16.16.3,172.16.16.4,172.16.16.7,172.16.16.8
EO_CFG
EOF
)"; echo -e "${usage_doc}"
    exit 1
}

tgt_rbd() {
    local cluster=${CLUSTER:-"ceph"}
    local ceph_user=${CEPH_USER:-ceph_user}
    local ceph_pool=${CEPH_POOL:-ceph_pool}
    local rbd_img=${RBD_IMG:-rbd_img}
    local chap_user=${CHAP_USER:-chap_user}
    local chap_pass=${CHAP_PASS:-chap_pass}
    info_msg "tgt iscsi mulitpath rbd backend, /etc/tgt/conf.d/rbd.conf\n"
    vinfo_msg <<EOF
ceph osd pool create ${ceph_pool} 128
rbd pool init ${ceph_pool}
ceph auth get-or-create client.${ceph_user} mon 'allow r' osd 'allow class-read object_prefix rbd_children, allow rwx pool=${ceph_pool}' -o ~/${cluster}.client.${ceph_user}.keyring
rbd create ${ceph_pool}/rbd.raw --size 30G
# # tgt server host
# /etc/ceph/${cluster}.client.${ceph_user}.keyring
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# # client use multipath iscsi
iscsiadm -m session -o show
iscsiadm --mode discoverydb --type sendtargets --portal <ip> --discover
# # automatic startup & login
# target name: iqn.2024-11.rbd.local:iscsi-01
iscsiadm --mode node -T <target name> -p <ip> --op update -n node.startup -v automatic
# # re-login manually
iscsiadm --mode node --portal <ip> --login / --logout
# iscsiadm --mode node --op delete

# # force remove device
# echo 1 > /sys/block/<name>/device/delete
# When the last block device for the volume is deleted, multipath will remove the virtual block device.
#
# cat /etc/iscsi/initiatorname.iscsi # # edit client name
# systemctl restart iscsid.service
# cat <<EO_CHAP >> /etc/iscsi/iscsid.conf
# node.session.auth.authmethod = CHAP
# node.session.auth.username = testuser
# node.session.auth.password = password123
# EO_CHAP
# lsblk
multipath -ll
ls -l /dev/mapper/
EOF
    cat <<EOF | ${FILTER_CMD:-sed '/^\s*#/d'}
<target iqn.$(date '+%Y-%m').rbd.local:iscsi-01>
driver iscsi
bs-type rbd
conf=/etc/ceph/${cluster}.conf
id=client.${ceph_user}
cluster=${cluster}
backing-store ${ceph_pool}/${rbd_img}
# Allowed incoming users, multi incominguser lines
incominguser ${chap_user} ${chap_pass}
</target>
EOF
}

main() {
    local opt_short=""
    local opt_long="cluster:,ceph_user:,ceph_pool:,rbd_img:,chap_user:,chap_pass:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            --cluster)       shift; export CLUSTER="${1}"; shift;;
            --ceph_user)     shift; export CEPH_USER="${1}"; shift;;
            --ceph_pool)     shift; export CEPH_POOL="${1}"; shift;;
            --rbd_img)       shift; export RBD_IMG="${1}"; shift;;
            --chap_user)     shift; export CHAP_USER="${1}"; shift;;
            --chap_pass)     shift; export CHAP_PASS="${1}"; shift;;
            ########################################
            -q | --quiet)   shift; QUIET=1;;
            -l | --log)     shift; set_loglevel ${1}; shift;;
            -d | --dryrun)  shift; DRYRUN=1;;
            -V | --version) shift; for _v in "${VERSION[@]}"; do echo "$_v"; done; exit 0;;
            -h | --help)    shift; usage;;
            --)             shift; break;;
            *)              usage "Unexpected option: $1";;
        esac
    done
    tgt_rbd
    return 0
}
main "$@"
