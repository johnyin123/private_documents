#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
VERSION+=("e1302c73[2025-10-11T08:55:04+08:00]:inst_vmmgr_api_srv.sh")
################################################################################
FILTER_CMD="cat"
LOGFILE=
APPFILES=(flask_app.py database.py config.py meta.py utils.py main.py template.py vmmanager.py console.py)
APPDBS=(devices.json golds.json hosts.json iso.json vars.json devices/ domains/ meta/)
export PYTHONDONTWRITEBYTECODE=1
################################################################################
log() { echo "$(tput setaf ${COLOR:-141})$*$(tput sgr0)" >&2; }
usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        -c|--docker              for docker env
        -t|--target   * <str>    target directory install apphome
        -u|--user    <username>  non docker env, username for run/inst app 
                                 default root
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
EOF
    exit 1
}
check_depends() {
    local docker="${1}"
    local files=()
    [ "${docker}" == "1" ] && {
        files+=(cacert.pem clientkey.pem clientcert.pem id_rsa id_rsa.pub)
    }
    local cmds=(socat ssh jq qemu-img cat)
    log "file(${files[@]} ${APPFILES[@]} ${APPDBS[@]})"
    for fn in ${files[@]} ${APPFILES[@]} ${APPDBS[@]}; do
        [ -e "${fn}" ] || { log "${fn} file, nofound"; exit 1;}
    done
    [ "${docker}" == "1" ] || {
        log "cmd(${cmds[@]})"
        for cmd in ${cmds[@]}; do
            command -v "${cmd}" &> /dev/null || { log "${cmd} nofound"; exit 1;}
        done
    }
    return 0
}
inst_app() {
    local home_dir="${1}"
    local uid="${2}"
    local gid="${3}"
    local outdir="${4}"
    local docker="${5}"
    install -v -d -m 0755 --group=${gid} --owner=${uid} ${home_dir}
    [ "${docker}" == "1" ] && {
        log "install PKI"
        install -v -d -m 0755 ${home_dir}/pki/CA
        install -v -d -m 0755 ${home_dir}/pki/libvirt/private
        openssl x509 -text -noout -in clientcert.pem | grep -E 'DNS|Before|After' | sed 's/^\s*//g'
        install -v -C -m 0644 cacert.pem ${home_dir}/pki/CA/cacert.pem
        install -v -C -m 0644 clientkey.pem ${home_dir}/pki/libvirt/private/clientkey.pem
        install -v -C -m 0644 clientcert.pem ${home_dir}/pki/libvirt/clientcert.pem
        log "install SSH key" && install -v -d -m 0700 --group=${gid} --owner=${uid} ${home_dir}/.ssh && {
            install -v -C -m 0600 --group=${gid} --owner=${uid} id_rsa ${home_dir}/.ssh/id_rsa
            install -v -C -m 0644 --group=${gid} --owner=${uid} id_rsa.pub ${home_dir}/.ssh/id_rsa.pub
            cat <<EO_DOC | install -v -C -m 0644 --group=${gid} --owner=${uid} /dev/stdin ${home_dir}/.ssh/config
StrictHostKeyChecking=no
UserKnownHostsFile=/dev/null
Host *
    ControlMaster auto
    ControlPath /tmp/vmmgr-%r@%h-%p
    ControlPersist 600
    Ciphers aes256-ctr,aes192-ctr,aes128-ctr
    MACs hmac-sha1
EO_DOC
        }
    }
    log "install ${home_dir}/app/startup.sh"
    install -v -d -m 0755 --group=${gid} --owner=${uid} ${home_dir}/app
    [ "${docker}" == "1" ] || outdir=$(realpath "${outdir}")
    cat <<'EODOC' | install -v -C -m 0755 --group=${gid} --owner=${uid} /dev/stdin ${home_dir}/app/startup.sh
#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
outdir=/dev/shm/simplekvm/work
tokdir=/dev/shm/simplekvm/token
rm -rf ${tokdir} ${outdir}
# VENV=
export PATH="${VENV:+${VENV}/bin:}${PATH}"

for svc in websockify-graph.service jwt-srv.service simple-kvm-srv.service etcd.service; do
    systemctl --user show ${svc} -p MemoryCurrent
    systemctl --user stop         ${svc} 2>/dev/null || true
    systemctl --user reset-failed ${svc} 2>/dev/null || true
done

systemd-run --user --unit etcd.service \
    --working-directory=${DIRNAME} \
    -E ETCD_LISTEN_CLIENT_URLS=http://0.0.0.0:2379    \
    -E ETCD_ADVERTISE_CLIENT_URLS=http://0.0.0.0:2379 \
    -E ETCD_LOG_LEVEL='warn'                          \
    ${DIRNAME}/etcd
    #--listen-client-urls http://0.0.0.0:2379 --advertise-client-urls http://0.0.0.0:2379 --log-level 'warn'

systemd-run --user --unit websockify-graph \
    --working-directory=${DIRNAME} \
    websockify --token-plugin TokenFile --token-source ${tokdir} 127.0.0.1:6800

systemd-run --user --unit jwt-srv \
    --working-directory=${DIRNAME} \
    --property=UMask=0022 \
    -E LEVELS='{"api_auth":"DEBUG"}' \
    -E JWT_CERT_PEM=/etc/nginx/ssl/simplekvm.pem \
    -E JWT_CERT_KEY=/etc/nginx/ssl/simplekvm.key \
    -E LDAP_SRV_URL=ldap://192.168.169.192:10389 \
    gunicorn -b 127.0.0.1:16000 --preload --workers=2 --threads=2 --access-logformat 'JWT %(r)s %(s)s %(M)sms len=%(B)s' --access-logfile='-' 'api_auth:app'

# -E META_SRV=vmm.registry.local \ KVMHOST use.
# -E GOLD_SRV=vmm.registry.local \ ACTIONS use(this srv).
# -E CTRL_SRV=guest.registry.local \
# -E LEVELS='{"utils":"DEBUG","database":"INFO"}' \
# -E ETCD_PREFIX=/simple-kvm/work \
# -E ETCD_SRV=etcd-server \
# -E ETCD_CA=ca.pem \
# -E ETCD_KEY=etcd-cli.key \
# -E ETCD_CERT=etcd-cli.pem \
# -E DATA_DIR=/dev/shm/simple-kvm/work \
# -E TOKEN_DIR=/dev/shm/simple-kvm/token \
#
# rm -f /etc/ssh/ssh_config.d/20-systemd-ssh-proxy.conf /or, for BindPaths --user owner 65534:65534
file_exists() { [ -f "$1" ]; }
mkdir -p ${DIRNAME}/deps/ssh_config.d
file_exists "${DIRNAME}/deps/config" || cat <<EO_CONF > "${DIRNAME}/deps/config"
StrictHostKeyChecking=no
UserKnownHostsFile=/dev/null
ControlMaster auto
ControlPath  ~/.ssh/%r@%h:%p
ControlPersist 600
Ciphers aes256-ctr,aes192-ctr,aes128-ctr
MACs hmac-sha1
EO_CONF
for f in cacert.pem clientcert.pem clientkey.pem config id_rsa id_rsa.pub; do
    file_exists "${DIRNAME}/deps/${f}" || { echo "deps/${f} === NO FOUND"; exit 1; }
done

systemd-run --user --unit simple-kvm-srv \
    --working-directory=${DIRNAME} \
    --property=UMask=0022 \
    --property=BindReadOnlyPaths=${DIRNAME}/ssh_config.d:/etc/ssh/ssh_config.d \
    --property=BindPaths=${DIRNAME}/config:$HOME/.ssh/config \
    --property=BindReadOnlyPaths=${DIRNAME}/id_rsa:$HOME/.ssh/id_rsa \
    --property=BindReadOnlyPaths=${DIRNAME}/id_rsa.pub:$HOME/.ssh/id_rsa.pub \
    --property=BindReadOnlyPaths=${DIRNAME}/cacert.pem:$HOME/.pki/libvirt/cacert.pem \
    --property=BindReadOnlyPaths=${DIRNAME}/clientkey.pem:$HOME/.pki/libvirt/clientkey.pem \
    --property=BindReadOnlyPaths=${DIRNAME}/clientcert.pem:$HOME/.pki/libvirt/clientcert.pem \
    -E ETCD_PREFIX=/simple-kvm/work \
    -E ETCD_SRV=127.0.0.1 \
    -E ETCD_PORT=2379 \
    -E DATA_DIR=${outdir} \
    -E TOKEN_DIR=${tokdir} \
    gunicorn -b 127.0.0.1:5009 --preload --workers=2 --threads=2 --access-logformat 'API %(r)s %(s)s %(M)sms len=%(B)s' --access-logfile='-' 'main:app'
EODOC
}
copy_app() {
    local home_dir="${1}"
    local uid="${2}"
    local gid="${3}"
    for fn in ${APPFILES[@]}; do
        local mode=0644
        [ "${fn}" == "console.py" ] && {
            mode=0755
            install -v -C -m ${mode} --group=${gid} --owner=${uid} ${fn} ${home_dir}/app/console
            continue
        }
        install -v -C -m ${mode} --group=${gid} --owner=${uid} ${fn} ${home_dir}/app/${fn}
    done
}
gen_restore_tgz() {
    tar c ${APPDBS[@]} | gzip > restore.tgz
    log "gen restore.tgz........."
    return 0
}
main() {
    local docker='' target='' user="root"
    local opt_short="ct:u:"
    local opt_long="docker,target:,user:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -c | --docker)  shift; docker=1;;
            -t | --target)  shift; target=${1}; shift;;
            -u | --user)    shift; user=${1}; shift;;
            ########################################
            -q | --quiet)   shift; FILTER_CMD=;;
            -l | --log)     shift; LOGFILE=${1}; shift;;
            -d | --dryrun)  shift; DRYRUN=1;;
            -V | --version) shift; for _v in "${VERSION[@]}"; do echo "$_v"; done; exit 0;;
            -h | --help)    shift; usage;;
            --)             shift; break;;
            *)              usage "Unexpected option: $1";;
        esac
    done
    [ "$(id -u)" -eq 0 ] || { log "root need!"; exit 1; }
    exec > >(${FILTER_CMD:-sed '/^\s*#/d'} | tee ${LOGFILE:+-i ${LOGFILE}})
    [ -z "${target}" ] && usage "target dir must input"
    [ -d "${target}" ] && { log "${target} directory exist!!!"; exit 2; }
    id "${user}" >/dev/null || exit 3
    check_depends "${docker}"
    local USR_ID=$(id -u ${user})
    local GRP_ID=$(id -g ${user})
    local USR_NAME=$(id -un ${user})
    local OUTDIR="${target}/work"
    local APP_OUTDIR="${OUTDIR}"
    [ "${docker}" == "1" ] && {
        USR_ID=10001
        GRP_ID=10001
        USR_NAME=johnyin
        APP_OUTDIR="/home/${USR_NAME}/work"
        log "${target}     ->docker:/home/${USR_NAME}"
        log "${target}/pki ->docker:/etc/pki"
    }
    inst_app "${target}" "${USR_ID}" "${GRP_ID}" "${APP_OUTDIR}" "${docker}"
    copy_app "${target}" "${USR_ID}" "${GRP_ID}"
    gen_restore_tgz
    log "!!!!!!!modify ${target}/app/startup.sh start app!!!!!!!"
    log "devices.json golds.json hosts.json iso.json CAN READ-ONLY"
    return 0
}
main "$@"
