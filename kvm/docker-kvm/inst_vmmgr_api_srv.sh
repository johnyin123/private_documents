#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
VERSION+=("0cd01cc1[2025-09-16T07:54:25+08:00]:inst_vmmgr_api_srv.sh")
################################################################################
FILTER_CMD="cat"
LOGFILE=
APPFILES=(flask_app.py dbi.py database.py database.py.shm config.py meta.py utils.py main.py template.py vmmanager.py console.py)
APPDBS=(devices.json golds.json hosts.json iso.json vars.json)
TOOLS=(reload_dbtable)
################################################################################
log() { echo "$(tput setaf ${COLOR:-141})$*$(tput sgr0)" >&2; }
usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        -c|--docker              for docker env
        --mode          <db/shm> vmmgr api srv mode
                                  db : use database(config.py)
                                  shm: use shm json as persistent store
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
    log "file(${files[@]} ${APPFILES[@]} ${APPDBS[@]} ${TOOLS[@]})"
    for fn in ${files[@]} ${APPFILES[@]} ${APPDBS[@]}; do
        [ -e "${fn}" ] || { log "${fn} file, nofound"; exit 1;}
    done
    for fn in ${TOOLS[@]}; do
        [ -h "${fn}" ] && { log "${fn} can not be link"; exit 1; }
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
token_dir=/dev/shm/simplekvm/token
# VENV=
export PATH="${VENV:+${VENV}/bin:}${PATH}"

for svc in websockify-graph.service jwt-srv.service simple-kvm-srv.service etcd.service; do
    systemctl --user show ${svc} -p MemoryCurrent
    systemctl --user stop         ${svc} 2>/dev/null || true
    systemctl --user reset-failed ${svc} 2>/dev/null || true
done

systemd-run --user --unit etcd.service     --working-directory=${DIRNAME}     ${DIRNAME}/etcd
    # --listen-client-urls http://0.0.0.0:2379 --advertise-client-urls http://0.0.0.0:2379 --log-level 'warn'

systemd-run --user --unit websockify-graph \
    --working-directory=${DIRNAME} \
    websockify --token-plugin TokenFile --token-source ${token_dir} 127.0.0.1:6800

systemd-run --user --unit jwt-srv \
    --working-directory=${DIRNAME} \
    gunicorn -b 127.0.0.1:16000 --preload --workers=2 --threads=2 --access-logformat 'JWT %(r)s %(s)s %(M)sms len=%(B)s' --access-logfile='-' 'jwt_server:app'

# -E META_SRV=vmm.registry.local \ KVMHOST use.
# -E GOLD_SRV=vmm.registry.local \ ACTIONS use(this srv).
# -E CTRL_PANEL_SRV=guest.registry.local \
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
file_exists "${DIRNAME}/config" || cat <<EO_CONF > "${DIRNAME}/config"
StrictHostKeyChecking=no
UserKnownHostsFile=/dev/null
ControlMaster auto
ControlPath  ~/.ssh/%r@%h:%p
ControlPersist 600
Ciphers aes256-ctr,aes192-ctr,aes128-ctr
MACs hmac-sha1
EO_CONF
mkdir -p ${DIRNAME}/ssh_config.d
for f in cacert.pem clientcert.pem clientkey.pem config id_rsa id_rsa.pub; do
    file_exists "${DIRNAME}/${f}" || { echo "${f} === NO FOUND"; exit 1; }
done
systemd-run --user --unit simple-kvm-srv \
    --working-directory=${DIRNAME} \
    --property=UMask=0022 \
    --property=PrivateTmp=yes \
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
    -E TOKEN_DIR=${token_dir} \
    gunicorn -b 127.0.0.1:5009 --preload --workers=2 --threads=2 --access-logformat 'API %(r)s %(s)s %(M)sms len=%(B)s' --access-logfile='-' 'main:app'
