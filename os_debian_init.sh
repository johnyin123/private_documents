#!/bin/echo Warnning, this library must only be sourced!
# shellcheck disable=SC2086 disable=SC2155

# TO BE SOURCED ONLY ONCE:
if [ -z ${__debian__inc+x} ]; then
    __debian__inc=1
else
    return 0
fi
# Disable unicode.
LC_ALL=C
LANG=C

#set -o pipefail  # trace ERR through pipes,only available on Bash
set -o errtrace  # trace ERR through 'time command' and other functions
set -o nounset   ## set -u : exit the script if you try to use an uninitialised variable
set -o errexit   ## set -e : exit the script if any statement returns a non-true return value

VERSION+=("7460eb7[2023-03-01T13:46:02+08:00]:os_debian_init.sh")
# liveos:debian_build /tmp/rootfs "" "linux-image-${INST_ARCH:-amd64},live-boot,systemd-sysv"
# docker:debian_build /tmp/rootfs /tmp/cache "systemd-container"
# INST_ARCH=amd64
# DEBIAN_VERSION=buster
# REPO=http://mirrors.163.com/debian
# HOSTNAME=deb-tpl
# NAME_SERVER=114.114.114.114
# PASSWORD=password
debian_build() {
    local root_dir=$1
    local cache_dir=${2:-}
    local include_pkg="whiptail,tzdata,locales,busybox${3:+,${3}}"
    [ -d "${root_dir}" ] || mkdir -p ${root_dir}
    debootstrap --verbose ${cache_dir:+--cache-dir=${cache_dir}} --no-check-gpg --arch ${INST_ARCH:-amd64} --variant=minbase --include=${include_pkg} --foreign ${DEBIAN_VERSION:-buster} ${root_dir} ${REPO:-http://mirrors.163.com/debian}

    [ ${INST_ARCH:-amd64} = "arm64" ] && {
        [ -e "/usr/bin/qemu-aarch64-static" ] || { echo "Need: apt install qemu-user-static"; return 1; }
        cp /usr/bin/qemu-aarch64-static ${root_dir}/usr/bin/
    }
    # fix some package error: Name or service not known
    cat /etc/hosts > ${root_dir}/etc/hosts
    LC_ALL=C LANGUAGE=C LANG=C chroot ${root_dir} /bin/bash <<EOSHELL
    /debootstrap/debootstrap --second-stage
    echo ${HOSTNAME:-deb-tpl} > /etc/hostname
    cat << EOF > /etc/rc.local
#!/bin/sh -e
test -f /etc/ssh/ssh_host_rsa_key || dpkg-reconfigure openssh-server
exit 0
EOF
    chmod 755 /etc/rc.local

    echo "nameserver ${NAME_SERVER:-114.114.114.114}" > /etc/resolv.conf
    debian_chpasswd root ${PASSWORD:-password}
    debian_apt_init ${DEBIAN_VERSION:-buster}
    debian_locale_init
    debian_limits_init
    debian_sysctl_init
    debian_bash_init root
    debian_minimum_init
    cat << EOF > /etc/hosts
127.0.0.1       localhost ${HOSTNAME:-deb-tpl}
EOF
EOSHELL
    return 0
}

# LC_ALL=C LANGUAGE=C LANG=C chroot ${root_dir} /bin/bash <<EOSHELL
#     debian_autologin_root
# EOSHELL
# ssh user@host << EOF
#     $(typeset -f debian_autologin_root)
#     debian_autologin_root
# EOF
# ftp.cn.debian.org/mirrors.163.com/mirrors.aliyun.com
debian_apt_init() {
    local ver=${1:-buster}
    echo 'Acquire::http::User-Agent "debian dler";' > /etc/apt/apt.conf
    echo '#Acquire::http::Proxy "http://proxy_srv:port";' >> /etc/apt/apt.conf
    echo '#Acquire::https::Proxy "https://u:p@srv:port";'>> /etc/apt/apt.conf
    # echo 'APT::Install-Recommends "0";'> /etc/apt/apt.conf.d/71-no-recommends
    echo 'APT::Install-Suggests "0";'> /etc/apt/apt.conf.d/72-no-suggests
    cat > /etc/apt/sources.list << EOF
deb http://mirrors.aliyun.com/debian ${ver} main non-free contrib
deb http://mirrors.aliyun.com/debian ${ver}-proposed-updates main non-free contrib
deb http://mirrors.aliyun.com/debian ${ver}-backports main contrib non-free
EOF
    cat > /etc/apt/sources.list.d/multimedia.list <<EOF
# # apt -y -oAcquire::http::User-Agent=dler --no-install-recommends -oAcquire::AllowInsecureRepositories=true update 2>/dev/null || true
# # apt -y -oAcquire::http::User-Agent=dler --no-install-recommends --allow-unauthenticated install deb-multimedia-keyring 2>/dev/null|| true
# deb http://mirrors.aliyun.com/debian-multimedia ${ver} main non-free
# deb http://mirrors.aliyun.com/debian-multimedia ${ver}-backports main
EOF
    # see bullseye release notes
    case "${ver}" in
        buster)
            echo "deb http://mirrors.aliyun.com/debian-security ${ver}/updates main contrib non-free"  >> /etc/apt/sources.list
            ;;
        bullseye|bookworm)
            echo "deb http://mirrors.aliyun.com/debian-security ${ver}-security main contrib"  >> /etc/apt/sources.list
            ;;
    esac
}
export -f debian_apt_init

