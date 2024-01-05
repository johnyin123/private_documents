#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("21db4ee[2024-01-04T09:42:50+08:00]:make_docker_image.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################
REGISTRY=${REGISTRY:-registry.local}
NAMESPACE=${NAMESPACE:-}
IMAGE=${IMAGE:-debian:bookworm}
readonly DIRNAME_COPYIN=docker
BASE_IMG="${REGISTRY}/${NAMESPACE:+${NAMESPACE}/}${IMAGE}"
usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        env: REGISTRY: private registry server(ssl), default registry.local
             NAMESPACE: image namespace, default "", no namespace use
             IMAGE: image name with tag, default debian:bookworm
             so, default multi arch baseimage: <REGISTRY>/<NAMESPACE>/<IMG:TAG>
        docker env:
            ENABLE_SSH=true/false, enable/disable sshd startup on 60022, default disable
            # docker create -e ENABLE_SSH=true
        -c <type>           *          Dockerfile for <base|combine|firefox|chrome|aria|nginx|xfce|common docker file>
                                            combine: combine multiarch docker image
                                            firefox: need firefox.tar.xz rootfs with firefox install /opt/firefox
        -D <dirname>                   target dirname for generate files
        --arch     <arch>              images arch(amd64/arm64), not set use same as baseimg, if baseimg is multiarch, need set arch
        --tag      <tag name>          combine: create new tag, for combine registry/tag-{{ARCH}} ==> registry/tag
                                       exam: debian:bookworm
                                       base: create base image tag
        --file     <tar.gz/tar.xz/..>  zip file for ADD
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
         # # cp firefox.tar.xz mytarget/
            ./${SCRIPTNAME} -c firefox -f firefox_rootfs.tar.xz -D myfirefox
         # # create goldimg
            ARCH=(amd64 arm64)
            for arch in \${ARCH[@]}; do
                ./${SCRIPTNAME} -c base -D base-\${arch} --arch \${arch} --file \${arch}.tar.xz
                (cd base-\${arch} && docker build -t ${BASE_IMG}-\${arch} .)
                docker push ${BASE_IMG}-\${arch}
            done
            ./${SCRIPTNAME} -c combine --tag ${BASE_IMG}
         # # multiarch aria2
            ARCH=(amd64 arm64)
            type=aria
            for arch in \${ARCH[@]}; do
                ./${SCRIPTNAME} -c \${type} -D my\${type}-\${arch} --arch \${arch}
                # confirm base-image is right arch
                docker pull --quiet ${BASE_IMG} --platform \${arch}
                docker run --rm --entrypoint="uname" ${BASE_IMG} -m
                (cd my\${type}-\${arch} && docker build --network=br-ext -t ${REGISTRY}/${NAMESPACE:+${NAMESPACE}/}\${type}:bookworm-\${arch} .)
                docker push ${REGISTRY}/${NAMESPACE:+${NAMESPACE}/}\${type}:bookworm-\${arch}
            done
            ./${SCRIPTNAME} -c combine --tag ${REGISTRY}/${NAMESPACE:+${NAMESPACE}/}\${type}:bookworm