EODOC
}
inst_app_outdir() {
    local outdir="${1}"
    local uid="${2}"
    local gid="${3}"
    log "install vmmgr DATA_DIR=${outdir}"
    install -v -d -m 0700 --group=${gid} --owner=${uid} ${outdir}
    local dirs=(actions devices domains meta)
    for dn in ${dirs[@]}; do
        install -v -d -m 0700 --group=${gid} --owner=${uid} ${outdir}/${dn}
        [ -d "${dn}" ] && {
            for fn in ${dn}/*; do
                log "install ${fn}"
                local mode=0600
                install -v -C -m ${mode} --group=${gid} --owner=${uid} ${fn} ${outdir}/${fn}
            done
        }
    done
}
copy_app() {
    local home_dir="${1}"
    local uid="${2}"
    local gid="${3}"
    local dbmode="${4}"
    for fn in ${APPFILES[@]}; do
        [ "${dbmode}" == "shm" ] && [ "${fn}" == "database.py" ] && continue
        [ "${dbmode}" == "shm" ] && [ "${fn}" == "dbi.py" ] && continue
        [ "${dbmode}" == "db" ] && [ "${fn}" == "database.py.shm" ] && continue
        local mode=0644
        [ "${fn}" == "console.py" ] && {
            mode=0755
            install -v -C -m ${mode} --group=${gid} --owner=${uid} ${fn} ${home_dir}/app/console
            continue
        }
        [ "${fn}" == "database.py.shm" ] && {
            install -v -C -m ${mode} --group=${gid} --owner=${uid} ${fn} ${home_dir}/app/database.py
            continue
        }
        install -v -C -m ${mode} --group=${gid} --owner=${uid} ${fn} ${home_dir}/app/${fn}
    done
}
gen_app_database() {
    local outdir="${1}"
    local uid="${2}"
    local gid="${3}"
    local dbmode="${4}"
    [ "${dbmode}" == "shm" ] && {
        for fn in ${APPDBS[@]}; do
            install -v -C -m 0644 --group=${gid} --owner=${uid} ${fn} ${outdir}/${fn}
        done
    }
    [ "${dbmode}" == "db" ] && {
        for fn in ${APPDBS[@]}; do
            ./reload_dbtable ${fn}
        done
        install -v -C -m 0644 --group=${gid} --owner=${uid} kvm.db ${outdir}/kvm.db
    }
    return 0
}
post_check() {
    local outdir="${1}"
    for fn in $(cat hosts.json | jq -r .[].tpl | sort | uniq | sed "/^$/d"); do
        log "check domain template: ${outdir}/domains/${fn}"
        [ -e "${outdir}/domains/${fn}" ] && { COLOR=2 log "OK"; } || { COLOR=1 log "NOT FOUND!!!"; }
    done
    for fn in $(cat devices.json | jq -r .[].tpl | sort | uniq | sed "/^$/d"); do
        log "check device template: ${outdir}/devices/${fn}"
        [ -e "${outdir}/devices/${fn}" ] && { COLOR=2 log "OK"; } || { COLOR=1 log "NOT FOUND!!!"; }
    done
    for fn in $(cat devices.json | jq -r .[].action | sort | uniq | sed "/^$/d"); do
        log "check device action: ${outdir}/actions/${fn}"
        [ -x "${outdir}/actions/${fn}" ] && { COLOR=2 log "OK"; } || { COLOR=1 log "NOT FOUND!!!"; }
    done
    for fn in $(cat golds.json | jq -r .[].tpl | sort | uniq | sed "/^$/d"); do
        log "check gold disk: ${fn}"
        [ -e "${fn}" ] && { COLOR=2 log "OK"; } || { COLOR=1 log "NOT FOUND!!!"; }
    done
    for fn in $(cat iso.json | jq -r .[].uri | sort | uniq | sed "/^$/d"); do
        srv=$(python3 -c 'import config; print(config.META_SRV)' || true)
        COLOR=3 log "NEED check ISO Image: http://${srv}${fn}"
    done
    return 0
}
main() {
    local docker='' target='' user="root" mode="db"
    local opt_short="ct:u:"
    local opt_long="docker,target:,user:,mode:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -c | --docker)  shift; docker=1;;
            --mode)         shift; mode=${1}; shift;;
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
    [ "${mode}" == "db" ] || [ "${mode}" == "shm" ] || usage "mode must db/shm"
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
    inst_app "${target}" "${USR_ID}" "${GRP_ID}" "${APP_OUTDIR}" "${mode}"
    inst_app_outdir "${OUTDIR}" "${USR_ID}" "${GRP_ID}"
    copy_app "${target}" "${USR_ID}" "${GRP_ID}" "${mode}"
    gen_app_database "${OUTDIR}" "${USR_ID}" "${GRP_ID}" "${mode}"
    post_check "${OUTDIR}"
    log "!!!!!!!modify ${target}/app/startup.sh start app!!!!!!!"
    log "devices.json golds.json hosts.json iso.json CAN READ-ONLY"
    return 0
}
main "$@"