debian_grub_init() {
    echo "generate grub config"
    cat << 'EOF' > /etc/default/grub
GRUB_DEFAULT=0
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR=`lsb_release -i -s 2> /dev/null || echo Debian`
GRUB_CMDLINE_LINUX_DEFAULT="console=ttyS0 console=tty1 net.ifnames=0 biosdevname=0"
GRUB_CMDLINE_LINUX=""
EOF
    mkdir -p /etc/default/grub.d || true
    echo 'GRUB_CMDLINE_LINUX_DEFAULT="$GRUB_CMDLINE_LINUX_DEFAULT apparmor=0"' | tee /etc/default/grub.d/apparmor.cfg
    echo "need run: update-grub"
    echo "cat /sys/module/apparmor/parameters/enabled"
    echo "enable apparmor: apparmor=1 security=apparmor"
}
export -f debian_grub_init

debian_limits_init() {
    #set the file limit
    cat > /etc/security/limits.d/tun.conf << EOF
*           soft   nofile       102400
*           hard   nofile       102400
EOF
    echo "export TMOUT=900" > /etc/profile.d/tmout.sh
    echo "export readonly HISTCONTROL=erasedups" > /etc/profile.d/hisfile.sh
    chmod 644 /etc/profile.d/tmout.sh /etc/profile.d/hisfile.sh
}
export -f debian_limits_init

debian_sysctl_init() {
    # net.ipv4.ip_local_port_range = 1024 65531
    # net.ipv4.tcp_fin_timeout = 10
    # # (65531-1024)/10 = 6450 sockets per second.
    mv /etc/sysctl.conf /etc/sysctl.conf.bak 2>/dev/null || true
    cat << EOF > /etc/sysctl.conf
net.ipv4.ping_group_range = 0 2147483647
net.core.rmem_max = 134217728 
net.core.wmem_max = 134217728 
net.core.netdev_max_backlog = 250000
net.core.somaxconn = 65535
net.core.wmem_default = 16777216
net.ipv4.ip_local_port_range = 1024 65531
net.ipv4.tcp_fin_timeout = 10
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.tcp_max_orphans = 3276800
net.ipv4.tcp_max_syn_backlog = 262144
net.ipv4.tcp_no_metrics_save=1
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.tcp_syn_retries = 1
net.ipv4.tcp_synack_retries = 1
net.ipv4.tcp_syncookies = 0
net.ipv4.tcp_timestamps = 0
#net.ipv4.tcp_tw_recycle = 0
net.ipv4.tcp_tw_reuse = 0
net.ipv4.ip_forward = 1
EOF
    cat << EOF > /etc/sysctl.d/90-bbr.conf
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
    cat << EOF > /etc/sysctl.d/90-perf.conf
kernel.sched_autogroup_enabled = 0
vm.min_free_kbytes = 131072
sysctl vm.dirty_ratio = 60
EOF
}
export -f debian_sysctl_init

debian_sshd_regenkey() {
  # Remove ssh host keys
  rm -f /etc/ssh/ssh_host_*
  systemctl stop sshd

  # Regenerate ssh host keys
  # dpkg-reconfigure openssh-server
  ssh-keygen -q -t rsa -N "" -f /etc/ssh/ssh_host_rsa_key
  ssh-keygen -q -t dsa -N "" -f /etc/ssh/ssh_host_dsa_key
  ssh-keygen -q -t ecdsa -N "" -f /etc/ssh/ssh_host_ecdsa_key
  ssh-keygen -q -t ed25519 -N "" -f /etc/ssh/ssh_host_ed25519_key
  systemctl start sshd
}
export -f debian_sshd_regenkey

