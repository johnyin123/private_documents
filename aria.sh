#!/bin/bash
# socat TCP-LISTEN:8899,bind=10.0.1.1,reuseaddr,fork TCP:127.0.0.1:60021
# aria2rpc --server ${srv} --port ${port} --secret password tellActive
# pip install aria2p
echo "setup cli rpc client"
zcat /usr/share/doc/aria2/xmlrpc/aria2rpc.gz | sudo tee /usr/bin/aria2rpc
sudo chmod 755 /usr/bin/aria2rpc
USER_HOME=/home/johnyin
mkdir ${USER_HOME}/.aria2
cat<<EOF > ${USER_HOME}/.aria2/aria2.conf
# 下载目录。可使用绝对路径或相对路径, 默认: 当前启动位置
dir=${USER_HOME}/down
# 磁盘缓存, 0 为禁用缓存，默认:16M
# 磁盘缓存的作用是把下载的数据块临时存储在内存中，然后集中写入硬盘，以减少磁盘 I/O ，提升读写性能，延长硬盘寿命。
# 建议在有足够的内存空闲情况下适当增加，但不要超过剩余可用内存空间大小。
# 此项值仅决定上限，实际对内存的占用取决于网速(带宽)和设备性能等其它因素。
disk-cache=64M

# 文件预分配方式, 可选：none, prealloc, trunc, falloc, 默认:prealloc
# 预分配对于机械硬盘可有效降低磁盘碎片、提升磁盘读写性能、延长磁盘寿命。
# 机械硬盘使用 ext4（具有扩展支持），btrfs，xfs 或 NTFS（仅 MinGW 编译版本）等文件系统建议设置为 falloc
# 若无法下载，提示 fallocate failed.cause：Operation not supported 则说明不支持，请设置为 none
# prealloc 分配速度慢, trunc 无实际作用，不推荐使用。
# 固态硬盘不需要预分配，只建议设置为 none ，否则可能会导致双倍文件大小的数据写入，从而影响寿命。
file-allocation=none

# 文件预分配大小限制。小于此选项值大小的文件不预分配空间，单位 K 或 M，默认：5M
no-file-allocation-limit=64M

# 禁用https证书检查
check-certificate=true

# 断点续传
continue=true

# 始终尝试断点续传，无法断点续传则终止下载，默认：true
always-resume=false

# 不支持断点续传的 URI 数值，当 always-resume=false 时生效。
# 达到这个数值从将头开始下载，值为 0 时所有 URI 不支持断点续传时才从头开始下载。
max-resume-failure-tries=0

# 获取服务器文件时间，默认:false
remote-time=true

## 进度保存设置 ##
# 从会话文件中读取下载任务
input-file=${USER_HOME}/.aria2/aria2.session

# 会话文件保存路径
# Aria2 退出时或指定的时间间隔会保存"错误/未完成"的下载任务到会话文件
save-session=${USER_HOME}/.aria2/aria2.session

# 任务状态改变后保存会话的间隔时间（秒）, 0 为仅在进程正常退出时保存, 默认:0
# 为了及时保存任务状态、防止任务丢失，此项值只建议设置为 1
save-session-interval=1

# 自动保存任务进度到控制文件(*.aria2)的间隔时间（秒），0 为仅在进程正常退出时保存，默认：60
# 此项值也会间接影响从内存中把缓存的数据写入磁盘的频率
# 想降低磁盘 IOPS (每秒读写次数)则提高间隔时间
# 想在意外非正常退出时尽量保存更多的下载进度则降低间隔时间
# 非正常退出：进程崩溃、系统崩溃、SIGKILL 信号、设备断电等
auto-save-interval=20

# 强制保存，即使任务已完成也保存信息到会话文件, 默认:false
# 开启后会在任务完成后保留 .aria2 文件，文件被移除且任务存在的情况下重启后会重新下载。
# 关闭后已完成的任务列表会在重启后清空。
force-save=false

