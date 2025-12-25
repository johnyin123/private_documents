ffmpeg -f x11grab -draw_mouse 1 -video_size 1600x700 -grab_x 0 -grab_y 200 -i :0.0 -vcodec libtheora -q:v 5 demo.ogv
#myvideo {
  position: fixed;
  right: 0;
  bottom: 0;
  min-width: 100%;
  min-height: 100%;
}
 <video autoplay loop muted plays-inline id="myvideo">
  <source src="/ui/demo.ovg" type="video/mp4">
  <p><a href="/ui/demo.ovg">Link to the video</a></p>
 </video>
 <a download="demo.tgz" href='data:application/x-compressed-tar;base64,xxx'>Download</a>
########################################################
action script, can accept env startwith ACT_, set env ACT_XX when start app
action convert gold disk:
    # # device not found, try 'modprobe fuse' first
    GOLD=http://vmm.registry.local/gold/bookworm.amd64.qcow2
    fname=$(basename ${GOLD})
    dir=$(mktemp -d)
    httpdirfs --cache --dl-seg-size 32 --no-range-check --single-file-mode ${GOLD} ${dir}
    [ -f "${dir}/${fname}" ] && qemu-img convert -p -f qcow2 -O raw "${dir}/${fname}" ssh://${SSHUSER}@${HOSTIP}:${SSHPORT}${DISK}
    umount ${dir} && httpdirfs --cache-clear

vm backup: ../vm_backup.sh
docker libvirtd  : docker-libvirtd.sh
docker simplekvm : docker-simplekvm.sh # docker pull johnyinnews/simplekvm:trixie
docker openldap  : docker-slapd.sh
docker etcd      : docker-etcd.sh
init cert key    : inst_cert_keys.sh
cat <<EOF
# # cython
# pip install ${PROXY:+--proxy ${PROXY} } cython
# apt -y install python3-dev / libpython3-dev
# # dbi.py/database.py/database.py.sh all ok
auth_app=(api_auth config utils flask_app)
simplekvm_app=(config database flask_app main meta template utils vmmanager)
combined=($(for ip in "${simplekvm_app[@]}" "${auth_app[@]}"; do echo "${ip}"; done | sort -u))
for fn in ${combined[@]}; do
    cython ${fn}.py -o ${fn}.c
    gcc -fPIC -shared `python3-config --cflags --ldflags` ${fn}.c -o ${fn}.so
    strip ${fn}.so
    chmod 644 ${fn}.so
done
# # apt -y install libpython3.13 # runtime embed
cython --embed console.py -o console.c
gcc $(python3-config --includes) console.c $(python3-config --embed --libs) -o console
chmod 755 console
target=..
cp console ${target}/docker/app/
for fn in ${simplekvm_app[@]}; do
    cp $fn.so ${target}/docker/app/
done
for fn in ${auth_app[@]}; do
    cp $fn.so ${target}/docker/auth/