debian_sshd_init() {
    apt -y -oAcquire::http::User-Agent=dler --no-install-recommends install openssh-server
    # dpkg-reconfigure -f noninteractive openssh-server
    sed --quiet -i.orig -E \
        -e '/^\s*(UseDNS|MaxAuthTries|GSSAPIAuthentication|Port|Ciphers|MACs|PermitRootLogin).*/!p' \
        -e '$aUseDNS no' \
        -e '$aMaxAuthTries 3' \
        -e '$aGSSAPIAuthentication no' \
        -e '$aPort 60022' \
        -e '$aCiphers aes256-ctr,aes192-ctr,aes128-ctr' \
        -e '$aMACs hmac-sha1' \
        -e '$aPermitRootLogin without-password' \
        /etc/ssh/sshd_config
    # root login only prikey "PermitRootLogin without-password"
    cat <<"EOF" > /etc/ssh/sshrc
logger -i -t ssh "$(date '+%Y%m%d%H%M%S') $USER $SSH_CONNECTION"
EOF
    [ ! -d /root/.ssh ] && mkdir -m0700 /root/.ssh
    cat <<EOF >/root/.ssh/authorized_keys
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDKxdriiCqbzlKWZgW5JGF6yJnSyVtubEAW17mok2zsQ7al2cRYgGjJ5iFSvZHzz3at7QpNpRkafauH/DfrZz3yGKkUIbOb0UavCH5aelNduXaBt7dY2ORHibOsSvTXAifGwtLY67W4VyU/RBnCC7x3HxUB6BQF6qwzCGwry/lrBD6FZzt7tLjfxcbLhsnzqOG2y76n4H54RrooGn1iXHBDBXfvMR7noZKbzXAUQyOx9m07CqhnpgpMlGFL7shUdlFPNLPZf5JLsEs90h3d885OWRx9Kp+O05W2gPg4kUhGeqO6IY09EPOcTupw77PRHoWOg4xNcqEQN2v2C1lr09Y9 root@yinzh
EOF
    chmod 0600 /root/.ssh/authorized_keys
    # ssh tap device no create, when ControlMaster !!!!
    cat <<EOF >/root/.ssh/config
StrictHostKeyChecking=no
UserKnownHostsFile=/dev/null
Host github.com
    Port=22
Host *
    Port=60022
#    ControlMaster auto
#    ControlPath  ~/.ssh/sockets/%r@%h-%p
#    ControlPersist 600
EOF
    mkdir -p /root/.ssh/sockets/
    chmod 0600 /root/.ssh/config
}
export -f debian_sshd_init

debian_zswap_init() {
    local size_mb=$1
    cat<<EOF > /etc/default/zramswap
ZRAM_DEV=/dev/zram0
# Compression algorithm selection
# speed: lz4 > zstd > lzo compression: zstd > lzo > lz4
ALGO=lzo

# Specifies a static amount of RAM in MiB
SIZE=${size_mb}MiB

# Specifies the priority for the swap devices, see swapon(2)
# This should probably be higher than hdd/ssd swaps.
#PRIORITY=100
EOF
    cat<<'EOF' >/lib/systemd/system/zramswap.service
[Unit]
Description=Linux zramswap setup
[Service]
Environment=ALGO=lzo
Environment=SIZE=256MiB
Environment=ZRAM_DEV=/dev/zram0
Environment=PRIORITY=100
EnvironmentFile=-/etc/default/zramswap
ExecStartPre=-/sbin/modprobe zram
ExecStart=/sbin/zramctl ${ZRAM_DEV}
ExecStart=/sbin/zramctl -a "${ALGO}" -s "${SIZE}" ${ZRAM_DEV}
ExecStart=/sbin/mkswap ${ZRAM_DEV}
ExecStart=/sbin/swapon -p "${PRIORITY}" ${ZRAM_DEV}
ExecStop=/sbin/swapoff ${ZRAM_DEV}
ExecStop=/sbin/zramctl -r ${ZRAM_DEV}
Type=oneshot
RemainAfterExit=true
[Install]
WantedBy=multi-user.target
EOF
}
export -f debian_zswap_init

