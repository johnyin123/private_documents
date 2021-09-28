#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("new_ceph.sh - 9a4676a - 2021-09-28T09:05:17+08:00")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || true
################################################################################
gen_ceph_conf() {
    local cname=${1}
    local name=${HOSTNAME:-$(hostname)}
    local ipaddr=$(hostname -i)
    local fsid=$(cat /proc/sys/kernel/random/uuid)
    local cluster_network=$(ip route | grep "${ipaddr}" | awk '{print $1}')
    sed -i "/^CLUSTER\s*=/d" /etc/sysconfig/ceph
    echo "CLUSTER=${cname}" >> /etc/sysconfig/ceph
    cat <<EOF | tee /etc/ceph/${cname}.conf
[global]
fsid = ${fsid}
mon_initial_members = ${name}
mon_host = ${ipaddr}
cluster network = ${cluster_network}
public network = ${cluster_network}
##################################
osd pool default size = 2
osd pool default min size = 1
mon allow pool delete = true
mon clock drift allowed = 2
mon clock drift warn backoff = 30
EOF
}

init_first_mon() {
    local cname=${1}
    local name=${HOSTNAME:-$(hostname)}
    local ipaddr=$(hostname -i)
    [ -e "/etc/ceph/${cname}.conf" ] || return 1
    local fsid=$(grep  '^fsid\s*=' /etc/ceph/${cname}.conf  | awk '{print $NF}')
    ceph-authtool --create-keyring /etc/ceph/${cname}.mon.keyring \
        --gen-key -n mon. --cap mon 'allow *'
    ceph-authtool --create-keyring /etc/ceph/${cname}.client.admin.keyring \
        --gen-key -n client.admin --cap mon 'allow *' --cap osd 'allow *' --cap mds 'allow *' --cap mgr 'allow *'
    ceph-authtool --create-keyring /var/lib/ceph/bootstrap-osd/${cname}.keyring \
        --gen-key -n client.bootstrap-osd --cap mon 'profile bootstrap-osd' --cap mgr 'allow r'
    ceph-authtool /etc/ceph/${cname}.mon.keyring --import-keyring /etc/ceph/${cname}.client.admin.keyring
    ceph-authtool /etc/ceph/${cname}.mon.keyring --import-keyring /var/lib/ceph/bootstrap-osd/${cname}.keyring
    chown ceph:ceph \
        /etc/ceph/${cname}.conf \
        /etc/ceph/${cname}.mon.keyring \
        /etc/ceph/${cname}.client.admin.keyring \
        /var/lib/ceph/bootstrap-osd/${cname}.keyring
    rm -rf /tmp/monmap && monmaptool --create --add ${name} ${ipaddr} --fsid ${fsid} /tmp/monmap
    sudo -u ceph mkdir -p /var/lib/ceph/mon/${cname}-${name}
    sudo -u ceph ceph-mon --cluster ${cname} --mkfs -i ${name} --monmap /tmp/monmap --keyring /etc/ceph/${cname}.mon.keyring
    systemctl enable --now ceph-mon@${name}
    echo "fix mon is allowing insecure global_id reclaim WARN"
    ceph --cluster ${cname} config set mon auth_allow_insecure_global_id_reclaim false
    ceph --cluster ${cname} -s
}

init_ceph_mgr() {
    local cname=${1}
    local name=${HOSTNAME:-$(hostname)}
    [ -e "/etc/ceph/${cname}.conf" ] || return 1
    ceph --cluster ${cname} mon enable-msgr2
    #ceph mgr module enable pg_autoscaler
    sudo -u ceph mkdir /var/lib/ceph/mgr/${cname}-${name}
    ceph --cluster ${cname} auth get-or-create mgr.${name} mon 'allow profile mgr' osd 'allow *' mds 'allow *'
    ceph --cluster ${cname} auth get-or-create mgr.${name} > /etc/ceph/${cname}.mgr.admin.keyring
    sudo -u ceph cp /etc/ceph/${cname}.mgr.admin.keyring /var/lib/ceph/mgr/${cname}-${name}/keyring
    systemctl enable --now ceph-mgr@${name}
    ceph --cluster ${cname} -s
    # switch standby ceph-mgr: ceph mgr fail <node>
}

add_new_mon() {
    local cname=${1}
    local name=${HOSTNAME:-$(hostname)}
    local mon_key=/tmp/mon.key
    local mon_map=/tmp/mon.map
    [ -e "/etc/ceph/${cname}.conf" ] || return 1
    sudo -u ceph ceph --cluster ${cname} auth get mon. -o ${mon_key}
    sudo -u ceph ceph --cluster ${cname} mon getmap -o ${mon_map}
    sudo -u ceph mkdir -p /var/lib/ceph/mon/${cname}-${name}
    sudo -u ceph ceph-mon --cluster ${cname} --mkfs -i ${name} --monmap ${mon_map} --keyring ${mon_key}
    systemctl enable --now ceph-mon@${name}
    ceph --cluster ${cname} -s
}