done
# # or
cat <<EO_SETUP
from setuptools import setup
from Cython.Build import cythonize
setup(
    #ext_modules=cythonize('env/*.py')
    ext_modules=cythonize([ 'config.py', 'flask_app.py', 'meta.py', 'template.py', 'vmmanager.py', 'database.py', 'main.py', 'utils.py', ])
)
EO_SETUP
mkdir -p env && cp *.py env/ ....
python setup.py build_ext --inplace
EOF
cat <<EOF
map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}
upstream cidata_srv {
    random;
    server 192.168.169.123:80;
    server 192.168.169.124:80;
    keepalive 16;
}
server {
    listen 80;
    server_name simplekvm.registry.local;
    location ~* (\/cidata\.iso|\/meta-data|\/user-data)$ { proxy_pass http://cidata_srv; }
    location / { autoindex on; autoindex_format json; set $limit 0; if_modified_since before; alias /home/johnyin/vmmgr/gold/; }
}
upstream user_api_upstream {
    random;
    server 192.168.169.123:1443;
    server 192.168.169.124:1443;
    keepalive 16;
}
server {
    listen 443 ssl;
    server_name user.registry.local;
    ssl_certificate     /etc/nginx/ssl/simplekvm.pem;
    ssl_certificate_key /etc/nginx/ssl/simplekvm.key;
    location / {
        alias /var/www/;
        try_files $uri @proxy;
    }
    location @proxy {
        proxy_cache off;
        expires off;
        proxy_read_timeout 240s;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_set_header Host $host;
        proxy_pass https://user_api_upstream;
    }
}
upstream api_upstream {
    random;
    server 192.168.169.123:443;
    server 192.168.169.124:443;
    keepalive 16;
}
server {
    listen 443 ssl;
    server_name simplekvm.registry.local;
    ssl_certificate     /etc/nginx/ssl/simplekvm.pem;
    ssl_certificate_key /etc/nginx/ssl/simplekvm.key;
    location / {
        alias /var/www/;
        try_files $uri @proxy;
    }
    location @proxy {
        proxy_cache off;
        expires off;
        proxy_read_timeout 240s;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_set_header Host $host;
        proxy_pass https://api_upstream;
    }
}
EOF
# iptables -A INPUT -p tcp -s 192.168.0.0/16 --dport <port> -j ACCEPT
# iptables -A INPUT -p tcp --dport <port> -j DROP

# # clout-init: net http://META_SRV/(uuid)/(meta-data|user-data) (domain.tpl)
# # clout-init: iso http://META_SRV/(uuid)/cidata.iso
# # iso.json  :     http://META_SRV/uri                          (same as clout-init iso)
# # META_SRV: Only for *KVMHOST* use. meta-data/user-data/cidata.iso and iso.json
# # GOLD_SRV: Only for *APP ACTIONS* use. http://GOLD_SRV/uri, golds.json
# # CTRL_SRV: https srv for user control panel, default https://META_SRV

USR -> config.CTRL_SRV -> API
ADM -> <IP> -> API -> Via libvirt/ssh -> KVMHOST
                |  -> Create meta(nocloud)
                |  -> config.GOLD_SRV -> Read golds(golds.json)(support http redirect)
KVMHOST => config.META_SRV => Read meta/cidata.iso
KVMHOST => config.META_SRV => Read iso(iso.json)(support http redirect)

4000 vm usage etcd 251M
pip install line_profiler
kernprof -lv test.py
# python -m line_profiler test.py.lprof
#    @profile
#    def testfunc(.....):
# pip install flask_profiler
# http://127.0.0.1:5009/flask-profiler
# # import flask_profiler
# # app.config["DEBUG"] = True
# # app.config["flask_profiler"] = {
# #     "enabled": app.config["DEBUG"],
# #     "storage": { "engine": "sqlite" },
# #     "basicAuth":{
# #         "enabled": True,
# #         "username": "admin",
# #         "password": "admin"
# #     },
# #     "ignore": [
# # 	    "^/static/.*"
# # 	]
# # }
# # flask_profiler.init_app(app)
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# # {{ var | default("myval", true) }} # undefined, false, None, or an empty string return myval
# python3 -m venv --system-site-packages my_venv
# pip install websockify gunicorn Flask pycdlib # SQLAlchemy # etcd3
# # regen meta_iso
# uuid=../cidata/uuid
cd ${uuid} && mkisofs -o ${uuid}.iso -V cidata -J -r user-data meta-data

list_tpl_varset         : list domain(include meta), device tpl vars
default_pool_redefine.sh: defile default pool directory /storage
docker-libvirtd.sh      : gen libvirtd docker image
docker-simplekvm.sh     : gen vmmgr-api docker image
inst_vmmgr_api_srv.sh   : inst vmmgr-api server(on docker or on vm)
gen_ngx_conf.sh         : gen nginx kvm.conf for vmmgr-api
hosts.json              : kvm hosts with domains template
devices.json            : host device mapping
golds.json              : gold disks, Add disk with template (API SRV) use host in golds.json
iso.json                : ISO disks, metadata and iso cdrom (KVM SRV) in http(s) META_SRV
                          gold iso should in same uri (same server name)
vars.json               : tpl vars desc
##########################################################################
<source protocol="https" name="url_path">
  <host name="hostname" port="443"/>
  <ssl verify="no"/>
</source>

cloud-init clean -l
cloud-init init
cloud-init schema --system --annotate
cloud-init devel schema --system --annotate
cloud-init status --long
DEBUG_LEVEL=2 DI_LOG=stderr /usr/libexec/cloud-init/ds-identify --force
# useradd -m --password "$(openssl passwd -6 -salt xyz yourpass)" test1 -s /bin/bash
if use NOCLOUD need dhcp, and meta server(ngx) on 169.254.169.254
if use ISO no need dhcp
---------------------------------------------------------
qemu-img convert -f qcow2 -O raw tpl.qcow2 ssh://user@host:port/path/to/disk.img
qemu-img convert -f qcow2 -O raw tpl.qcow2 rbd:cephpool/disk.raw:conf=/etc/ceph/ceph.conf
qemu-img convert -p --image-opt file.driver=https,file.sslverify=off,file.readahead=$((10*1024*1024)),file.url=https://vmm.registry.local/gold/openeuler_22.03sp1.amd64.qcow2 -W -m1 -O raw disk.raw
qemu-img convert -p -f qcow2 -W -m1 -O raw http://vmm.registry.local/gold/openeuler_22.03sp1.amd64.qcow2 disk.raw
#define CURL_BLOCK_OPT_URL       "url"
#define CURL_BLOCK_OPT_READAHEAD "readahead"
#define CURL_BLOCK_OPT_SSLVERIFY "sslverify"
#define CURL_BLOCK_OPT_TIMEOUT "timeout"
#define CURL_BLOCK_OPT_COOKIE    "cookie"
#define CURL_BLOCK_OPT_COOKIE_SECRET "cookie-secret"
#define CURL_BLOCK_OPT_USERNAME "username"
#define CURL_BLOCK_OPT_PASSWORD_SECRET "password-secret"
#define CURL_BLOCK_OPT_PROXY_USERNAME "proxy-username"
#define CURL_BLOCK_OPT_PROXY_PASSWORD_SECRET "proxy-password-secret"
---------------------------------------------------------
websockify --token-plugin TokenFile --token-source ./token/ 6800
virsh domdisplay xxx
# vnc://127.0.0.1:0 5900 + port
echo 'vm1: 127.0.0.1:5900' > ./token/uuid.txt
# <graphics type='vnc' autoport='yes' listen='0.0.0.0' password='abc'/>
vnc_lite.html?host=192.168.168.1&port=6800&password=abc&path=websockify/?token=vm1
https://vmm.registry.local/novnc/vnc_lite.html?password=abc&path=websockify/?token=vm1
---------------------------------------------------------
---------------------------------------------------------
---------------------------------------------------------
srv=http://127.0.0.1:5009 #https://vmm.registry.local
uid=admin
pass=adminpass
token=$(cat <<EOF | curl -sk -X POST ${srv}/api/login -d '@-' | jq -r '"Authorization: Bearer \(.token)"'
{"username":"${uid}", "password":"${pass}"}
EOF
)
log() { echo "$(tput setaf 141)$*$(tput sgr0)" >&2; }
function CURL() {
    local method="${1}"; shift 1
    local uri="${1}"; shift 1
    local curl=(curl -sk --header "${token}")
    local args=("$@")
    [ "${method}" == "GET" ] && {
        # pass through cache
        special_chars_pattern='[?]'
        if [[ "${uri}" =~ $special_chars_pattern ]]; then
            uri="${uri}&k=$(date +'%Y%m%d%H%M%S')"
        else
            uri="${uri}?k=$(date +'%Y%m%d%H%M%S')"
        fi
    }
    case "${method}" in
        UPLOAD)
            curl+=(--request POST --form "${args[@]}") ;;
        POST)
            curl+=(--request POST --data @-) ;;
        *)
            curl+=(--request "$method" "${args[@]}") ;;
    esac
    curl+=("${srv}${uri}")
    log "${curl[@]}"
    "${curl[@]}"
    log ''
    log "-----------------------------------------------"
}
gen_host() {
    cat<<EOF
{ "name":"${1:-testsrv}","tpl":"domain","url":"qemu+ssh://root@192.168.169.1:60022/system","arch":"x86_64","ipaddr":"192.168.169.1","sshport":"60022","sshuser":"root", "disk.file":"on", "net.br-ext":"on", "cdrom.null":"on" }
EOF
}
log "refresh token " && CURL GET /api/refresh
arch=x86_64
host=testhost
iso=testiso
gold=testgold
#GET     /vm/websockify/${host}/${uuid}?disp=&expire=<mins>&token=
log "list conf     " && CURL GET /conf/
log "get ssh pubkey" && CURL GET /conf/ssh_pubkey/ -o id_rsa.pub
log "backup config " && CURL GET /conf/backup/ -o backup.tgz
log "restore config" && CURL UPLOAD /conf/restore/ 'file=@init_env.tgz'
log "list dom tpls " && CURL GET /conf/domains/
log "list dev tpls " && CURL GET /conf/devices/