## 下载连接设置 ##
# 文件未找到重试次数，默认:0 (禁用)
# 重试时同时会记录重试次数，所以也需要设置 max-tries 这个选项
max-file-not-found=10

# 最大尝试次数，0 表示无限，默认:5
max-tries=0

# 重试等待时间（秒）, 默认:0 (禁用)
retry-wait=10

# 连接超时时间（秒）。默认：60
connect-timeout=10

# 超时时间（秒）。默认：60
timeout=10

# 最大同时下载任务数, 运行时可修改, 默认:5
max-concurrent-downloads=5

# 单服务器最大连接线程数, 任务添加时可指定, 默认:1
# 最大值为 16 (增强版无限制), 且受限于单任务最大连接线程数(split)所设定的值。
max-connection-per-server=16

# 单任务最大连接线程数, 任务添加时可指定, 默认:5
split=64

# 文件最小分段大小, 添加时可指定, 取值范围 1M-1024M (增强版最小值为 1K), 默认:20M
# 比如此项值为 10M, 当文件为 20MB 会分成两段并使用两个来源下载, 文件为 15MB 则只使用一个来源下载。
# 理论上值越小使用下载分段就越多，所能获得的实际线程数就越大，下载速度就越快，但受限于所下载文件服务器的策略。
min-split-size=4M

# HTTP/FTP 下载分片大小，所有分割都必须是此项值的倍数，最小值为 1M (增强版为 1K)，默认：1M
piece-length=1M

# 允许分片大小变化。默认：false
# false：当分片大小与控制文件中的不同时将会中止下载
# true：丢失部分下载进度继续下载
allow-piece-length-change=true

# 最低下载速度限制。当下载速度低于或等于此选项的值时关闭连接（增强版本为重连），此选项与 BT 下载无关。单位 K 或 M ，默认：0 (无限制)
lowest-speed-limit=0

# 全局最大下载速度限制, 运行时可修改, 默认：0 (无限制)
max-overall-download-limit=0

# 单任务下载速度限制, 默认：0 (无限制)
max-download-limit=0

# 禁用 IPv6, 默认:false
disable-ipv6=true

# GZip 支持，默认:false
http-accept-gzip=true

# URI 复用，默认: true
reuse-uri=false

# 禁用 netrc 支持，默认:false
no-netrc=true

# 允许覆盖，当相关控制文件(.aria2)不存在时从头开始重新下载。默认:false
allow-overwrite=false

# 文件自动重命名，此选项仅在 HTTP(S)/FTP 下载中有效。新文件名在名称之后扩展名之前加上一个点和一个数字（1..9999）。默认:true
auto-file-renaming=true

# 使用 UTF-8 处理 Content-Disposition ，默认:false
content-disposition-default-utf8=true

# 最低 TLS 版本，可选：TLSv1.1、TLSv1.2、TLSv1.3 默认:TLSv1.2
#min-tls-version=TLSv1.2


## BT/PT 下载设置 ##
# BT 监听端口(TCP), 默认:6881-6999
# 直通外网的设备，比如 VPS ，务必配置防火墙和安全组策略允许此端口入站
# 内网环境的设备，比如 NAS ，除了防火墙设置，还需在路由器设置外网端口转发到此端口
listen-port=50000

# DHT 网络与 UDP tracker 监听端口(UDP), 默认:6881-6999
# 因协议不同，可以与 BT 监听端口使用相同的端口，方便配置防火墙和端口转发策略。
dht-listen-port=51413

# 启用 IPv4 DHT 功能, PT 下载(私有种子)会自动禁用, 默认:true
enable-dht=true

# 启用 IPv6 DHT 功能, PT 下载(私有种子)会自动禁用，默认:false
# 在没有 IPv6 支持的环境开启可能会导致 DHT 功能异常
enable-dht6=false

