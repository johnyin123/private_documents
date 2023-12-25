#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("d7982fa[2023-12-25T12:22:04+08:00]:make_docker_image.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################
usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        -c <type>           *          Dockerfile for <combine|firefox|aria|common docker file>
                                            combine: combine multiarch docker image
                                            firefox: need firefox.tar.xz rootfs with firefox install /opt/firefox
        -D <dirname>                   target dirname for generate files
        --registry <docker registry>   combine: use registry for combine multiarch, MUST SSL
                                       exam: registry.local
        --tag      <tag name>          combine: create new tag, for combine registry/tag-{{ARCH}} ==> registry/tag
                                       exam: debian:bookworm 
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
            # registry.local/debian:bookworm-amd64 registry.local/debian:bookworm-arm64, will combine
            ./${SCRIPTNAME} -c combine --registry registry.local --tag debian:bookworm
            # cp firefox.tar.xz mytarget/
            ./${SCRIPTNAME} -c firefox -D tttt
EOF
    exit 1
}
gen_dockerfile() {
    local name=${1}
    local target_dir=${2}
    local base_img=${3:-}
    local action="FROM ${base_img}"
    [ -e "${target_dir}/${base_img}" ] && action="FROM scratch\nADD ${base_img##*/} /\n"
    [ -z "${base_img}" ] && action="FROM scratch\nADD rootfs.tar.xz /\n"
    try mkdir -p "${target_dir}"
    cfg_file=${target_dir}/Dockerfile
    write_file "${cfg_file}" <<EOF
$(echo -e "${action}")
LABEL maintainer="johnyin" name="${name}" build-date="$(date '+%Y%m%d%H%M%S')"
ENV DEBIAN_FRONTEND=noninteractive
COPY starter.sh /usr/local/bin/startup
COPY service /run_command
RUN { \\
        mkdir -p /run/sshd && touch /usr/local/bin/startup && chmod 755 /usr/local/bin/startup; \\
        echo "ALL OK"; \\
        rm -rf /var/cache/apt/* /var/lib/apt/lists/* /root/.bash_history; \\
    }
ENTRYPOINT ["dumb-init", "--"]
CMD ["/usr/local/bin/startup"]
EOF
    cfg_file=${target_dir}/starter.sh
    write_file "${cfg_file}" <<'EOF'
#!/bin/bash
set -o errexit
set -o pipefail
set -o nounset
set -o xtrace
[ -e "/run_command" ] && source /run_command
echo "Running command: '${CMD:-}${ARGS:+ $ARGS}'"
[ -z "${CMD:-}" ] && /usr/sbin/sshd -D || {
    /usr/sbin/sshd -D&
    exec ${CMD} ${ARGS:-}
}
EOF
    cfg_file=${target_dir}/service
    write_file "${cfg_file}" <<EOF
# CMD=sleep infinity
# ARGS=
EOF
}
build_firefox() {
    local dir="${1}"
    local name=firefox
    local rootfs_with_firefox=firefox.tar.xz
    local username=johnyin
    [ -e "${dir}/${rootfs_with_firefox}" ] || exit_msg "${dir}/${rootfs_with_firefox} file no found\n"
    gen_dockerfile "${name}" "${dir}" "${rootfs_with_firefox}"
    cfg_file=${dir}/Dockerfile
    write_file "${cfg_file}" append <<EOF
RUN { \\
        useradd -m ${username} --home-dir /home/${username}/; \\
    }
VOLUME ["/home/${username}/"]
EOF
    cfg_file=${dir}/service
    write_file "${cfg_file}" <<EOF
CMD=/usr/bin/su
ARGS="${username} -c '/opt/firefox/firefox'"
# CMD=/usr/sbin/runuser
# ARGS="-u johnyin -- /opt/google/chrome/google-chrome --no-sandbox"
EOF
    cat <<'EOF'
docker create --network br-ext -e DISPLAY=unix$DISPLAY -v /tmp/.X11-unix:/tmp/.X11-unix -v /testhome:/home/johnyin chrome
# xhost +127.0.0.1
# apt -y update && apt -y --no-install-recommends install libgtk-3-0 libnss3 libssl3 libdbus-glib-1-2 libx11-xcb1 libxtst6 libasound2 fonts-noto-cjk
docker build -t firefox .
docker create --network internet --ip 192.168.169.2 --dns 8.8.8.8 \
    --cpuset-cpus 0 \
    --memory 512mb \
    --hostname myinternet --name firefox \
    -v /testhome:/home/johnyin \
    -e DISPLAY=unix${DISPLAY} \
    -v /dev/shm:/dev/shm \
    -v /tmp/.X11-unix:/tmp/.X11-unix \
    --device /dev/snd \
    --device /dev/dri \
    firefox
EOF
}
build_aria2() {
    local dir="${1}"
    local name=aria2
    local base="registry.local/debian:bookworm-amd64"
    local username=johnyin
    gen_dockerfile "${name}" "${dir}" "${base}"
    cfg_file=${dir}/Dockerfile
    write_file "${cfg_file}" append <<EOF
RUN { \\
        useradd -m ${username} --home-dir /home/${username}/; \\
        apt -y -oAcquire::AllowInsecureRepositories=true update \\
            && apt -y -oAcquire::AllowInsecureRepositories=true install aria2; \\ 
    }
VOLUME ["/home/${username}/"]
EOF
    cfg_file=${dir}/service
    write_file "${cfg_file}" <<EOF
CMD=/usr/bin/su
ARGS="${username} -c '/usr/bin/aria2c --conf-path=\${HOME}/.aria2/aria2.conf'"
EOF
    cat <<'EOF'
docker build --network=host -t aria2 .
# # add /fakehome/.aria/ configurations files!!
docker create --network internet --ip 192.168.169.3 --dns 8.8.8.8 
    --hostname mydownloader --name aria \
    -v /fakehome:/home/johnyin \
    aria2
EOF
}
combine_multiarch() {
    local registry="${1}"
    local img_tag="${2}"
    local ARCH=(amd64 arm64)
    warn_msg "registry must has ssl access\n"
    try "docker manifest rm ${registry}/${img_tag} 2>/dev/null || true"
    local arch_args=""
    for arch in ${ARCH[@]}; do
        arch_args+=" --amend ${registry}/${img_tag}-${arch}"
    done
    try docker manifest create --insecure ${registry}/${img_tag} ${arch_args}
    for arch in ${ARCH[@]}; do
        try docker manifest annotate --arch ${arch} ${registry}/${img_tag} ${registry}/${img_tag}-${arch}
    done
    try docker manifest inspect ${registry}/${img_tag}
    try docker manifest push --insecure ${registry}/${img_tag}
    for arch in ${ARCH[@]}; do
        info_msg "++++++++++++++++++check ${arch} start++++++++++++++++++"
        try docker pull -q ${registry}/${img_tag} --platform ${arch}
        try docker run --entrypoint="uname" ${registry}/${img_tag} -m
    done
}
main() {
    local func="" dir="" registry="" tag=""
    local opt_short="c:D:"
    local opt_long="registry:,tag:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -c)             shift; func=${1}; shift;;
            -D)             shift; dir=${1}; shift;;
            --registry)     shift; registry=${1}; shift;;
            --tag)          shift; tag=${1}; shift;;
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
    [ -z "${func}" ] && usage "-c <func type>"
    case "${func}" in
        combine)
                    [ -z "${registry}" ] && usage "combine mode, registry must input"
                    [ -z "${tag}" ] && usage "combine mode, tag must input"
                    combine_multiarch "${registry}" "${tag}"
                    ;;
        firefox)    build_firefox "${dir:-firefox}";;
        aria)       build_aria2 "${dir:-aria2}";;
        *)          gen_dockerfile "${func}" "${dir:-common-demo}" "registry.local/debian:bookworm-amd64"
                    gen_dockerfile "${func}" "${dir:-scratch-demo}"
                    ;;
    esac
    return 0
}
main "$@"