debian_zswap_init1() {
    local size_mb=$1
    cat<<EOF > /etc/default/zramswap
# Compression algorithm selection
# speed: lz4 > zstd > lzo compression: zstd > lzo > lz4
#ALGO=lz4

# Specifies the amount of RAM that should be used for zram
#PERCENT=50

# Specifies a static amount of RAM in MiB
SIZE=${size_mb}

# Specifies the priority for the swap devices, see swapon(2)
# This should probably be higher than hdd/ssd swaps.
#PRIORITY=100
EOF
    cat<<EOF >/lib/systemd/system/zramswap.service
[Unit]
Description=Linux zramswap setup
[Service]
EnvironmentFile=-/etc/default/zramswap
ExecStart=/usr/sbin/zramswap start
ExecStop=/usr/sbin/zramswap stop
ExecReload=/usr/sbin/zramswap restart
Type=oneshot
RemainAfterExit=true
[Install]
WantedBy=multi-user.target
EOF
    cat<<'EOSH' >/usr/sbin/zramswap
#!/bin/bash
readonly CONFIG="/etc/default/zramswap"
readonly SWAP_DEV="/dev/zram0"

if command -v logger >/dev/null; then
    function elog {
        logger -s "Error: $*"
        exit 1
    }
    function wlog {
        logger -s "$*"
    }
else
    function elog {
        echo "Error: $*"
        exit 1
    }
    function wlog {
        echo "$*"
    }
fi

function start {
    wlog "Starting Zram"

    # Load config
    test -r "${CONFIG}" || wlog "Cannot read config from ${CONFIG} continuing with defaults."
    source "${CONFIG}" 2>/dev/null

    # Set defaults if not specified
    : "${ALGO:=lz4}" "${SIZE:=256}" "${PRIORITY:=100}"

    SIZE=$((SIZE * 1024 * 1024)) # convert amount from MiB to bytes

    # Prefer percent if it is set
    if [ -n "${PERCENT}" ]; then
        readonly TOTAL_MEMORY=$(awk '/MemTotal/{print $2}' /proc/meminfo) # in KiB
        readonly SIZE="$((TOTAL_MEMORY * 1024 * PERCENT / 100))"
    fi

    modprobe zram || elog "inserting the zram kernel module"
    echo -n "${ALGO}" > /sys/block/zram0/comp_algorithm || elog "setting compression algo to ${ALGO}"
    echo -n "${SIZE}" > /sys/block/zram0/disksize || elog "setting zram device size to ${SIZE}"
    mkswap "${SWAP_DEV}" || elog "initialising swap device"
    swapon -p "${PRIORITY}" "${SWAP_DEV}" || elog "enabling swap device"
}

function status {
    test -x "$(which zramctl)" || elog "install zramctl for this feature"
    test -b "${SWAP_DEV}" || elog "${SWAP_DEV} doesn't exist"
    # old zramctl doesn't have --output-all
    #zramctl --output-all
    zramctl "${SWAP_DEV}"
}

function stop {
    wlog "Stopping Zram"
    test -b "${SWAP_DEV}" || wlog "${SWAP_DEV} doesn't exist"
    swapoff "${SWAP_DEV}" 2>/dev/null || wlog "disabling swap device: ${SWAP_DEV}"
    modprobe -r zram || elog "removing zram module from kernel"
}

function usage {
    cat << EOF
Usage:
    zramswap (start|stop|restart|status)
EOF
}

case "$1" in
    start)      start;;
    stop)       stop;;
    restart)    stop && start;;
    status)     status;;
    "")         usage;;
    *)          elog "Unknown option $1";;
esac
EOSH
    chmod 755 /usr/sbin/zramswap
    systemctl enable zramswap.service
}

debian_zswap_init2() {
    local size_mb=$(($1*1024*1024))
    ( grep -v -E "^/dev/zram0" /etc/fstab ; echo "/dev/zram0   none swap sw,pri=32767 0 0"; ) | tee /etc/fstab.bak
    mv /etc/fstab.bak /etc/fstab
    cat <<EOF > /etc/udev/rules.d/99-zswap.rules
KERNEL=="zram0", ACTION=="add", ATTR{disksize}="${size_mb}", RUN="/sbin/mkswap /\$root/\$name"
EOF
    #echo "zram" > /etc/modules-load.d/zram.conf
    #fix no swap after update-initramfs -c -k $(uname -r)
    echo "zram" >> /etc/initramfs-tools/modules
    update-initramfs -c -k $(uname -r)
}
export -f debian_zswap_init2