EOF
    exit 1
}
gen_dockerfile() {
    local name=${1}
    local target_dir=${2}
    local base_img=${3:-}
    local arch=${4:-}
    # FROM --platform=$BUILDPLATFORM
    # Automatic platform ARGs in the global scope
    local action="FROM ${arch:+--platform=${arch} }${base_img}"
    [ -e "${target_dir}/${base_img}" ] && action="FROM ${arch:+--platform=${arch} }scratch\nADD ${base_img##*/} /\n"
    [ -z "${base_img}" ] && action="FROM ${arch:+--platform=${arch} }scratch\nADD rootfs.tar.xz /\n"
    # # Override user name at build. If build-arg is not passed, will create user named `default_user`
    # ARG DOCKER_USER=default_user
    # RUN useradd ${DOCKER_USER}
    cfg_file=${target_dir}/Dockerfile
    try mkdir -p "${target_dir}" && write_file "${cfg_file}" <<EOF
$(echo -e "${action}")
LABEL maintainer="johnyin" name="${name}${arch:+-${arch}}" build-date="$(date '+%Y%m%d%H%M%S')"
ENV TZ=Asia/Shanghai
ADD ${DIRNAME_COPYIN} /
RUN set -eux && { \\
        export DEBIAN_FRONTEND=noninteractive; \\
        ln -snf /usr/share/zoneinfo/\$TZ /etc/localtime && echo \$TZ > /etc/timezone; \\
        mkdir -p /run/sshd && touch /usr/local/bin/startup && chmod 755 /usr/local/bin/startup; \\
        rm -f /etc/ssh/ssh_host_* && ssh-keygen -A; \\
        /bin/sh -o errexit -x /build.run;  \\
        echo "ALL OK"; \\
        rm -rf /var/cache/apt/* /var/lib/apt/lists/* /root/.bash_history /build.run; \\
    }
ENTRYPOINT ["dumb-init", "--"]
CMD ["/usr/local/bin/startup"]
EOF
    try mkdir -p ${target_dir}/${DIRNAME_COPYIN} && try touch ${target_dir}/${DIRNAME_COPYIN}/build.run
    cfg_file=${target_dir}/${DIRNAME_COPYIN}/usr/local/bin/startup
    try mkdir -p ${target_dir}/${DIRNAME_COPYIN}/usr/local/bin && write_file "${cfg_file}" <<'EOF'
#!/bin/bash
set -o errexit
set -o pipefail
set -o nounset
set -o xtrace
[ -e "/run_command" ] && source /run_command
[ "${ENABLE_SSH:=false}" = "true" ] && ssh_cmd="/usr/sbin/sshd"
echo "Running command [ssh: ${ENABLE_SSH}]: '${CMD:-}${ARGS:+ $ARGS}'"
command -v "ip" &> /dev/null && ip a || { command -v "busybox" && busybox ip a; }
[ -z "${CMD:-}" ] && {
    echo "no service start"
    ${ssh_cmd:+${ssh_cmd} -D}
} || {
    ${ssh_cmd:+${ssh_cmd}}
    echo "service start ${CMD} ${ARGS:-}"
    eval exec "${CMD}" ${ARGS:-}
}
EOF
    cfg_file=${target_dir}/${DIRNAME_COPYIN}/run_command
    try mkdir -p ${target_dir}/${DIRNAME_COPYIN} && write_file "${cfg_file}" <<'EOF'
# CMD=/usr/sbin/runuser
# ARGS="-u root -- /usr/bin/busybox sleep infinity"
EOF
    info_msg "gen dockerfile ok\n"
    info_msg " edit ${target_dir}/${DIRNAME_COPYIN}/run_command for you service\n"
    info_msg " edit ${target_dir}/${DIRNAME_COPYIN}/build.run for you RUN commands for Dockerfile\n"
}
build_base() {
    local dir="${1}"
    local tag="${2}"
    local base="${3}"
    local arch="${4:-}"
    [ -e "${base}" ] || exit_msg "${base} no found\n"
    info_msg "copyt ${base} -> ${dir}/${base##*/}\n"
    try "mkdir -p '${dir}' && cat ${base} > ${dir}/${base##*/}"
    gen_dockerfile "goldimg" "${dir}" "${base}" "${arch}"
}
build_xfceweb() {
    local dir="${1}"
    local arch=${2:-}
    local name=xfce
    local base="${BASE_IMG}"
    local username=johnyin
    gen_dockerfile "${name}" "${dir}" "${base}" "${arch}"
    cfg_file=${dir}/${DIRNAME_COPYIN}/build.run
    write_file "${cfg_file}" <<EOF
getent passwd ${username} >/dev/null || useradd -m ${username} --home-dir /home/${username}/ --shell /bin/bash
# wget -q -O- 'https://xpra.org/xpra.asc' | apt-key add -
# echo "deb [trusted=yes] https://xpra.org/ bookworm main" > /etc/apt/sources.list.d/xpra.list
apt -y update || true
apt -y install xserver-xorg xserver-xorg-video-dummy xfce4 xfce4-terminal dbus-x11
# fonts-noto-cjk
# fcitx5 fcitx5-pinyin fcitx5-chinese-addons fcitx5-frontend-gtk2 fcitx5-frontend-gtk3 fcitx5-frontend-qt5
apt -y install xpra
mkdir -m0755 -p /run/user/\$(id -u ${username})
chown -R ${username}:${username} /run/user/\$(id -u ${username})
cat <<EOC > /etc/xpra/xpra.conf
uid=\$(id -u ${username})
gid=\$(id -g ${username})
start=xfce4-session
xvfb=/usr/bin/Xvfb +extension Composite +extension GLX +extension RANDR +extension RENDER -nolisten tcp -dpi 96 -ac -r -cc 4 -accessx -xinerama -auth /home/${username}/.Xauthority
html=on
# authenticate using password, docker -e XPRA_PASSWORD=mypassword
# tcp-auth=env
# enable HTML5 client
bell=no
dbus-control=no
dbus-launch=no
dbus-proxy=no
mdns=no
notifications=no
printing=no
pulseaudio=no
systemd-run=no
webcam=no
# ssl=auto
# ssl-cert=/etc/xpra/ssl-cert.pem
# ssl-client-verify-mode=none
EOC
# {
#     for i in \$(locale); do
#         echo start-env=\$i
#     done
# } >> /etc/xpra/xpra.conf
EOF
    cfg_file=${dir}/Dockerfile
    write_file "${cfg_file}" append <<EOF
VOLUME ["/home/${username}/"]
EOF
    cfg_file=${dir}/${DIRNAME_COPYIN}/run_command
    write_file "${cfg_file}" <<EOF
CMD="xpra"
ARGS="start-desktop --daemon=no --bind-tcp=0.0.0.0:\${PORT:-9999}"
# CMD=/usr/sbin/runuser
# ARGS="-u ${username} -- xpra start-desktop --daemon=no"
# --auth=file --password-file=./password.txt
EOF
    cat <<'EOF'
docker create --name xfce --hostname xfce \
    --network br-ext --ip 192.168.169.100 --dns 8.8.8.8 \
    -e ENABLE_SSH=true \
    -e PORT=9999 -e SCREEN_SIZE=1024x768 \
    -v /home/johnyin/disk/docker_home/:/home/johnyin/:rw \
    -v /usr/share/fonts/opentype/noto/:/usr/share/fonts/opentype/noto/:ro \
    registry.local/xfce:bookworm-amd64
curl http://192.168.169.100:9999
EOF
}
build_chrome() {
    local dir="${1}"
    local arch=${2:-}
    local name=chrome
    local base="${BASE_IMG}"
    local username=johnyin
    str_equal "${arch}" "amd64" || exit_msg "chrome only support arch: amd64!!\n"
    gen_dockerfile "${name}" "${dir}" "${base}" "amd64"
    cfg_file=${dir}/${DIRNAME_COPYIN}/build.run
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
    cfg_file=${dir}/${DIRNAME_COPYIN}/run_command
    write_file "${cfg_file}" <<EOF
CMD=/usr/sbin/runuser
ARGS="-u ${username} -- /opt/google/chrome/google-chrome --no-sandbox"
EOF
    cat <<'EOF'
docker create --name chrome --hostname chrome \
    --network br-ext --ip 192.168.169.100 --dns 8.8.8.8 \
    -e ENABLE_SSH=true \
    -e DISPLAY=unix$DISPLAY \
    -v /home/johnyin/disk/docker_home/:/home/johnyin/:rw \
    -v /usr/share/fonts/opentype/noto/:/usr/share/fonts/opentype/noto/:ro \
    -v /dev/shm:/dev/shm \
    -v /tmp/.X11-unix:/tmp/.X11-unix \
    --device /dev/snd \
    --device /dev/dri \
    registry.local/chrome:bookworm-amd64
xhost +127.0.0.1
# #
docker create --ipc=host --pid=host
EOF
}
build_firefox() {
    local dir="${1}"
    local file="${2}"
    local arch=${3:-}
    local name=firefox
    local username=johnyin
    [ -e "${dir}/${file}" ] || exit_msg "${dir}/${file} file no found\n"
    gen_dockerfile "${name}" "${dir}" "${file}" "${arch}"
    cfg_file=${dir}/${DIRNAME_COPYIN}/build.run
    write_file "${cfg_file}" <<EOF
useradd -m ${username} --home-dir /home/${username}/
EOF
    cfg_file=${dir}/Dockerfile
    write_file "${cfg_file}" append <<EOF
VOLUME ["/home/${username}/"]
EOF
    cfg_file=${dir}/${DIRNAME_COPYIN}/run_command
    write_file "${cfg_file}" <<EOF
CMD=/usr/bin/su
ARGS="${username} -c '/opt/firefox/firefox'"
EOF
    cat <<'EOF'
# apt -y update && apt -y --no-install-recommends install libgtk-3-0 libnss3 libssl3 libdbus-glib-1-2 libx11-xcb1 libxtst6 libasound2 fonts-noto-cjk
docker pull registry.local/firefox:bookworm --platform amd64
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
    registry.local/firefox:bookworm
xhost +127.0.0.1
# #
docker run --rm -e DISPLAY -v /tmp:/tmp --ipc=host --pid=host --network br-ext myx11 '/firefox/firefox
# #
xpra start ssh:user@host --exit-with-children --start-child="command"
xpra start --ssh="ssh" ssh:user@host --exit-with-children --start-child="command"
xpra start-desktop :7 --start-child=xfce4-session --exit-with-children
pactl load-module module-native-protocol-tcp auth-ip-acl=172.17.0.2
docer -e PULSE_SERVER=172.17.42.1 ..
EOF
}
build_aria2() {
    local dir="${1}"
    local arch="${2:-}"
    local name=aria2
    local base="${BASE_IMG}"
    local username=johnyin
    gen_dockerfile "${name}" "${dir}" "${base}" "${arch}"
    cfg_file=${dir}/${DIRNAME_COPYIN}/build.run
    write_file "${cfg_file}" <<EOF
useradd -m ${username} --home-dir /home/${username}/
apt -y --no-install-recommends update
apt -y --no-install-recommends install aria2
EOF
    cfg_file=${dir}/Dockerfile
    write_file "${cfg_file}" append <<EOF
VOLUME ["/home/${username}/"]
EOF
    cfg_file=${dir}/${DIRNAME_COPYIN}/run_command
    write_file "${cfg_file}" <<EOF
CMD=/usr/sbin/runuser
ARGS="-u ${username} -- /usr/bin/aria2c --conf-path=/home/${username}/.aria2/aria2.conf"
EOF
    cat <<'EOF'
docker pull registry.local/aria:bookworm --platform amd64
docker create --name aria --hostname aria \
    --network br-ext --ip 192.168.169.101 --dns 8.8.8.8 \
    -e ENABLE_SSH=true \
    -v /home/johnyin/disk/docker_home/:/home/johnyin/:rw \
    registry.local/aria:bookworm
EOF
}
build_nginx() {
    local dir="${1}"
    local arch="${2:-}"
    local name=nginx
    local base="${BASE_IMG}"
    local username=nginx
    local groupname=nginx
    gen_dockerfile "${name}" "${dir}" "${base}" "${arch}"
    cfg_file=${dir}/${DIRNAME_COPYIN}/build.run
    write_file "${cfg_file}" <<EOF
getent group ${groupname} >/dev/null || groupadd --system ${groupname} || :
getent passwd ${username} >/dev/null || useradd -g ${groupname} --system -s /sbin/nologin -d /var/empty/nginx ${username} 2> /dev/null || :
apt -y update && apt -y install --no-install-recommends libbrotli1 libgeoip1 libxml2 libxslt1.1
EOF
    cfg_file=${dir}/Dockerfile
    write_file "${cfg_file}" append <<EOF
VOLUME ["/etc/nginx/", "/var/log/nginx/"]
EOF
    cfg_file=${dir}/${DIRNAME_COPYIN}/run_command
    write_file "${cfg_file}" <<EOF
CMD=/usr/sbin/runuser
ARGS="-u root -- /usr/sbin/nginx -g \"daemon off;\""
EOF
    cat <<'EOF'
docker pull registry.local/nginx:bookworm --platform amd64
docker create --name nginx --hostname nginx \
    --network br-ext --ip 192.168.169.100 --dns 8.8.8.8 \
    -e ENABLE_SSH=true \
    -v /storage/nginx/etc/:/etc/nginx/:ro \
    -v /storage/nginx/log/:/var/log/nginx/:rw \
    registry.local/nginx:bookworm
EOF
}
combine_multiarch() {
    local img_tag="${1}"
    local ARCH=(amd64 arm64)
    warn_msg "registry must has ssl access\n"
    local arch_args=""
    for arch in ${ARCH[@]}; do
        try "docker image ls --format '{{.Repository}}:{{.Tag}}' | grep -q '${img_tag}-${arch}'" \
            && info_msg "${img_tag}-${arch} found OK\n" \
            || { error_msg "${img_tag}-${arch} no found\n"; return 1; }
        arch_args+=" --amend ${img_tag}-${arch}"
    done
    try "docker manifest rm ${img_tag} 2>/dev/null || true"
    try docker manifest create --insecure ${img_tag} ${arch_args}
    for arch in ${ARCH[@]}; do
        try docker manifest annotate --os linux --arch ${arch} ${img_tag} ${img_tag}-${arch}
    done
    try "docker manifest inspect --insecure ${img_tag} | jq .manifests[].platform"
    try docker manifest push --insecure ${img_tag}
    for arch in ${ARCH[@]}; do
        try docker pull -q ${img_tag} --platform ${arch}
        info_msg "++++++++++++++++++++++++++++++++++++++++++++++++++++\n"
        info_msg "++++++++++++++++++check: ${arch} | $(try docker run --rm --entrypoint="uname" ${img_tag} -m)++++++++++++++++++\n"
    done
}
build_other() {
    local dir="${1}"
    local tag="${2}"
    local base="${3}"
    local arch="${4:-}"
    [ -e "${base}" ] || exit_msg "${base} no found\n"
    info_msg "copyt ${base} -> ${dir}/${base##*/}\n"
    try "mkdir -p '${dir}' && cat ${base} > ${dir}/${base##*/}"
    gen_dockerfile "goldimg" "${dir}" "${base}" "${arch}"
}
main() {
    local func="" dir="" tag="" file="" arch=""
    local opt_short="c:D:"
    local opt_long="tag:,file:,arch:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -c)             shift; func=${1}; shift;;
            -D)             shift; dir=${1}; shift;;
            --tag)          shift; tag=${1}; shift;;
            --arch)         shift; arch=${1}; shift;;
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
                    build_base "${dir:-goldimg}" "${tag}" "${file}" "${arch}"
                    ;;
        combine)
                    [ -z "${tag}" ] && usage "combine mode, tag must input"
                    combine_multiarch "${tag}"
                    ;;
        xfce)       build_xfceweb "${dir:-xfce}" "${arch}";;
        chrome)     build_chrome "${dir:-chrome}" "${arch}";;
        firefox)    build_firefox "${dir:-firefox}" "${file}" "${arch}";;
        aria)       build_aria2 "${dir:-aria2}" "${arch}";;
        nginx)      build_nginx "${dir:-nginx-johnyin}" "${arch}";;
        *)
                    [ -z "${file}" ] && gen_dockerfile "${func}" "${dir:-${func}-common-demo}" "${BASE_IMG}" "${arch}" \
                        || build_other "${dir:-${func}-scratch-demo}" "${func}" "${file}" "${arch}"
                    ;;
    esac
    : <<'EOF'
docker pull registry.local/debian:bookworm --platform <arch>
docker build --network=br-ext -t nginx-amd64 .

docker images | awk '{print $3}' | xargs -I@ docker image rm @ -f
docker ps -a | awk '{print $1}' | xargs -I@ docker rm @

# # override ENTRYPOINT
docker run --rm --entrypoint="/bin/ls" mybase:v1 /bin/
# # list all
for image in $(docker images --format "{{.Repository}}:{{.Tag}}") ;do echo $image;done

docker images -a
# show image layers
docker history --no-trunc <Image ID>
# list all images arch
docker image inspect --format "{{.ID}} {{.RepoTags}} {{.Architecture}}" $(docker image ls -q)
docker inspect --format='{{.Architecture}}' ..
docker system prune -af
EOF
    return 0
}
main "$@"