# 指定 BT 和 DHT 网络中的 IP 地址
# 使用场景：在家庭宽带没有公网 IP 的情况下可以把 BT 和 DHT 监听端口转发至具有公网 IP 的服务器，在此填写服务器的 IP ，可以提升 BT 下载速率。
#bt-external-ip=

# IPv4 DHT 文件路径
dht-file-path=${USER_HOME}/.aria2/dht.dat

# IPv6 DHT 文件路径
dht-file-path6=${USER_HOME}/.aria2/dht6.dat

# IPv4 DHT 网络引导节点
dht-entry-point=dht.transmissionbt.com:6881

# IPv6 DHT 网络引导节点
dht-entry-point6=dht.transmissionbt.com:6881

# 本地节点发现, PT 下载(私有种子)会自动禁用 默认:false
bt-enable-lpd=true

# 指定用于本地节点发现的接口，可能的值：接口，IP地址
# 如果未指定此选项，则选择默认接口。
#bt-lpd-interface=

# 启用节点交换, PT 下载(私有种子)会自动禁用, 默认:true
enable-peer-exchange=true

# BT 下载最大连接数（单任务），运行时可修改。0 为不限制，默认:55
# 理想情况下连接数越多下载越快，但在实际情况是只有少部分连接到的做种者上传速度快，其余的上传慢或者不上传。
# 如果不限制，当下载非常热门的种子或任务数非常多时可能会因连接数过多导致进程崩溃或网络阻塞。
# 进程崩溃：如果设备 CPU 性能一般，连接数过多导致 CPU 占用过高，因资源不足 Aria2 进程会强制被终结。
# 网络阻塞：在内网环境下，即使下载没有占满带宽也会导致其它设备无法正常上网。因远古低性能路由器的转发性能瓶颈导致。
bt-max-peers=128

# BT 下载期望速度值（单任务），运行时可修改。单位 K 或 M 。默认:50K
# BT 下载速度低于此选项值时会临时提高连接数来获得更快的下载速度，不过前提是有更多的做种者可供连接。
# 实测临时提高连接数没有上限，但不会像不做限制一样无限增加，会根据算法进行合理的动态调节。
bt-request-peer-speed-limit=10M

# 全局最大上传速度限制, 运行时可修改, 默认:0 (无限制)
# 设置过低可能影响 BT 下载速度
max-overall-upload-limit=2M

# 单任务上传速度限制, 默认:0 (无限制)
max-upload-limit=0

# 最小分享率。当种子的分享率达到此选项设置的值时停止做种, 0 为一直做种, 默认:1.0
# 强烈建议您将此选项设置为大于等于 1.0
seed-ratio=1.0

# 最小做种时间（分钟）。设置为 0 时将在 BT 任务下载完成后停止做种。
seed-time=0

# 做种前检查文件哈希, 默认:true
bt-hash-check-seed=true

# 继续之前的BT任务时, 无需再次校验, 默认:false
bt-seed-unverified=false

# BT tracker 服务器连接超时时间（秒）。默认：60
# 建立连接后，此选项无效，将使用 bt-tracker-timeout 选项的值
bt-tracker-connect-timeout=10

# BT tracker 服务器超时时间（秒）。默认：60
bt-tracker-timeout=10

# BT 服务器连接间隔时间（秒）。默认：0 (自动)
#bt-tracker-interval=0

# BT 下载优先下载文件开头或结尾
bt-prioritize-piece=head=32M,tail=32M

# 保存通过 WebUI(RPC) 上传的种子文件(.torrent)，默认:true
# 所有涉及种子文件保存的选项都建议开启，不保存种子文件有任务丢失的风险。
# 通过 RPC 自定义临时下载目录可能不会保存种子文件。
rpc-save-upload-metadata=true

# 下载种子文件(.torrent)自动开始下载, 默认:true，可选：false|mem
# true：保存种子文件
# false：仅下载种子文件
# mem：将种子保存在内存中
follow-torrent=true