debian_zswap_init3() {
    local zram_size=$1
    local cfg=
    # "Enable udisk2 ${zram_size}M zram swap"
    cat <<EOF >/etc/modules
$( grep -v -E 'zram' /etc/modules; echo 'zram';)
EOF
    eval $(grep -E "^VERSION_CODENAME=" /etc/os-release)
    case "$VERSION_CODENAME" in
        buster)
            apt -y -oAcquire::http::User-Agent=dler --no-install-recommends update && apt -y -oAcquire::http::User-Agent=dler --no-install-recommends install udisks2
            mkdir -p /usr/local/lib/zram.conf.d/
            cfg=/usr/local/lib/zram.conf.d/zram0-env
            ;;
        bullseye)
            apt -y -oAcquire::http::User-Agent=dler --no-install-recommends update && apt -y -oAcquire::http::User-Agent=dler --no-install-recommends install udisks2-zram
            mkdir -p /usr/lib/zram.conf.d/
            cfg=/usr/lib/zram.conf.d/zram0
            ;;
    esac
 
    cat << EOF > ${cfg}
ZRAM_NUM_STR=lzo
ZRAM_DEV_SIZE=$((${zram_size}*1024*1024))
SWAP=y
EOF
}
export -f debian_zswap_init3

debian_vim_init() {
    apt -y -oAcquire::http::User-Agent=dler --no-install-recommends install vim
    cat <<'EOF' > /etc/vim/vimrc.local
syntax on
" color evening
set number
set nowrap
set fileencodings=utf-8,gb2312,gbk,gb18030
" set termencoding=utf-8
let &termencoding=&encoding
set fileformats=unix
set hlsearch                 " highlight the last used search pattern
set noswapfile
set tabstop=4                " 设置tab键的宽度
set shiftwidth=4             " 换行时行间交错使用4个空格
set expandtab                " 用space替代tab的输入
set autoindent               " 自动对齐
set backspace=2              " 设置退格键可用
set cindent shiftwidth=4     " 自动缩进4空格
set smartindent              " 智能自动缩进
"Paste toggle - when pasting something in, don't indent.
set pastetoggle=<F7>
set mouse=r
"disable .viminfo file
set viminfo=
let g:is_bash=1

"新建.py,.sh文件，自动插入文件头"
autocmd BufNewFile *.py,*.c,*.sh,*.h exec ":call SetTitle()"
"定义函数SetTitle，自动插入文件头"
func SetTitle()
    if expand ("%:e") == 'sh'
        call setline(1, "#!/usr/bin/env bash")
        call setline(2, "readonly DIRNAME=\"$(readlink -f \"$(dirname \"$0\")\")\"")
        call setline(3, "readonly SCRIPTNAME=${0##*/}")
        call setline(4, "if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then")
        call setline(5, "    exec 5> \"${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log\"")
        call setline(6, "    BASH_XTRACEFD=\"5\"")
        call setline(7, "    export PS4='[\\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'")
        call setline(8, "    set -o xtrace")
        call setline(9, "fi")
        call setline(10, "VERSION+=()")
        call setline(11, "[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }")
        call setline(12, "################################################################################")
        call setline(13, "usage() {")
        call setline(14, "    [ \"$#\" != 0 ] && echo \"$*\"")
        call setline(15, "    cat <<EOF")
        call setline(16, "${SCRIPTNAME}")
        call setline(17, "        -q|--quiet")
        call setline(18, "        -l|--log <int> log level")
        call setline(19, "        -V|--version")
        call setline(20, "        -d|--dryrun dryrun")
        call setline(21, "        -h|--help help")
        call setline(22, "EOF")
        call setline(23, "    exit 1")
        call setline(24, "}")
        call setline(25, "main() {")
        call setline(26, "    local opt_short=\"\"")
        call setline(27, "    local opt_long=\"\"")
        call setline(28, "    opt_short+=\"ql:dVh\"")
        call setline(29, "    opt_long+=\"quiet,log:,dryrun,version,help\"")
        call setline(30, "    __ARGS=$(getopt -n \"${SCRIPTNAME}\" -o ${opt_short} -l ${opt_long} -- \"$@\") || usage")
        call setline(31, "    eval set -- \"${__ARGS}\"")
        call setline(32, "    while true; do")
        call setline(33, "        case \"$1\" in")
        call setline(34, "            ########################################")
        call setline(35, "            -q | --quiet)   shift; QUIET=1;;")
        call setline(36, "            -l | --log)     shift; set_loglevel ${1}; shift;;")
        call setline(37, "            -d | --dryrun)  shift; DRYRUN=1;;")
        call setline(38, "            -V | --version) shift; for _v in \"${VERSION[@]}\"; do echo \"$_v\"; done; exit 0;;")
        call setline(39, "            -h | --help)    shift; usage;;")
        call setline(40, "            --)             shift; break;;")
        call setline(41, "            *)              usage \"Unexpected option: $1\";;")
        call setline(42, "        esac")
        call setline(43, "    done")
        call setline(44, "    return 0")
        call setline(45, "}")
        call setline(46, "main \"$@\"")
    endif
    if expand ("%:e") == 'py'
        call setline(1, "#!/usr/bin/env python3")
        call setline(2, "# -*- coding: utf-8 -*-")
        call setline(3, "")
        call setline(4, "class MyClass(object):")
        call setline(5, "    def __init__(self, url, binddn, password):")
        call setline(6, "        print('DEMO')")
        call setline(7, "")
        call setline(8, "def main():")
        call setline(9, "    return 0")
        call setline(10, "")
        call setline(11, "if __name__ == '__main__':")
        call setline(12, "    exit(main())")
    endif
    if expand ("%:e") == 'h'
        let fn = toupper(substitute(expand("%"), '[.-]', '_', 'g'))
        let tm = strftime("%H%M%S")
        let rnd = rand()
        call setline(1, printf("#ifndef __%s_%s_%d__INC__", fn, tm, rnd))
        call setline(2, printf("#define __%s_%s_%d__INC__", fn, tm, rnd))
        call setline(3, "")
        call setline(4, printf("#endif"))
    endif
    if expand ("%:e") == 'c'
        call setline(1, "#include <stdio.h>")
        call setline(2, "#include <getopt.h>")
        call setline(3, "#include <string.h>")
        call setline(4, "#include <stdlib.h>")
        call setline(5, "")
        call setline(6, "struct env {")
        call setline(7, "    int verbose;")
        call setline(8, "} env = {")
        call setline(9, "    .verbose = 0,")
        call setline(10, "};")
        call setline(11, "")
        call setline(12, "const char *opt_short=\"hV\";")
        call setline(13, "struct option opt_long[] = {")
        call setline(14, "    { \"help\",    no_argument, NULL, 'h' },")
        call setline(15, "    { \"verbose\", no_argument, NULL, 'V' },")
        call setline(16, "    { 0, 0, 0, 0 }")
        call setline(17, "};")
        call setline(18, "/*")
        call setline(19, " * { \"demo\",    required_argument, NULL, 'd' }, ")
        call setline(20, " * strncpy(env.demo, optarg, 10);")
        call setline(21, " * env.demo = strtol(optarg, NULL, 10);")
        call setline(22, "*/")
        call setline(23, "")
        call setline(24, "static void usage(char *prog)")
        call setline(25, "{")
        call setline(26, "    printf(\"Usage: %s\\n\", prog);")
        call setline(27, "    printf(\"    -h|--help help\\n\");")
        call setline(28, "    printf(\"    -V|--verbose\\n\");")
        call setline(29, "    exit(0);")
        call setline(30, "}")
        call setline(31, "")
        call setline(32, "static int parse_command_line(int argc, char **argv)")
        call setline(33, "{")
        call setline(34, "    int opt, option_index;")
        call setline(35, "    while ((opt = getopt_long(argc, argv, opt_short, opt_long, &option_index)) != -1) {")
        call setline(36, "        switch (opt) {")
        call setline(37, "            case 'h':")
        call setline(38, "                usage(argv[0]);")
        call setline(39, "                return 0;")
        call setline(40, "            case 'V':")
        call setline(41, "                env.verbose = 1;")
        call setline(42, "                break;")
        call setline(43, "            default:")
        call setline(44, "                usage(argv[0]);")
        call setline(45, "                return 1;")
        call setline(46, "        }")
        call setline(47, "    }")
        call setline(48, "    return 0;")
        call setline(49, "}")
        call setline(50, "")
        call setline(51, "int main(int argc, char *argv[])")
        call setline(52, "{")
        call setline(53, "    parse_command_line(argc, argv);")
        call setline(54, "    return 0;")
        call setline(55, "}")
    endif
endfunc
EOF
    sed -i "s/mouse=a/mouse=/g" /usr/share/vim/vim*/defaults.vim || true
}
export -f debian_vim_init