log "add new host  " && CURL POST /conf/host/ <<<$(gen_host "${host}")
log "sshkey -> host" && CURL POST "/conf/add_authorized_keys/${host}?passwd=sshpassword" <<< ""
log "add new iso   " && CURL POST /conf/iso/ << EOF
{"name":"${iso}","uri":"/gold/hotpe.iso","desc":"test CD"}
EOF
log "add new gold  " && CURL POST /conf/gold/ << EOF
{"name":"${gold}","arch":"${arch}","uri":"/gold/bookworm.amd64.qcow2","size":"2","desc":"test gold"}
EOF

log "list all hosts" && CURL GET /tpl/host/
log "list all iso  " && CURL GET /tpl/iso/
log "list all golds" && CURL GET /tpl/gold/
log "list all devs " && CURL GET /tpl/device/
log "list arch gold" && CURL GET /tpl/gold/${arch}
log "list host devs" && CURL GET /tpl/device/${host}

log "lst cached vms" && CURL GET /vm/list/
log "create vm     " && uuid=$(CURL POST /vm/create/${host} <<<'{"vm_desc":"测试VM","vm_graph":"vnc"}' | jq -r .uuid) && log "uuid=${uuid}"
log "get vm xml    " && CURL GET /vm/xml/${host}/${uuid}
log "vm add disk   " && CURL POST /vm/attach_device/${host}/${uuid}?dev=disk.file <<EOF
{"size":2,"gold":"${gold}","vm_disk_type":"qcow2"}
EOF
log "vm add network" && CURL POST /vm/attach_device/${host}/${uuid}?dev=net.br-ext <<< '{}'
log "list vm info  " && CURL GET /vm/list/${host}/${uuid}
log "vda disk size " && CURL GET /vm/blksize/${host}/${uuid}?dev=vda
log "vm netstat    " && CURL GET /vm/netstat/${host}/${uuid}?dev=52:54:00:97:bc:5a
log "vm ctrl url   " && CURL GET /vm/ctrl_url/${host}/${uuid}?epoch=$(date -d "+240 hour" +%s)
log "vm start      " && CURL GET /vm/start/${host}/${uuid}
log "vnc display   " && CURL GET "/vm/display/${host}/${uuid}?disp=&prefix=&timeout_mins=15"
log "serial console" && CURL GET "/vm/display/${host}/${uuid}?disp=console&prefix=&timeout_mins=15"
log "vm ipaddr     " && CURL GET /vm/ipaddr/${host}/${uuid}
log "vm reset      " && CURL GET /vm/reset/${host}/${uuid}
log "vm stop       " && CURL GET /vm/stop/${host}/${uuid}
log "vm poweroff   " && CURL GET /vm/stop/${host}/${uuid}?force=true
log "vm desc       " && CURL GET /vm/desc/${host}/${uuid}?vm_desc=new%20desc
log "vm set memory " && CURL GET /vm/setmem/${host}/${uuid}?vm_ram_mb=1024
log "vm set vcpus  " && CURL GET /vm/setcpu/${host}/${uuid}?vm_vcpus=1
log "list snapshot " && CURL GET /vm/snapshot/${host}/${uuid}
log "add  snapshot1" && CURL POST /vm/snapshot/${host}/${uuid} <<< ''
log "add  snapshot2" && CURL POST /vm/snapshot/${host}/${uuid}?name=mysnap <<< ''
log "reve snapshot " && CURL GET /vm/revert_snapshot/${host}/${uuid}?name=mysnap
log "del  snapshot " && CURL GET /vm/delete_snapshot/${host}/${uuid}?name=mysnap
log "set metadata  " && CURL POST /vm/metadata/${host}/${uuid} <<< '{"key":"val"}'
log "change iso    " && CURL POST /vm/cdrom/${host}/${uuid}?dev=sda << EOF
{"isoname":"${iso}"}
EOF
log "delete cdrom  " && CURL POST /vm/detach_device/${host}/${uuid}?dev=sda <<< ''
log "list vm info  " && CURL GET /vm/list/${host}/${uuid}
log "delete vm     " && CURL GET /vm/delete/${host}/${uuid}
log "delete iso    " && CURL DELETE "/conf/iso/?name=${iso}"
log "delete gold   " && CURL DELETE "/conf/gold/?name=${gold}&arch=${arch}"
log "delete host   " && CURL DELETE "/conf/host/?name=${host}"
---------------------------------------------------------
---------------------------------------------------------
---------------------------------------------------------
1. create CA
    ${ca_root}/ca.key
    ${ca_root}/ca.pem
