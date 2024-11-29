#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("9bd9694[2023-07-11T08:22:54+08:00]:ganesha.nfs.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################
usage() {
    R='\e[1;31m' G='\e[1;32m' Y='\e[33;1m' W='\e[0;97m' N='\e[m' usage_doc="$(cat <<EOF
${*:+${Y}$*${N}\n}${R}${SCRIPTNAME}${N}
        --cluster       ${G}<str>${N}       ceph cluster name, default 'ceph'
        --cephfs_name   ${G}<str>${N}       cephfs name, ceph fs ls
        --cephfs_path   ${G}<str>${N}       cephfs subpath, default /
        --ceph_user     ${G}<str>${N}       ceph user
        --ceph_key      ${G}<str>${N}       ceph auth key
        --nfs_export    ${G}<str>${N}       nfs export path, default /nfs_share
        --bucket        ${G}<str>${N}       s3 bucket name
        --access_key    ${G}<str>${N}       s3 access key
        --secret_key    ${G}<str>${N}       s3 secret access key
        --annotation                        Output conf with comment
        -q|--quiet
        -l|--log ${G}<int>${N} log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
        apt -y install nfs-ganesha
        apt -y install nfs-ganesha-ceph # export cephfs (or RGW)
        apt -y install nfs-ganesha-rgw # export s3 rgw
        exam:
          ${SCRIPTNAME} --cluster armsite --cephfs_name tsdfs --cephfs_path /k8s --ceph_user k9s --ceph_key "AQAA5ENnWx2+DBAAC7ZpySjtYfXevBTlxw3AUg==" --bucket docker-registry --access_key I3FQV62N89SJLCVJX8OV --secret_key SeNoU5ou95Uwi4nZk01MACmmbniLoA608TeUauY0
    cat <<EO_CFG > ceph.conf
[global]
fsid = fa0a4156-7196-416e-8ef2-b7c7328a4458
mon_host = 172.16.16.2,172.16.16.3,172.16.16.4,172.16.16.7,172.16.16.8
EO_CFG
EOF
)"; echo -e "${usage_doc}"
    exit 1
}

log_common() {
    cat <<EOF | ${FILTER_CMD:-sed '/^\s*#/d'}
LOG {
    # # Default log level for all components
    # Default_Log_Level = DEBUG;
    Default_Log_Level = WARN;
}
EOF
}

export_common() {
    local id=${1}
    cat <<EOF | ${FILTER_CMD:-sed '/^\s*#/d'}
    # # Unique export ID number for this export
    Export_id = ${id};
    Protocols = 4;
    # # NFSv4 does not allow UDP transport
    Transports = TCP;
    Pseudo = "${NFS_EXPORT:-/nfs_share}_${id}";
    # # 允许客户端在没有Kerberos身份验证的情况下附加
    SecType = "sys";
    # # 允许用户在NFS挂载中更改目录所有权
    Squash = no_root_squash;
    # # We want to be able to read and write
    Access_Type = RW;
EOF
}

ganesha_cephfs() {
    local cluster=${CLUSTER:-"ceph"}
    local ceph_user=${CEPH_USER:-ceph_user}
    local ceph_key=${CEPH_KEY:-base64key}
    local cephfs_name=${CEPHFS_NAME:-dummy_cephfs_name}
    local cephfs_path=${CEPHFS_PATH:-/cephfs_path}
    local id=$(random 1 1000)
    info_msg "ganesha nfs cephfs backend, /etc/ganesha/ceph.conf\n"
    vinfo_msg <<EOF
ceph fs ls
EOF
    cat <<EOF | ${FILTER_CMD:-sed '/^\s*#/d'}
EXPORT {
$(export_common "${id}")
    # # Path into the cephfs tree.
    # #
    # # Note that FSAL_CEPH does not support subtree checking, so there is
    # # no way to validate that a filehandle presented by a client is
    # # reachable via an exported subtree.
    # #
    # # For that reason, we just export "/" here.
    Path = "${cephfs_path}";
    # # Time out attribute cache entries immediately
    Attr_Expiration_Time = 0;
    # # Enable read delegations? libcephfs v13.0.1 and later allow the
    # # ceph client to set a delegation. While it's possible to allow RW
    # # delegations it's not recommended to enable them until ganesha
    # # acquires CB_GETATTR support.
    # #
    # # Note too that delegations may not be safe in clustered
    # # configurations, so it's probably best to just disable them until
    # # this problem is resolved:
    # #
    # # http://tracker.ceph.com/issues/24802
    # #
    # Delegations = R;
    FSAL {
        Name = Ceph;
        Filesystem = "${cephfs_name}";
        User_Id = "${ceph_user}";
        Secret_Access_Key = "${ceph_key}";
    }
}
CEPH {
    Ceph_Conf = "/etc/ceph/${cluster}.conf";
    umask = 0;
}
EOF
}