debian_locale_init() {
    #dpkg-reconfigure locales
    sed -i "s/^# *zh_CN.UTF-8/zh_CN.UTF-8/g" /etc/locale.gen
    locale-gen
    echo -e 'LANG="zh_CN.UTF-8"\nLANGUAGE="zh_CN:zh"\nLC_ALL="zh_CN.UTF-8"\n' > /etc/default/locale
    #echo "Asia/Shanghai" > /etc/timezone
    rm -f /etc/localtime && ln -fs /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
    dpkg-reconfigure -f noninteractive tzdata
}
export -f debian_locale_init

debian_chpasswd() {
    local user=$1
    local password=$2
    # usermod -p "$(echo ${password} | openssl passwd -1 -stdin)" ${user}
    echo "${user}:${password}" |chpasswd
    # Force Users To Change Their Passwords Upon First Login
    # chage -d 0 ${user}
}
export -f debian_chpasswd

debian_autologin_root() {
    # auto login as root
    sed -i "s|#NAutoVTs=6|NAutoVTs=1|" /etc/systemd/logind.conf
    mkdir -p /etc/systemd/system/getty@tty1.service.d
    cat <<EOF | tee /etc/systemd/system/getty@tty1.service.d/override.conf
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I 38400 linux
EOF
    systemctl enable getty@tty1.service
}
export -f debian_autologin_root