# 种子文件下载完后暂停任务，默认：false
# 在开启 follow-torrent 选项后下载种子文件或磁力会自动开始下载任务进行下载，而同时开启当此选项后会建立相关任务并暂停。
pause-metadata=false

# 保存磁力链接元数据为种子文件(.torrent), 默认:false
bt-save-metadata=true

# 加载已保存的元数据文件(.torrent)，默认:false
bt-load-saved-metadata=true

# 删除 BT 下载任务中未选择文件，默认:false
bt-remove-unselected-file=true

# BT强制加密, 默认: false
# 启用后将拒绝旧的 BT 握手协议并仅使用混淆握手及加密。可以解决部分运营商对 BT 下载的封锁，且有一定的防版权投诉与迅雷吸血效果。
# 此选项相当于后面两个选项(bt-require-crypto=true, bt-min-crypto-level=arc4)的快捷开启方式，但不会修改这两个选项的值。
bt-force-encryption=true

# BT加密需求，默认：false
# 启用后拒绝与旧的 BitTorrent 握手协议(\19BitTorrent protocol)建立连接，始终使用混淆处理握手。
#bt-require-crypto=true

# BT最低加密等级，可选：plain（明文），arc4（加密），默认：plain
#bt-min-crypto-level=arc4

# 分离仅做种任务，默认：false
# 从正在下载的任务中排除已经下载完成且正在做种的任务，并开始等待列表中的下一个任务。
bt-detach-seed-only=true


## 客户端伪装 ##
all-proxy=http://yin.zh:Passw)rd123@192.168.2.78:8080
check-certificate=false
# 自定义 User Agent
user-agent=Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/87.0.4280.88 Safari/537.36 Edg/87.0.664.57

# BT 客户端伪装
# PT 下载需要保持 user-agent 和 peer-agent 两个参数一致
# 部分 PT 站对 Aria2 有特殊封禁机制，客户端伪装不一定有效，且有封禁账号的风险。
#user-agent=Transmission 2.94
peer-agent=Transmission 2.94
peer-id-prefix=-TR2940-


## RPC 设置 ##

# 启用 JSON-RPC/XML-RPC 服务器, 默认:false
enable-rpc=true

# 接受所有远程请求, 默认:false
rpc-allow-origin-all=true

# 允许外部访问, 默认:false
rpc-listen-all=false

# RPC 监听端口, 默认:6800
rpc-listen-port=6800

# RPC 密钥
# rpc-secret=password

# RPC 最大请求大小
rpc-max-request-size=10M

## 高级选项 ##

# 启用异步 DNS 功能。默认：true
#async-dns=true

# 指定异步 DNS 服务器列表，未指定则从 /etc/resolv.conf 中读取。
#async-dns-server=119.29.29.29,223.5.5.5,8.8.8.8,1.1.1.1

# 指定单个网络接口，可能的值：接口，IP地址，主机名
# 如果接口具有多个 IP 地址，则建议指定 IP 地址。
# 已知指定网络接口会影响依赖本地 RPC 的连接的功能场景，即通过 localhost 和 127.0.0.1 无法与 Aria2 服务端进行讯通。
#interface=

# 指定多个网络接口，多个值之间使用逗号(,)分隔。
# 使用 interface 选项时会忽略此项。
#multiple-interface=


## 日志设置 ##

# 日志文件保存路径，忽略或设置为空为不保存，默认：不保存
#log=

# 日志级别，可选 debug, info, notice, warn, error 。默认：debug
#log-level=warn

# 控制台日志级别，可选 debug, info, notice, warn, error ，默认：notice
console-log-level=notice

# 安静模式，禁止在控制台输出日志，默认：false
quiet=false

# 下载进度摘要输出间隔时间（秒），0 为禁止输出。默认：60
summary-interval=0


## 增强扩展设置(非官方) ##