2. create ngx cert/key & simplekvm client cert/key
    ${ngx_ssl}/simplekvm.pem
    ${ngx_ssl}/simplekvm.key
    ${cli_pki}/pki/CA/cacert.pem
    ${cli_pki}/pki/libvirt/private/clientkey.pem
    ${cli_pki}/pki/libvirt/clientcert.pem
    ${cli_ssh}/id_rsa      #600 10001:10001
    ${cli_ssh}/id_rsa.pub  #644 10001:10001
    ${cli_ssh}/config      #644 10001:10001
    # docker create in docker-vmmgr.sh

3. libvirt srv cert/key
    # file=kvm1.local
    install -v -C -m 0440 ca.pem       /etc/pki/CA/cacert.pem
    install -v -C -m 0440 ${file}.key  /etc/pki/libvirt/private/serverkey.pem
    install -v -C -m 0440 ${file}.pem  /etc/pki/libvirt/servercert.pem
    # docker create in docker-libvirtd.sh
---------------------------------------------------------
# -smbios type=1,serial=ds=nocloud;s=http://ip:port/__dmi.system-uuid__/
https://IP:PORT/uuid/meta-data
https://IP:PORT/uuid/user-data
https://IP:PORT/uuid/vendor-data
https://IP:PORT/uuid/network-config