add_osd_bluestore() {
    local cname=${1}
    local disk=${2}
    # copy /var/lib/ceph/bootstrap-osd/${cname}.keyring from monitor node to osd node
    [ -e "/var/lib/ceph/bootstrap-osd/${cname}.keyring" ] && {
        echo "destroy all volume groups and logical volumes"
        ceph-volume --cluster ${cname} lvm zap ${disk} --destroy
        echo "create ceph volumes"
        ceph-volume --cluster ${cname} lvm create --data ${disk}
    }
    ceph --cluster ${cname} -s
}

add_mds() {
    # first is active, others standby
    local cname=${1}
    local name=${HOSTNAME:-$(hostname)}
    [ -e "/etc/ceph/${cname}.conf" ] || return 1
    sudo -u ceph mkdir -p /var/lib/ceph/mds/${cname}-${name}
    sudo -u ceph --cluster ${cname} ceph-authtool --create-keyring /var/lib/ceph/mds/${cname}-${name}/keyring --gen-key -n mds.${name}
    sudo -u ceph --cluster ${cname} ceph auth add mds.${name} osd "allow rwx" mds "allow *" mon "allow profile mds" -i /var/lib/ceph/mds/${cname}-${name}/keyring
    systemctl enable --now ceph-mds@${name}
    ceph --cluster ${cname} mds stat
}

master_multi_site_rgw() {
    local cname=${1}
    local realm_name=${2}
    local zonegroup_name=${3}
    local zone_name=${4}
    local endpoints=${5}
    local access_key=${6}
    local secret_key=${7}
    local username=${zonegroup_name}_sysuser
    echo "create realm ${realm_name}"
    radosgw-admin --cluster ${cname} realm create --rgw-realm=${realm_name} --default || true
    echo "create zonegroup ${zonegroup_name}"
    radosgw-admin --cluster ${cname} zonegroup create \
        --rgw-zonegroup=${zonegroup_name} \
        --endpoints=${endpoints} \
        --rgw-realm=${realm_name} \
        --master --default || true
    echo "create zone ${zone_name}"
    radosgw-admin --cluster ${cname} zone create \
        --rgw-zonegroup=${zonegroup_name} \
        --rgw-zone=${zone_name} \
        --endpoints=${endpoints} \
        --master --default || true
    echo "remove default zone from default zonegroup"
    radosgw-admin --cluster ${cname} zonegroup remove --rgw-zonegroup=default --rgw-zone=default || true
    echo "period update"
    radosgw-admin --cluster ${cname} period update --commit
    echo "delete zone default"
    radosgw-admin --cluster ${cname} zone delete --rgw-zone=default || true
    echo "period update"
    radosgw-admin --cluster ${cname} period update --commit
    echo "delete zonegroup default"
    radosgw-admin --cluster ${cname} zonegroup delete --rgw-zonegroup=default || true
    echo "period update"
    radosgw-admin --cluster ${cname} period update --commit
    echo "delete default rgw pool"
    ceph --cluster ${cname} osd pool rm default.rgw.control default.rgw.control --yes-i-really-really-mean-it || true
    ceph --cluster ${cname} osd pool rm default.rgw.data.root default.rgw.data.root --yes-i-really-really-mean-it || true
    ceph --cluster ${cname} osd pool rm default.rgw.gc default.rgw.gc --yes-i-really-really-mean-it || true
    ceph --cluster ${cname} osd pool rm default.rgw.log default.rgw.log --yes-i-really-really-mean-it || true
    ceph --cluster ${cname} osd pool rm default.rgw.users.uid default.rgw.users.uid --yes-i-really-really-mean-it || true
    ceph --cluster ${cname} osd pool rm default.rgw.meta default.rgw.meta --yes-i-really-really-mean-it || true
    echo "Add the system user to the master zone"
    radosgw-admin --cluster ${cname} user rm --uid=${username} --purge-data || true
    radosgw-admin --cluster ${cname} user create --uid=${username} --display-name="${zonegroup_name}_synchronization_user_multi_site" --access-key=${access_key} --secret=${secret_key} --system
    radosgw-admin --cluster ${cname} user list
    # radosgw-admin --cluster ${cname} zone modify --rgw-zone=${zone_name} --access-key=${access_key} --secret=${secret_key}
    radosgw-admin --cluster ${cname} zone modify --rgw-realm=${realm_name} --rgw-zonegroup=${zonegroup_name} --rgw-zone=${zone_name} --endpoints ${endpoints} --access-key=${access_key} --secret=${secret_key} --master --default
    echo "period update"
    radosgw-admin --cluster ${cname} period update --commit
    echo "fix rgw multi site upload http 416"
    ceph --cluster ${cname} config set global mon_max_pg_per_osd 300
    ceph --cluster ${cname} -s
}