# 仅适用于 myfreeer/aria2-build-msys2 (Windows) 和 P3TERX/Aria2-Pro-Core (GNU/Linux) 项目所构建的增强版本

# 在服务器返回 HTTP 400 Bad Request 时重试，仅当 retry-wait > 0 时有效，默认 false
#retry-on-400=true

# 在服务器返回 HTTP 403 Forbidden 时重试，仅当 retry-wait > 0 时有效，默认 false
#retry-on-403=true

# 在服务器返回 HTTP 406 Not Acceptable 时重试，仅当 retry-wait > 0 时有效，默认 false
#retry-on-406=true

# 在服务器返回未知状态码时重试，仅当 retry-wait > 0 时有效，默认 false
#retry-on-unknown=true

## BitTorrent trackers ##
## https://github.com/ngosang/trackerslist/blob/master/trackers_all_udp.txt
bt-tracker=
EOF

# systemctl --user start aria2
# systemctl --user stop aria2
# systemctl --user restart aria2
# systemctl --user status aria2
cat <<EOF | sudo tee /etc/systemd/system/aria2.service
[Unit]
Description=Aria2 Service
After=network.target
[Service]
User=johnyin
Group=johnyin
ExecStart=/usr/bin/aria2c --conf-path=${USER_HOME}/.aria2/aria2.conf
[Install]
WantedBy=default.target
EOF

cat <<"EOF" >  ~/.aria2/update_tracker.sh
#!/usr/bin/env bash
# BT tracker is provided by the following project.
# https://github.com/XIU2/TrackersListCollection
# Fallback URLs provided by jsDelivr
# https://www.jsdelivr.com
#

RED_FONT_PREFIX="\033[31m"
GREEN_FONT_PREFIX="\033[32m"
YELLOW_FONT_PREFIX="\033[1;33m"
LIGHT_PURPLE_FONT_PREFIX="\033[1;35m"
FONT_COLOR_SUFFIX="\033[0m"
INFO="[${GREEN_FONT_PREFIX}INFO${FONT_COLOR_SUFFIX}]"
ERROR="[${RED_FONT_PREFIX}ERROR${FONT_COLOR_SUFFIX}]"
ARIA2_CONF=${1:-aria2.conf}
DOWNLOADER="curl -fsSL --connect-timeout 3 --max-time 3 --retry 2"

DATE_TIME() {
    date +"%m/%d %H:%M:%S"
}

GET_TRACKERS() {
    echo && echo -e "$(DATE_TIME) ${INFO} Get BT trackers ..."
    if [[ -z "${CUSTOM_TRACKER_URL}" ]]; then
        TRACKER=$(
            ${DOWNLOADER} https://trackerslist.com/all_aria2.txt ||
                ${DOWNLOADER} https://cdn.jsdelivr.net/gh/XIU2/TrackersListCollection@master/all_aria2.txt ||
                ${DOWNLOADER} https://trackers.p3terx.com/all_aria2.txt
        )
    else
        TRACKER=$(${DOWNLOADER} ${CUSTOM_TRACKER_URL} | awk NF | sed ":a;N;s/\n/,/g;ta")
    fi
    [[ -z "${TRACKER}" ]] && {
        echo
        echo -e "$(DATE_TIME) ${ERROR} Unable to get trackers, network failure or invalid links." && exit 1
    }
}

ECHO_TRACKERS() {
    echo -e "
--------------------[BitTorrent Trackers]--------------------
${TRACKER}
--------------------[BitTorrent Trackers]--------------------
"
}