debain_overlay_init() {
    cat > /etc/overlayroot.conf <<'EOF'
OVERLAY=OVERLAYFS
SKIP_OVERLAY=1
EOF

(grep -v -E "^overlay" /etc/initramfs-tools/modules; echo "overlay"; ) | tee /etc/initramfs-tools/modules

    cat > /usr/share/initramfs-tools/hooks/overlay <<'EOF'
#!/bin/sh

. /usr/share/initramfs-tools/scripts/functions
. /usr/share/initramfs-tools/hook-functions

copy_exec /sbin/blkid
copy_exec /sbin/fsck
copy_exec /sbin/mke2fs
copy_exec /sbin/fsck.ext2
copy_exec /sbin/fsck.ext3
copy_exec /sbin/fsck.ext4
copy_exec /sbin/logsave
manual_add_modules overlay
EOF

    cat > /etc/initramfs-tools/scripts/init-bottom/init-bottom-overlay <<'EOF'
#!/bin/sh

PREREQ=""
prereqs()
{
   echo "$PREREQ"
}

case $1 in
prereqs)
   prereqs
   exit 0
   ;;
esac

. /scripts/functions

[ -f ${rootmnt}/etc/overlayroot.conf ] && . ${rootmnt}/etc/overlayroot.conf
OVERLAY_LABEL=${OVERLAY:-OVERLAY}
SKIP_OVERLAY=${SKIP_OVERLAY:-0}
grep -q -E '(^|\s)skipoverlay(\s|$)' /proc/cmdline && SKIP_OVERLAY=1

if [ "${SKIP_OVERLAY-}" = 1 ]; then
    log_begin_msg "Skipping overlay, found 'skipoverlay' in cmdline"
    log_end_msg
    exit 0
fi

log_begin_msg "Starting overlay"
log_end_msg

mkdir -p /overlay

# if we have a filesystem label of ${OVERLAY_LABEL}
# use that as the overlay, otherwise use tmpfs.
OLDEV=$(blkid -L ${OVERLAY_LABEL})
if [ -z "${OLDEV}" ]; then
    mount -t tmpfs tmpfs /overlay
else
    _checkfs_once ${OLDEV} /overlay ext4 || \
    mke2fs -FL ${OVERLAY_LABEL} -t ext4 -E lazy_itable_init,lazy_journal_init ${OLDEV}
    if ! mount -t ext4 ${OLDEV} /overlay; then
        mount -t tmpfs tmpfs /overlay
    fi
fi

# if you sudo touch /overlay/reformatoverlay
# next reboot will give you a fresh /overlay
if [ -f /overlay/reformatoverlay ]; then
    umount /overlay
    mke2fs -FL ${OVERLAY_LABEL} -t ext4 -E lazy_itable_init,lazy_journal_init ${OLDEV}
    if ! mount -t ext4 ${OLDEV} /overlay; then
        mount -t tmpfs tmpfs /overlay
    fi
fi

mkdir -p /overlay/upper
mkdir -p /overlay/work
mkdir -p /overlay/lower

# make the readonly root available
mount -n -o move ${rootmnt} /overlay/lower
mount -t overlay overlay -olowerdir=/overlay/lower,upperdir=/overlay/upper,workdir=/overlay/work ${rootmnt}

mkdir -p ${rootmnt}/overlay
mount -n -o rbind /overlay ${rootmnt}/overlay

# fix up fstab
# cp ${rootmnt}/etc/fstab ${rootmnt}/etc/fstab.orig
# awk '$2 != "/" {print $0}' ${rootmnt}/etc/fstab.orig > ${rootmnt}/etc/fstab
# awk '$2 == "'${rootmnt}'" { $2 = "/" ; print $0}' /etc/mtab >> ${rootmnt}/etc/fstab
# Already there?
if [ -e ${rootmnt}/etc/fstab ] && grep -qE ''^overlay[[:space:]]+/[[:space:]]+overlay'' ${rootmnt}/etc/fstab; then
    exit 0 # Do nothing
