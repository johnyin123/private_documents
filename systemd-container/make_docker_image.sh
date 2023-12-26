#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("1a035a7[2023-12-26T09:37:05+08:00]:make_docker_image.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################
usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        docker env:
            ENABLE_SSH=true/false, enable/disable sshd startup on 60022, default disable
            # docker create -e ENABLE_SSH=true
        -c <type>           *          Dockerfile for <base|combine|firefox|chrome|aria|common docker file>
                                            combine: combine multiarch docker image
                                            firefox: need firefox.tar.xz rootfs with firefox install /opt/firefox
        -D <dirname>                   target dirname for generate files
        --registry <docker registry>   combine: use registry for combine multiarch, MUST SSL
                                       exam: registry.local
        --tag      <tag name>          combine: create new tag, for combine registry/tag-{{ARCH}} ==> registry/tag
                                       exam: debian:bookworm
                                       base: create base image tag
        --file     <tar.gz/tar.xz/..>  zip file for ADD
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
            # registry.local/debian:bookworm-amd64 registry.local/debian:bookworm-arm64, will combine
            ./${SCRIPTNAME} -c combine --registry registry.local --tag debian:bookworm
            # cp firefox.tar.xz mytarget/
            ./${SCRIPTNAME} -c firefox -D tttt
            # create goldimg
            ./${SCRIPTNAME} -c base -D mybase --file rootfs.tar.xz

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
    touch ${target_dir}/build.run.sh
    cfg_file=${target_dir}/Dockerfile
    write_file "${cfg_file}" <<EOF
$(echo -e "${action}")
LABEL maintainer="johnyin" name="${name}" build-date="$(date '+%Y%m%d%H%M%S')"
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Shanghai
COPY starter.sh /usr/local/bin/startup
COPY service /run_command
COPY build.run.sh /build.run
RUN { \\
        ln -snf /usr/share/zoneinfo/\$TZ /etc/localtime && echo \$TZ > /etc/timezone; \\
        mkdir -p /run/sshd && touch /usr/local/bin/startup && chmod 755 /usr/local/bin/startup; \\
        /bin/sh -x /build.run;  \\
        echo "ALL OK"; \\
        rm -rf /var/cache/apt/* /var/lib/apt/lists/* /root/.bash_history /build.run; \\
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
[ "${ENABLE_SSH:=false}" = "true" ] && ssh_cmd="/usr/sbin/sshd"
echo "Running command [ssh: ${ENABLE_SSH}]: '${CMD:-}${ARGS:+ $ARGS}'"
[ -z "${CMD:-}" ] && {
    echo "no service start"
    ${ssh_cmd:+${ssh_cmd} -D}
} || {
    ${ssh_cmd:+${ssh_cmd}}
    echo "service start ${CMD} ${ARGS:-}"
    exec "${CMD}" ${ARGS:-}
}
EOF
    cfg_file=${target_dir}/service
    write_file "${cfg_file}" <<'EOF'
# CMD=/usr/sbin/runuser
# ARGS="-u root -- /usr/bin/busybox sleep infinity"
EOF
    info_msg "gen dockerfile ok\n"
    info_msg " edit ${target_dir}/service for you service\n"
    info_msg " edit ${target_dir}/build.run.sh for you RUN commands for Dockerfile\n"
}
build_base() {
    local dir="${1}"
    local tag="${2}"
    local base="${3}"
    [ -e "${base}" ] || exit_msg "${base} no found\n"
    info_msg "copyt ${base} -> ${dir}/${base##*/}\n"
    try "mkdir -p '${dir}' && cat ${base} > ${dir}/${base##*/}"
    gen_dockerfile "goldimg" "${dir}" "${base}"
}
build_chrome() {
    local dir="${1}"
    local name=chrome
    local base="registry.local/debian:bookworm-amd64"
    local username=johnyin
    gen_dockerfile "${name}" "${dir}" "${base}"
    cfg_file=${dir}/build.run.sh
    write_file "${cfg_file}" <<EOF
touch /etc/default/google-chrome
echo 'deb [arch=amd64 trusted=yes] http://dl.google.com/linux/chrome/deb/ stable main' > /etc/apt/sources.list.d/google.list
apt update
apt -y install --no-install-recommends google-chrome-stable && useradd -m ${username} --home-dir /home/${username}/
EOF
    cfg_file=${dir}/Dockerfile
    write_file "${cfg_file}" append <<EOF
VOLUME ["/home/${username}/"]
EOF
    cfg_file=${dir}/service
    write_file "${cfg_file}" <<EOF
CMD=/usr/sbin/runuser
ARGS="-u ${username} -- /opt/google/chrome/google-chrome --no-sandbox"
EOF
    cat <<'EOF'
docker create --network br-ext -e ENABLE_SSH=true -e DISPLAY=unix$DISPLAY -v /testhome:/home/johnyin chrome
xhost +127.0.0.1
EOF
}
build_firefox() {
    local dir="${1}"
    local name=firefox
    local rootfs_with_firefox=firefox.tar.xz
    local username=johnyin
    [ -e "${dir}/${rootfs_with_firefox}" ] || exit_msg "${dir}/${rootfs_with_firefox} file no found\n"
    gen_dockerfile "${name}" "${dir}" "${rootfs_with_firefox}"
    cfg_file=${dir}/build.run.sh
    write_file "${cfg_file}" <<EOF
useradd -m ${username} --home-dir /home/${username}/
EOF
    cfg_file=${dir}/Dockerfile
    write_file "${cfg_file}" append <<EOF
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
    cfg_file=${dir}/build.run.sh
    write_file "${cfg_file}" <<EOF
useradd -m ${username} --home-dir /home/${username}/
apt -y -oAcquire::AllowInsecureRepositories=true update
apt -y -oAcquire::AllowInsecureRepositories=true install aria2
EOF
    cfg_file=${dir}/Dockerfile
    write_file "${cfg_file}" append <<EOF
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
    local func="" dir="" registry="" tag="" file=""
    local opt_short="c:D:"
    local opt_long="registry:,tag:,file:,"
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
            --file)         shift; file=${1}; shift;;
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
        base)
                    [ -z "${file}" ] && usage "base mode, file must input"
                    build_base "${dir:-goldimg}" "${tag}" "${file}"
                    ;;
        combine)
                    [ -z "${registry}" ] && usage "combine mode, registry must input"
                    [ -z "${tag}" ] && usage "combine mode, tag must input"
                    combine_multiarch "${registry}" "${tag}"
                    ;;
        firefox)    build_firefox "${dir:-firefox}";;
        chrome)     build_chrome "${dir:-chrome}";;
        aria)       build_aria2 "${dir:-aria2}";;
        *)          gen_dockerfile "${func}" "${dir:-${func}-common-demo}" "registry.local/debian:bookworm-amd64"
                    gen_dockerfile "${func}" "${dir:-${func}-scratch-demo}"
                    ;;
    esac
    return 0
}
main "$@"