secondary_multi_site_rgw() {
    local cname=${1}
    local realm_name=${2}
    local zonegroup_name=${3}
    local zone_name=${4}
    local endpoints=${5}
    local access_key=${6}
    local secret_key=${7}
    local master_url=${8}
    echo "pull the realm"
    radosgw-admin --cluster ${cname} realm pull  --url=${master_url} --access-key=${access_key} --secret=${secret_key}
    echo "This realm is the default realm or the only realm, make the realm the default realm"
    radosgw-admin --cluster ${cname} realm default --rgw-realm=${realm_name}
    echo "pull the period"
    radosgw-admin --cluster ${cname} period pull --url=${master_url} --access-key=${access_key} --secret=${secret_key}
    echo "create secondary zone(NOT master/default)"
    radosgw-admin --cluster ${cname} zone create \
        --rgw-zonegroup=${zonegroup_name} \
        --rgw-zone=${zone_name} \
        --endpoints=${endpoints} \
        --access-key=${access_key} --secret=${secret_key}
        # --read-only
    echo "remove zonegroup/zone default"
    radosgw-admin --cluster ${cname} zonegroup remove --rgw-zonegroup=default --rgw-zone=default || true
    radosgw-admin --cluster ${cname} zone delete --rgw-zone=default || true
    radosgw-admin --cluster ${cname} zonegroup delete --rgw-zonegroup=default || true
    echo "delete default rgw pool"
    ceph --cluster ${cname} osd pool rm default.rgw.control default.rgw.control --yes-i-really-really-mean-it || true
    ceph --cluster ${cname} osd pool rm default.rgw.data.root default.rgw.data.root --yes-i-really-really-mean-it || true
    ceph --cluster ${cname} osd pool rm default.rgw.gc default.rgw.gc --yes-i-really-really-mean-it || true
    ceph --cluster ${cname} osd pool rm default.rgw.log default.rgw.log --yes-i-really-really-mean-it || true
    ceph --cluster ${cname} osd pool rm default.rgw.users.uid default.rgw.users.uid --yes-i-really-really-mean-it || true
    ceph --cluster ${cname} osd pool rm default.rgw.meta default.rgw.meta --yes-i-really-really-mean-it || true
    echo "restart ceph-radosgw@rgw.$(hostname)"
    systemctl restart ceph-radosgw@rgw.$(hostname)
    echo "radosgw period update"
    radosgw-admin --cluster ${cname} period update --commit
    echo "radosgw sync status"
    radosgw-admin --cluster ${cname} sync status
}

add_rgw() {
    local cname=${1}
    local name=${HOSTNAME:-$(hostname)}
    ceph --cluster ${cname} auth get-or-create client.rgw.${name} mon 'allow rwx' osd 'allow rwx' -o /etc/ceph/${cname}.client.rgw.${name}.keyring
    chown ceph.ceph /var/lib/ceph/radosgw
    sudo -u ceph mkdir -p /var/lib/ceph/radosgw/${cname}-rgw.${name}
    sudo -u ceph cp /etc/ceph/${cname}.client.rgw.${name}.keyring /var/lib/ceph/radosgw/${cname}-rgw.${name}/keyring
    systemctl enable --now ceph-radosgw@rgw.${name}
    ceph --cluster ${cname} -s
}