fi

FSTAB=$(awk '$2 != "/" {print $0}' ${rootmnt}/etc/fstab && awk '$2 == "'${rootmnt}'" { $2 = "/" ; print $0}' /etc/mtab)
cat>${rootmnt}/etc/fstab<<EO_FSTAB
$FSTAB
EO_FSTAB

exit 0
EOF
    chmod 755 /usr/share/initramfs-tools/hooks/overlay
    chmod 755 /etc/initramfs-tools/scripts/init-bottom/init-bottom-overlay
}
export -f debain_overlay_init

debian_minimum_init() {
    rm -rf /var/cache/apt/* \
           /var/lib/apt/lists/* \
           /var/cache/debconf/*-old \
           /var/lib/dpkg/*-old \
           /var/log/* \
           /root/.bash_history \
           /root/.viminfo \
           /root/.vim/ || true
    find /usr/share/doc -depth -type f ! -name copyright -print0 | xargs -0 rm || true
    find /usr/share/doc -empty -print0 | xargs -0 rm -rf || true
    # remove on used locale
    find /usr/share/locale -maxdepth 1 -mindepth 1 -type d ! -iname 'zh_CN*' ! -iname 'en*' | xargs -I@ rm -rf @ || true
    rm -rf /usr/share/groff \
           /usr/share/info \
           /usr/share/lintian \
           /usr/share/linda \
           /var/cache/man || true
} >/dev/null 2>&1
export -f debian_minimum_init

# root user save as .bashrc
# other save as .bash_aliases
# see: /etc/skel/.bashrc
debian_bash_init() {
    local user=$1
    local busybox=${2:-}
    local home=$(getent passwd ${user} | cut -d: -f6)
    [ -z ${home} ] && return 1
    [ ${user} = "root" ] && home+=/.bashrc || home+=/.bash_aliases
    {
        [ ${user} = "root" ] && {
            cat << "EOF"
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
fi
EOF
        }
        cat <<"EOF"
umask 022

alias cal='ncal -b'
alias ls='ls --color=auto --group-directories-first'
alias ll='ls -lh'
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'
alias df='df -h'
alias grep='grep --color=auto'

export PS1="\[\033[1;31m\]\u\[\033[m\]@\[\033[1;32m\]\h:\[\033[33;1m\]\w\[\033[m\]$"

[ -e /usr/lib/git-core/git-sh-prompt ] && {
    source /usr/lib/git-core/git-sh-prompt
    export GIT_PS1_SHOWDIRTYSTATE=1
    export readonly PROMPT_COMMAND='__git_ps1 "\\[\\033[1;31m\\]\\u\\[\\033[m\\]@\\[\\033[1;32m\\]\\h:\\[\\033[33;1m\\]\\w\\[\\033[m\\]"  "\\\\\$ "'
}

set -o vi
EOF
     [[ ${busybox} =~ ^1|yes|true$ ]] && cat <<'EOF'
bb_cmd() {
    for i in $*; do
        alias $i="$(busybox which $i || echo busybox $i)"
    done
}
for c in $(busybox --list)
do
    bb_cmd $c
done
EOF
    } > ${home}
    chown ${user}:${user} ${home}
}
export -f debian_bash_init

debian_service_init() {
    systemctl set-default multi-user.target
    local netsvc=networking.service
    {
        systemctl list-unit-files -t service | egrep -v "getty|console-setup.service|keyboard-setup.service|ssh.service|rsyslog.service|cron.service|sysstat.service|systemd-timesyncd.service|${netsvc}" | awk '$2 == "enabled" {printf "systemctl disable %s\n", $1}'
        echo "systemctl enable ${netsvc}"
        systemctl list-unit-files -t timer  | grep enabled | egrep -v "logrotate.timer|sysstat-collect.timer|sysstat-summary.timer" | awk '{print "systemctl disable", $1}'
    } | bash -x || true
}
export -f debian_service_init

# # /etc/sudoers.d/testuser
# Cmnd_Alias SHUTDOWN = /usr/sbin/halt, /usr/sbin/shutdown, \
# /usr/sbin/poweroff, /usr/sbin/reboot, /usr/sbin/init, /usr/bin/systemctl, \
# /usr/bin/ls
# #test  ALL=(ALL)       ALL, !SHUTDOWN
# testuser  ALL=(ALL)       !ALL, SHUTDOWN

