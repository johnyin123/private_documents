#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
VERSION+=("initver[2025-04-17T09:54:16+08:00]:inst_vmmgr_api_srv.sh")
################################################################################
FILTER_CMD="cat"
LOGFILE=
################################################################################
log() { echo "$(tput setaf 141)$*$(tput sgr0)" >&2; }
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
    local files=(cacert.pem clientkey.pem clientcert.pem id_rsa id_rsa.pub)
    log "file(${files[@]})"
    for fn in ${files[@]}; do
        [ -e "${fn}" ] || { log "${fn} file, nofound"; exit 1;}
    done
}
inst_app() {
    local home_dir="${1}"
    local uid="${2}"
    local gid="${3}"
    local outdir="${4}"
    install -v -d -m 0755 --group=${gid} --owner=${uid} ${home_dir}
    log "install PKI"
    install -v -d -m 0755 ${home_dir}/pki/CA
    install -v -d -m 0755 ${home_dir}/pki/libvirt/private
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
    log "install ${home_dir}/app/startup.sh"
    install -v -d -m 0755 --group=${gid} --owner=${uid} ${home_dir}/app
    cat <<EODOC | install -v -C -m 0755 --group=${gid} --owner=${uid} /dev/stdin ${home_dir}/app/startup.sh
#!/usr/bin/env bash
export OUTDIR=${outdir}
pkill --uid johnyin -9 websockify || true
pkill --uid johnyin -9 gunicorn || true
nohup websockify --token-plugin TokenFile --token-source \${OUTDIR}/token/ 127.0.0.1:6800 &>\${OUTDIR}/websockify.log &
gunicorn -b 127.0.0.1:5009 --preload --workers=2 --threads=2 --access-logfile='-' 'main:app'
EODOC
}
inst_app_outdir() {
    local outdir="${1}"
    local uid="${2}"
    local gid="${3}"
    log "install vmmgr OUTDIR=${outdir}"
    install -v -d -m 0755 --group=${gid} --owner=${uid} ${outdir}
    install -v -d -m 0755 --group=${gid} --owner=${uid} ${outdir}/iso
    install -v -d -m 0755 --group=${gid} --owner=${uid} ${outdir}/gold
    install -v -d -m 0755 --group=${gid} --owner=${uid} ${outdir}/token
    install -v -d -m 0755 --group=${gid} --owner=${uid} ${outdir}/nocloud
    install -v -d -m 0755 --group=${gid} --owner=${uid} ${outdir}/request
    local dirs=(actions devices domains meta)
    for dn in ${dirs[@]}; do
        install -v -d -m 0755 --group=${gid} --owner=${uid} ${outdir}/${dn}
        [ -d "${dn}" ] && {
            for fn in ${dn}/*; do
                log "install ${fn}"
                local mode=0644
                [ "${dn}" == "actions" ] && mode=0755
                install -v -C -m ${mode} --group=${gid} --owner=${uid} ${fn} ${outdir}/${fn}
            done
        }
    done
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
    check_depends
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
    inst_app "${target}" "${USR_ID}" "${GRP_ID}" "${APP_OUTDIR}"
    inst_app_outdir "${OUTDIR}" "${USR_ID}" "${GRP_ID}"
    log "!!!!!!!copy app in ${target}/app!!!!!!!"
    log "!!!!!!!modify ${target}/app/startup.sh start app!!!!!!!"
    [ "${docker}" == "1" ] && cat <<EODOC
# --network host \
docker run --rm \\
    --name vmmgr-api \\
    --network br-int --ip 192.168.169.123 \\
    -v ${target}:/home/${USR_NAME} \\
    registry.local/libvirtd/vmmgr:bookworm
EODOC
    return 0
}
main "$@"