teardown() {
    local name=${HOSTNAME:-$(hostname)}
    systemctl disable --now ceph-mon@${name} || true
    systemctl disable --now ceph-mgr@${name} || true
    systemctl disable --now ceph-mds@${name} || true
    systemctl disable --now ceph-volume@ || true
    systemctl disable ceph-radosgw@rgw.${name} || true
    kill -9 $(pidof radosgw) || true
    kill -9 $(pidof ceph-osd) || true
    # kill -9 $(pidof ceph-osd)
    for i in /var/lib/ceph/osd/*; do
        umount -fl $i || true
    done
    rm -fr \
    /etc/ceph/* \
    /var/lib/ceph/bootstrap-osd/* \
    /var/lib/ceph/bootstrap-mds/* \
    /var/lib/ceph/bootstrap-mon/* \
    /var/lib/ceph/bootstrap-mgr/* \
    /var/lib/ceph/mon/* \
    /var/lib/ceph/mgr/* \
    /var/lib/ceph/osd/* \
    /var/lib/ceph/mds/* \
    /var/run/ceph/* \
    /var/lib/ceph/radosgw/* \
    || true
}
list_rgw_info() {
    local cname=${1}
    echo "realm info"
    radosgw-admin --cluster ${cname} realm list
    echo "zonegroup info"
    radosgw-admin --cluster ${cname} zonegroup list
    echo "zone info"
    radosgw-admin --cluster ${cname} zone list
    echo "pool info"
    ceph --cluster ${cname} osd pool ls
}
# remote execute function end!
################################################################################
SSH_PORT=${SSH_PORT:-60022}
remote_func() {
    local ipaddr=${1}
    local port=${2}
    local user=${3}
    local func_name=${4}
    shift 4
    local args=("$@")
    warn_msg "${user}@${ipaddr}:${port} start ====> ${func_name}\n"
    local ssh_opt="-o StrictHostKeyChecking=no -o ServerAliveInterval=60 -p${port} ${user}@${ipaddr}"
    try ssh ${ssh_opt} /bin/bash -x -o errexit -s << EOF
$(typeset -f "${func_name}" 2>/dev/null)
${func_name} ${args[@]}
EOF
    warn_msg "${user}@${ipaddr}:${port} end ====> ${func_name}\n"
}

remove_ceph_cfg() {
    local ipaddr=${1}
    info_msg "${ipaddr} teardown all ceph config!\n"
    remote_func ${ipaddr} ${SSH_PORT} "root" "teardown"
}

download() {
    local ipaddr=${1}
    local port=${2}
    local user=${3}
    local rfile=${4}
    local lfile=${5}
    warn_msg "download ${user}@${ipaddr}:${port}${rfile} ====> ${lfile}\n"
    try scp -P${port} ${user}@${ipaddr}:${rfile} ${lfile}
}

upload() {
    local lfile=${1}
    local ipaddr=${2}
    local port=${3}
    local user=${4}
    local rfile=${5}
    warn_msg "upload ${lfile} ====> ${user}@${ipaddr}:${port}${rfile}\n"
    try scp -P${port} ${lfile} ${user}@${ipaddr}:${rfile}
}

inst_ceph_mon() {
    local cname=${1}
    shift 1
    local mon=("$@")
    local allmon=("$@")
    local ipaddr=${mon[0]}
    local mon_initial_members=()
    local mon_host=()
    info_msg "${ipaddr} ceph mgr install the first mon node!\n"
    mon_initial_members+=($(remote_func ${ipaddr} ${SSH_PORT} "root" "hostname"))
    mon_host+=($(remote_func ${ipaddr} ${SSH_PORT} "root" "hostname -i"))
    remote_func ${ipaddr} ${SSH_PORT} "root" gen_ceph_conf "${cname}"
    download ${ipaddr} ${SSH_PORT} "root" "/etc/sysconfig/ceph" "${DIRNAME}/${cname}.ceph"
    download ${ipaddr} ${SSH_PORT} "root" "/etc/ceph/${cname}.conf" "${DIRNAME}/${cname}.conf"
    ${EDITOR:-vi} "${DIRNAME}/${cname}.conf" || true
    confirm "Confirm NEW init ceph env(timeout 10,default N)?" 10 || exit_msg "BYE!"
    upload "${DIRNAME}/${cname}.conf" ${ipaddr} ${SSH_PORT} "root" "/etc/ceph/${cname}.conf"
    remote_func ${ipaddr} ${SSH_PORT} "root" init_first_mon "${cname}"
    download ${ipaddr} ${SSH_PORT} "root" "/etc/ceph/${cname}.client.admin.keyring" "${DIRNAME}/${cname}.client.admin.keyring"
    download ${ipaddr} ${SSH_PORT} "root" "/var/lib/ceph/bootstrap-osd/${cname}.keyring" "${DIRNAME}/${cname}.keyring"
    remote_func ${ipaddr} ${SSH_PORT} "root" init_ceph_mgr "${cname}"
    #now add other mons
    mon[0]=
    for ipaddr in ${mon[@]}; do
        info_msg "****** $ipaddr init mon.\n"
        mon_initial_members+=($(remote_func ${ipaddr} ${SSH_PORT} "root" "hostname"))
        mon_host+=($(remote_func ${ipaddr} ${SSH_PORT} "root" "hostname -i"))
        upload "${DIRNAME}/${cname}.ceph" ${ipaddr} ${SSH_PORT} "root" "/etc/sysconfig/ceph"
        upload "${DIRNAME}/${cname}.conf" ${ipaddr} ${SSH_PORT} "root" "/etc/ceph/${cname}.conf"
        upload "${DIRNAME}/${cname}.client.admin.keyring" ${ipaddr} ${SSH_PORT} "root" "/etc/ceph/${cname}.client.admin.keyring"
        upload "${DIRNAME}/${cname}.keyring" ${ipaddr} ${SSH_PORT} "root" "/var/lib/ceph/bootstrap-osd/${cname}.keyring"
        remote_func ${ipaddr} ${SSH_PORT} "root" "chmod 644 /etc/ceph/${cname}.client.admin.keyring"
        remote_func ${ipaddr} ${SSH_PORT} "root" "chown ceph:ceph /var/lib/ceph/bootstrap-osd/${cname}.keyring"
        remote_func ${ipaddr} ${SSH_PORT} "root" add_new_mon "${cname}"
        # standby ceph-mgr
        remote_func ${ipaddr} ${SSH_PORT} "root" init_ceph_mgr "${cname}"
    done
    try cat "${DIRNAME}/${cname}.conf" | \
        set_config mon_initial_members "$(OIFS="$IFS" IFS=,; echo "${mon_initial_members[*]}"; IFS="$OIFS")" | \
        set_config mon_host "$(OIFS="$IFS" IFS=,; echo "${mon_host[*]}"; IFS="$OIFS")" \
        > "${DIRNAME}/${cname}.conf.new"
    try rm -f "${DIRNAME}/${cname}.conf"
    try mv "${DIRNAME}/${cname}.conf.new" "${DIRNAME}/${cname}.conf"
    for ipaddr in ${allmon[@]}; do
        upload "${DIRNAME}/${cname}.conf" ${ipaddr} ${SSH_PORT} "root" "/etc/ceph/${cname}.conf"
        remote_func ${ipaddr} ${SSH_PORT} "root" "systemctl restart ceph.target"
    done
}

inst_ceph_osd() {
    local cname=${1}
    shift 1
    local osd=("$@")
    local ipaddr= dev=
    [ -e "${DIRNAME}/${cname}.ceph" ] || exit_msg "nofound ${DIRNAME}/${cname}.ceph\n"
    [ -e "${DIRNAME}/${cname}.conf" ] || exit_msg "nofound ${DIRNAME}/${cname}.conf\n"
    [ -e "${DIRNAME}/${cname}.client.admin.keyring" ] || exit_msg "nofound ${DIRNAME}/${cname}.client.admin.keyring\n"
    [ -e "${DIRNAME}/${cname}.keyring" ] || exit_msg "nofound ${DIRNAME}/${cname}.keyring\n"
    for ipaddr in ${osd[@]}; do
        #dev=${ipaddr##*:}
        dev=$(awk -F':' '{print $2}' <<< "$ipaddr")
        [ -z "${dev}" ] && continue
        ipaddr=${ipaddr%:*}
        info_msg "****** ${ipaddr}:${dev} init osd.\n"
        upload "${DIRNAME}/${cname}.ceph" ${ipaddr} ${SSH_PORT} "root" "/etc/sysconfig/ceph"
        upload "${DIRNAME}/${cname}.conf" ${ipaddr} ${SSH_PORT} "root" "/etc/ceph/${cname}.conf"
        upload "${DIRNAME}/${cname}.client.admin.keyring" ${ipaddr} ${SSH_PORT} "root" "/etc/ceph/${cname}.client.admin.keyring"
        upload "${DIRNAME}/${cname}.keyring" ${ipaddr} ${SSH_PORT} "root" "/var/lib/ceph/bootstrap-osd/${cname}.keyring"
        remote_func ${ipaddr} ${SSH_PORT} "root" "chmod 644 /etc/ceph/${cname}.client.admin.keyring"
        remote_func ${ipaddr} ${SSH_PORT} "root" "chown ceph:ceph /var/lib/ceph/bootstrap-osd/${cname}.keyring"
        remote_func ${ipaddr} ${SSH_PORT} "root" add_osd_bluestore "${cname}" "${dev}"
    done
}

inst_ceph_mds() {
    local cname=${1}
    shift 1
    local mds=("$@")
    local ipaddr=
    [ -e "${DIRNAME}/${cname}.ceph" ] || exit_msg "nofound ${DIRNAME}/${cname}.ceph\n"
    [ -e "${DIRNAME}/${cname}.conf" ] || exit_msg "nofound ${DIRNAME}/${cname}.conf\n"
    [ -e "${DIRNAME}/${cname}.client.admin.keyring" ] || exit_msg "nofound ${DIRNAME}/${cname}.client.admin.keyring\n"
    [ -e "${DIRNAME}/${cname}.keyring" ] || exit_msg "nofound ${DIRNAME}/${cname}.keyring\n"
    for ipaddr in ${mds[@]}; do
        info_msg "****** ${ipaddr} init mds.\n"
        upload "${DIRNAME}/${cname}.ceph" ${ipaddr} ${SSH_PORT} "root" "/etc/sysconfig/ceph"
        upload "${DIRNAME}/${cname}.conf" ${ipaddr} ${SSH_PORT} "root" "/etc/ceph/${cname}.conf"
        upload "${DIRNAME}/${cname}.client.admin.keyring" ${ipaddr} ${SSH_PORT} "root" "/etc/ceph/${cname}.client.admin.keyring"
        upload "${DIRNAME}/${cname}.keyring" ${ipaddr} ${SSH_PORT} "root" "/var/lib/ceph/bootstrap-osd/${cname}.keyring"
        remote_func ${ipaddr} ${SSH_PORT} "root" "chmod 644 /etc/ceph/${cname}.client.admin.keyring"
        remote_func ${ipaddr} ${SSH_PORT} "root" "chown ceph:ceph /var/lib/ceph/bootstrap-osd/${cname}.keyring"
        remote_func ${ipaddr} ${SSH_PORT} "root" add_mds "${cname}"
     done
}

setup_rgw_multi_site_master() {
    local cname=${1}
    local realm_name=${2}
    local zonegroup_name=${3}
    local zone_name=${4}
    # fully qualified domain name(s) in the zonegroup
    local endpoints=${5}
    shift 5
    local rgw=("$@")
    local ipaddr=${rgw[0]}
    info_msg "****** ${ipaddr} master zone multi site rgw.\n"
    local access_key=$(gen_passwd 20)
    local secret_key=$(gen_passwd 40)
    tee -i "${DIRNAME}/${cname}.rgw.master.info" <<EOF
cname=${cname}
realm_name=${realm_name}
zonegroup_name=${zonegroup_name}
zone_name=${zone_name}
endpoints=${endpoints}
access_key=${access_key}
secret_key=${secret_key}
EOF
    remote_func ${ipaddr} ${SSH_PORT} "root" master_multi_site_rgw "${cname}" "${realm_name}" "${zonegroup_name}" "${zone_name}" "${endpoints}" "${access_key}" "${secret_key}"
    for ipaddr in ${rgw[@]}; do
        remote_func ${ipaddr} ${SSH_PORT} "root" 'systemctl restart ceph-radosgw@rgw.$(hostname)'
    done
    remote_func ${ipaddr} ${SSH_PORT} "root" list_rgw_info "${cname}"
}

setup_rgw_multi_site_slave() {
    local cname=${1}
    local realm_name=${2}
    local zonegroup_name=${3}
    local zone_name=${4}
    local endpoints=${5}
    local master_url=${6}
    local access_key=${7}
    local secret_key=${8}
    shift 8
    local rgw=("$@")
    local ipaddr=${rgw[0]}
    info_msg "****** ${ipaddr} secondary zone multi site rgw.\n"
    tee -i "${DIRNAME}/${cname}.rgw.secondary.info" <<EOF
cname=${cname}
realm_name=${realm_name}
zonegroup_name=${zonegroup_name}
zone_name=${zone_name}
endpoints=${endpoints}
access_key=${access_key}
secret_key=${secret_key}
master_url=${master_url}
EOF
    remote_func ${ipaddr} ${SSH_PORT} "root" secondary_multi_site_rgw "${cname}" "${realm_name}" \
        "${zonegroup_name}" "${zone_name}" "${endpoints}" "${access_key}" "${secret_key}" "${master_url}"
    for ipaddr in ${rgw[@]}; do
        remote_func ${ipaddr} ${SSH_PORT} "root" 'systemctl restart ceph-radosgw@rgw.$(hostname)'
    done
    remote_func ${ipaddr} ${SSH_PORT} "root" list_rgw_info "${cname}"
}

inst_ceph_rgw() {
    local cname=${1}
    shift 1
    local rgw=("$@")
    local ipaddr= port= name=
    [ -e "${DIRNAME}/${cname}.conf" ] || exit_msg "nofound ${DIRNAME}/${cname}.conf\n"
    for ipaddr in ${rgw[@]}; do
        port=$(awk -F':' '{print $2}' <<< "$ipaddr")
        #port=${ipaddr##*:}
        ipaddr=${ipaddr%:*}
        name=$(remote_func ${ipaddr} ${SSH_PORT} "root" hostname)
        # remove orig configurtions
        sed -i "/\[client.rgw.${name}]/,/^\[client.rgw.$/d" ${DIRNAME}/${cname}.conf
        cat <<EOF >> ${DIRNAME}/${cname}.conf
##################################
[client.rgw.${name}]
# ipaddr of the node
host = ${ipaddr}
rgw frontends = "beast port=${port:-80}"
EOF
    # rgw_zone = <you zone if not default>
    # rgw frontends = "civetweb port=80"
    done
    ${EDITOR:-vi} "${DIRNAME}/${cname}.conf" || true
    for ipaddr in ${rgw[@]}; do
        ipaddr=${ipaddr%:*}
        info_msg "****** ${ipaddr} init rgw.\n"
        upload "${DIRNAME}/${cname}.conf" ${ipaddr} ${SSH_PORT} "root" "/etc/ceph/${cname}.conf"
        remote_func ${ipaddr} ${SSH_PORT} "root" add_rgw "${cname}"
     done
}

usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        -c|--cluster   <cluster name> ceph cluster name, default "ceph"
        -m|--mon       <ceph mon ip>  ceph mon node, (first mon is mon/mgr(active), other mon/mgr(standby))
        -o|--osd       <ceph osd ip>:<device>  ceph osd node
        --mds          <ceph mds ip>  ceph mds node, (first mds active, other standby)
        --rgw          <ceph rgw ip>:<port>  ceph rgw node, default port=80
                       first: yum -y install ceph-radosgw
                       echo <access_key:secret_key> > ~/.passwd-s3fs
                       chmod 600 ~/.passwd-s3fs
                       s3fs bucket1 /mnt/ -o passwd_file=~/.passwd-s3fs -o url=http://<ip> -o use_path_request_style
        --master_zone  <ip>   make rgw as default master zone
                       master zone needs: <rgw_realm> <rgw_grp> <rgw_zone> <rgw_endpts>
                       !!! script delete all default rgw pool !!!
        --sec_zone     <ip>   make rgw as default secondary zone
                       sec zone needs: <rgw_realm> <rgw_grp> <rgw_zone> <rgw_endpts>
                                       <master_url> <access_key> <secret_key>
                       rgw_zone is NOT same as rgw_zone in master_zone
                       !!! script delete all default rgw pool !!!
        --master_url   <url>  master url for pull realm&period, example: http://192.168.168.201
        --access_key   <key>  master sync system user access_key
        --secret_key   <key>  master sync system user secret_key
        --rgw_realm    <name> rgw multi site realm
        --rgw_grp      <name> rgw multi site zonegroup
        --rgw_zone     <name> rgw multi site zone
        --rgw_endpts   <str>  rgw multi site endpoints. exam: http://pic.sample.com:80
        --teardown     <ip>   remove all ceph config
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
    Example:
            centos-release-ceph-nautilus/centos-release-ceph-octopus/centos-release-ceph-pacific
        1. yum -y update && yum -y install centos-release-ceph-pacific
        2. yum -y install ceph
        SSH_PORT default is 60022
         ${SCRIPTNAME} -c site1 \\
               -m 192.168.168.101 -m 192.168.168.102 -m 192.168.168.103 \\
               -o 192.168.168.101:/dev/vdb -o 192.168.168.102:/dev/vdb -o 192.168.168.103:/dev/vdb \\
               --rgw 192.168.168.101:80 --rgw 192.168.168.102:80 --rgw 192.168.168.103:80
         ${SCRIPTNAME} -c site1 \\
               --master_zone 192.168.168.101 --master_zone 192.168.168.102 --master_zone 192.168.168.103 \\
               --rgw_endpts http://192.168.168.101:80,http://192.168.168.102:80,http://192.168.168.103:80 \\
               --rgw_realm movie --rgw_grp cn --rgw_zone idc01
         ${SCRIPTNAME} -c site2 \\
               -m 192.168.168.201 -m 192.168.168.202 -m 192.168.168.203 \\
               -o 192.168.168.201:/dev/vdb -o 192.168.168.202:/dev/vdb -o 192.168.168.203:/dev/vdb \\
               --rgw 192.168.168.201:80 --rgw 192.168.168.202:80 --rgw 192.168.168.203:80 \\
               --sec_zone 192.168.168.201 --sec_zone 192.168.168.202 --sec_zone 192.168.168.203 \\
               --rgw_endpts http://192.168.168.201:80,http://192.168.168.202:80,http://192.168.168.203:80 \\
               --master_url http://192.168.168.101 --access_key <key> --secret_key <key> \\
               --rgw_realm movie --rgw_grp cn --rgw_zone idc02
        ceph node hosts: servern is public network(mon_host,mon_initial_members),osd in cluster network
               127.0.0.1       localhost
               192.168.168.101 server1
               .....
               192.168.168.... servern
EOF
    exit 1
}
main() {
    local mon=() osd=() mds=() rgw=() cluster=ceph
    local master_zone=() rgw_realm="" rgw_grp="" rgw_zone="" rgw_endpts=""
    local sec_zone=() master_url="" access_key="" secret_key=""
    local opt_short="c:m:o:"
    local opt_long="cluster:,mon:,osd:,mds:,rgw:,master_zone:,rgw_realm:,rgw_grp:,rgw_zone:,rgw_endpts:,sec_zone:,master_url:,access_key:,secret_key:,teardown:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -c | --cluster) shift; cluster=${1}; shift;;
            -m | --mon)     shift; mon+=(${1}); shift;;
            -o | --osd)     shift; osd+=(${1}); shift;;
            --mds)          shift; mds+=(${1}); shift;;
            --rgw)          shift; rgw+=(${1}); shift;;
            --master_zone)  shift; master_zone+=(${1}); shift;;
            --rgw_realm)    shift; rgw_realm=${1}; shift;;
            --rgw_grp)      shift; rgw_grp=${1}; shift;;
            --rgw_zone)     shift; rgw_zone=${1}; shift;;
            --rgw_endpts)   shift; rgw_endpts=${1}; shift;;
            --sec_zone)     shift; sec_zone+=(${1}); shift;;
            --master_url)   shift; master_url=${1}; shift;;
            --access_key)   shift; access_key=${1}; shift;;
            --secret_key)   shift; secret_key=${1}; shift;;
            --teardown)     shift; remove_ceph_cfg ${1}; shift;;
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
    [ "$(array_size master_zone)" -gt "0" ] && [ "$(array_size sec_zone)" -gt "0" ] && usage "sec_zone/master_zone?"
    [ "$(array_size mon)" -gt "0" ] && inst_ceph_mon "${cluster}" "${mon[@]}"
    [ "$(array_size osd)" -gt "0" ] && inst_ceph_osd "${cluster}" "${osd[@]}"
    [ "$(array_size mds)" -gt "0" ] && inst_ceph_mds "${cluster}" "${mds[@]}"
    [ "$(array_size rgw)" -gt "0" ] && inst_ceph_rgw "${cluster}" "${rgw[@]}"
    [ "$(array_size master_zone)" -gt "0" ] && {
        [ -z "${rgw_realm}" ] || [ -z "${rgw_grp}" ] || \
        [ -z "${rgw_zone}" ] || [ -z "${rgw_endpts}" ] || \
            setup_rgw_multi_site_master "${cluster}" "${rgw_realm}" "${rgw_grp}" "${rgw_zone}" "${rgw_endpts}" "${master_zone[@]}"
    }
    [ "$(array_size sec_zone)" -gt "0" ] && {
        [ -z "${rgw_realm}" ] || [ -z "${rgw_grp}" ] || \
        [ -z "${rgw_zone}" ] || [ -z "${rgw_endpts}" ] || \
        [ -z "${master_url}" ] || [ -z "${access_key}" ] || [ -z "${secret_key}" ] || \
            setup_rgw_multi_site_slave "${cluster}" "${rgw_realm}" "${rgw_grp}" "${rgw_zone}" "${rgw_endpts}" \
            "${master_url}" "${access_key}" "${secret_key}" "${sec_zone[@]}"
    }
    info_msg "ALL DONE\n"
    return 0
}
main "$@"

: <<'EOF'
# mon is allowing insecure global_id reclaim
    ceph config set mon auth_allow_insecure_global_id_reclaim false
# rgw multi site upload http 416
    ceph config set global mon_max_pg_per_osd 300
# dashboard
    ceph mgr module enable dashboard
    ceph mgr module ls | grep -A 5 enabled_modules
    ceph dashboard create-self-signed-cert
    ceph mgr services
    echo "password" > pwdfile
    ceph dashboard ac-user-create admin  administrator -i pwdfile
    ceph config set mgr mgr/dashboard/server_addr 192.168.168.201
    ceph mgr services
# ceph 12 not support this module
    ceph mgr module enable pg_autoscaler
# cephfs init
    ceph osd pool create cephfs_data
    ceph osd pool create cephfs_metadata
    ceph fs new myfs cephfs_metadata cephfs_data
    ceph fs ls
    mount -t ceph {IP}:/ /mnt -oname=admin,secret=AU50JhycRCQ==
# add rgw user
    radosgw-admin user create --uid=cephtest --display-name="ceph test" --email=test@demo.com
    radosgw-admin user list
    radosgw-admin user info --uid=cephtest
    radosgw-admin user rm --uid=cephtest
    radosgw-admin bucket list
    radosgw-admin subuser create --uid=cephtest --subuser=cephtest:swift --access=full
    radosgw-admin key create --subuser=cephtest:swift --key-type=swift --gen-secret
    radosgw-admin user create --uid=admin --display-name=admin --access_key=admin --secret=123456
    radosgw-admin caps add --uid=admin --caps="users=read, write"
    radosgw-admin caps add --uid=admin --caps="usage=read, write"
    # radosgw-admin caps add --uid=admin --caps="users=read, write;usage=read, write;buckets=read, write"
# rgw delete realm/zonegroup/zone
    radosgw-admin realm delete --rgw-realm=${realm_name}
    radosgw-admin zonegroup delete --rgw-zonegroup=${zonegroup_name}
    radosgw-admin zone delete --rgw-zone=${zone_name}
# modify rgw configure
    radosgw-admin zonegroup get --rgw-zonegroup=cn > zonegroup.json
    # edit zonegroup.json
    radosgw-admin zonegroup set --rgw-zonegroup=cn --infile=zonegroup.json
    radosgw-admin period update --commit
# check master/secondary zone sync status
    radosgw-admin sync status
# secondary/master zone failover
    radosgw-admin zone modify --rgw-zone=${zone_name} --master --default
    radosgw-admin period update --commit
    systemctl restart ceph-radosgw@rgw.$(hostname)
EOF