ADD_TRACKERS() {
    echo -e "$(DATE_TIME) ${INFO} Adding BT trackers to Aria2 configuration file ${LIGHT_PURPLE_FONT_PREFIX}${ARIA2_CONF}${FONT_COLOR_SUFFIX} ..." && echo
    if [ ! -f ${ARIA2_CONF} ]; then
        echo -e "$(DATE_TIME) ${ERROR} '${ARIA2_CONF}' does not exist."
        exit 1
    else
        [ -z $(grep "bt-tracker=" ${ARIA2_CONF}) ] && echo "bt-tracker=" >>${ARIA2_CONF}
        sed -i "s@^\(bt-tracker=\).*@\1${TRACKER}@" ${ARIA2_CONF} && echo -e "$(DATE_TIME) ${INFO} BT trackers successfully added to Aria2 configuration file !"
    fi
}

ADD_TRACKERS_RPC() {
    if [[ "${RPC_SECRET}" ]]; then
        RPC_PAYLOAD='{"jsonrpc":"2.0","method":"aria2.changeGlobalOption","id":"P3TERX","params":["token:'${RPC_SECRET}'",{"bt-tracker":"'${TRACKER}'"}]}'
    else
        RPC_PAYLOAD='{"jsonrpc":"2.0","method":"aria2.changeGlobalOption","id":"P3TERX","params":[{"bt-tracker":"'${TRACKER}'"}]}'
    fi
    curl "${RPC_ADDRESS}" -fsSd "${RPC_PAYLOAD}" || curl "https://${RPC_ADDRESS}" -kfsSd "${RPC_PAYLOAD}"
}

ADD_TRACKERS_RPC_STATUS() {
    RPC_RESULT=$(ADD_TRACKERS_RPC)
    [[ $(echo ${RPC_RESULT} | grep OK) ]] &&
        echo -e "$(DATE_TIME) ${INFO} BT trackers successfully added to Aria2 !" ||
        echo -e "$(DATE_TIME) ${ERROR} Network failure or Aria2 RPC interface error!"
}

ADD_TRACKERS_REMOTE_RPC() {
    echo -e "$(DATE_TIME) ${INFO} Adding BT trackers to remote Aria2: ${LIGHT_PURPLE_FONT_PREFIX}${RPC_ADDRESS%/*}${FONT_COLOR_SUFFIX} ..." && echo
    ADD_TRACKERS_RPC_STATUS
}

ADD_TRACKERS_LOCAL_RPC() {
    if [ ! -f ${ARIA2_CONF} ]; then
        echo -e "$(DATE_TIME) ${ERROR} '${ARIA2_CONF}' does not exist."
        exit 1
    else
        RPC_PORT=$(grep ^rpc-listen-port ${ARIA2_CONF} | cut -d= -f2-)
        RPC_SECRET=$(grep ^rpc-secret ${ARIA2_CONF} | cut -d= -f2-)
        [[ ${RPC_PORT} ]] || {
            echo -e "$(DATE_TIME) ${ERROR} Aria2 configuration file incomplete."
            exit 1
        }
        RPC_ADDRESS="localhost:${RPC_PORT}/jsonrpc"
        echo -e "$(DATE_TIME) ${INFO} Adding BT trackers to Aria2 ..." && echo
        ADD_TRACKERS_RPC_STATUS
    fi
}

[ $(command -v curl) ] || {
    echo -e "$(DATE_TIME) ${ERROR} curl is not installed."
    exit 1
}

if [ "$1" = "cat" ]; then
    GET_TRACKERS
    ECHO_TRACKERS
elif [ "$1" = "RPC" ]; then
    RPC_ADDRESS="$2/jsonrpc"
    RPC_SECRET="$3"
    GET_TRACKERS
    ECHO_TRACKERS
    ADD_TRACKERS_REMOTE_RPC
elif [ "$2" = "RPC" ]; then
    GET_TRACKERS
    ECHO_TRACKERS
    ADD_TRACKERS
    echo
    ADD_TRACKERS_LOCAL_RPC
else
    GET_TRACKERS
    ECHO_TRACKERS
    ADD_TRACKERS
fi

exit 0
EOF
chmod 755 ~/.aria2/update_tracker.sh