ganesha_rgw() {
    local bucket=${BUCKET:-"/public"}
    local cluster=${CLUSTER:-"ceph"}
    local access_key=${ACCESS_KEY:-"access_key"}
    local secret_key=${SECRET_KEY:-"secret_key"}
    local id=$(random 1 1000)
    info_msg "ganesha nfs rgw backend, /etc/ganesha/rgw.conf\n"
    vinfo_msg <<EOF
# ceph auth get-or-create client.<user_id> mon 'allow r' osd 'allow rw pool=.nfs namespace=<nfs_cluster_name>, allow rw tag cephfs data=<fs_name>' mds 'allow rw path=<export_path>'
# 强制执行写顺序，sync挂载选项
# echo '<host:/ <mount-point> nfs noauto,soft,nfsvers=4.1,sync,proto=tcp 0 0' >> /etc/fstab

# Ceph 配置文件的 [client.rgw] 部分中的
# rgw_relaxed_s3_bucket_names 设置为 true。

# # RGW ganesha:
name = client.admin
copy ceph keyring to ganesha host, /var/lib/ceph/radosgw/armsite-admin/keyring
EOF
    cat <<EOF | ${FILTER_CMD:-sed '/^\s*#/d'}
EXPORT {
$(export_common "${id}")
    Path = "${bucket}";
    FSAL {
        Name = RGW;
        User_Id = "${access_key}";
        Access_Key_Id ="${access_key}";
        Secret_Access_Key = "${secret_key}";
    }
}
RGW {
    ceph_conf = /etc/ceph/${cluster}.conf;
    # for vstart cluster, name = "client.admin"
    # /var/lib/ceph/radosgw/armsite-admin/keyring
    name = client.admin;
    cluster = ${cluster};
    # init_args = "-d --debug-rgw=16";
}
EOF
}

main() {
    local opt_short=""
    local opt_long="annotation,ceph_user:,ceph_key:,cephfs_name:,cephfs_path:,nfs_export:,bucket:,cluster:,access_key:,secret_key:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            --ceph_user)     shift; export CEPH_USER="${1}"; shift;;
            --ceph_key)      shift; export CEPH_KEY="${1}"; shift;;
            --cephfs_name)   shift; export CEPHFS_NAME="${1}"; shift;;
            --cephfs_path)   shift; export CEPHFS_PATH="${1}"; shift;;
            --nfs_export)    shift; export NFS_EXPORT="${1}"; shift;;
            --bucket)        shift; export BUCKET="${1}"; shift;;
            --cluster)       shift; export CLUSTER="${1}"; shift;;
            --access_key)    shift; export ACCESS_KEY="${1}"; shift;;
            --secret_key)    shift; export SECRET_KEY="${1}"; shift;;
            --annotation)    shift; export FILTER_CMD=cat;;
                                  # export FILTER_CMD=tee output.log
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
    vinfo_msg <<'EOF'
nfs_host:${NFS_EXPORT} /mountpoint nfs noauto,soft,nfsvers=4.1,sync,proto=tcp 0 0'
EOF
    log_common
    ganesha_cephfs
    ganesha_rgw
    return 0
}
main "$@"
