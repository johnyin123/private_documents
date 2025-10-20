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
for fn in config database flask_app main meta template utils vmmanager api_auth; do
    cython ${fn}.py -o ${fn}.c
    gcc -fPIC -shared `python3-config --cflags --ldflags` ${fn}.c -o ${fn}.so
    strip ${fn}.so
    chmod 644 ${fn}.so
done
# # apt -y install libpython3.13 # runtime embed
cython --embed console.py -o console.c
gcc $(python3-config --includes) console.c $(python3-config --embed --libs) -o console
chmod 755 console
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
    location / { proxy_pass http://cidata_srv; }
    location ^~ /gold { set $limit 0; alias /home/johnyin/vmmgr/gold/; }
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
        proxy_cache off;
        expires off;
        proxy_read_timeout 240s;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_set_header Host $host;
        proxy_set_header Connection "";
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
        proxy_cache off;
        expires off;
        proxy_read_timeout 240s;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_set_header Host $host;
        proxy_set_header Connection "";
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
docker-vmmgr.sh         : gen vmmgr-api docker image
inst_vmmgr_api_srv.sh   : inst vmmgr-api server(on docker or on vm)
gen_ngx_conf            : gen nginx kvm.conf for vmmgr-api
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
if use ISO no deed dhcp
---------------------------------------------------------
qemu-img convert -f qcow2 -O raw tpl.qcow2 ssh://user@host:port/path/to/disk.img
qemu-img convert -f qcow2 -O raw tpl.qcow2 rbd:cephpool/disk.raw:conf=/etc/ceph/ceph.conf
qemu-img convert -p --image-opt file.driver=https,file.sslverify=off,file.url=https://vmm.registry.local/gold/openeuler_22.03sp1.amd64.qcow2 -W -m1 -O raw disk.raw
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
}
arch=x86_64
host=testhost
iso=testiso
gold=testgold
#GET     /vm/websockify/${host}/${uuid}?disp=&expire=<mins>&token=
echo "backup config " && CURL GET /conf/backup/ -o backup.tgz
echo "restore config" && CURL UPLOAD /conf/restore/ 'file=@backup.tgz'
echo "list all hosts" && CURL GET /tpl/host/
echo "list all iso  " && CURL GET /tpl/iso/
echo "list all golds" && CURL GET /tpl/gold/
echo "list all devs " && CURL GET /tpl/device/
echo "list arch gold" && CURL GET /tpl/gold/${arch}
echo "list host devs" && CURL GET /tpl/device/${host}
echo "list dom tpls " && CURL GET /conf/domains/
echo "list dev tpls " && CURL GET /conf/devices/
gen_host() {
    cat <<EOF
{ "name":"${1}","tpl":"domain","url":"qemu+ssh://root@192.168.169.1:60022/system","arch":"x86_64","ipaddr":"192.168.169.1","sshport":"60022","sshuser":"root", "disk.file":"on", "net.br-ext":"on", "cdrom.null":"on" }
EOF
}
echo "add new host  " && gen_host "${host}" | CURL POST /conf/host/
echo "add new iso   " && CURL POST /conf/iso/ << EOF
{"name":"${iso}","uri":"/gold/hotpe.iso","desc":"test CD"}
EOF
echo "add new gold  " && CURL POST /conf/gold/ << EOF
{"name":"${gold}","arch":"${arch}","uri":"/gold/bookworm.amd64.qcow2","size":"2","desc":"test gold"}
EOF

echo "lst cached vms" && CURL GET /vm/list/
echo "create vm     " && uuid=$(CURL POST /vm/create/${host} <<<'{ "vm_desc" : "测试VM" }' | jq -r .uuid)
echo "list vm info  " && CURL GET /vm/list/${host}/${uuid}
echo "get vm xml    " && CURL GET /vm/xml/${host}/${uuid}
echo "vm attach dev " && CURL POST /vm/attach_device/${host}/${uuid}?dev=disk.file <<EOF
{"size":2,"gold":"debian12"}
EOF
CURL GET /vm/blksize/${host}/${uuid}?dev=vda
CURL GET /vm/netstat/${host}/${uuid}?dev=52:54:00:97:bc:5a
CURL GET /vm/ctrl_url/${host}/${uuid}?epoch=$(date -d "+3600 second" +%s)
CURL GET "/vm/display/${host}/${uuid}?disp=&prefix=&timeout_mins=15"
CURL GET "/vm/display/${host}/${uuid}?disp=console&prefix=&timeout_mins=15"
CURL GET /vm/start/${host}/${uuid}
CURL GET /vm/ipaddr/${host}/${uuid}
CURL GET /vm/reset/${host}/${uuid}
CURL GET /vm/stop/${host}/${uuid}
CURL GET /vm/stop/${host}/${uuid}?force=true
CURL GET /vm/desc/${host}/${uuid}?vm_desc=new%20desc
CURL GET /vm/setmem/${host}/${uuid}?vm_ram_mb=1024
CURL GET /vm/setcpu/${host}/${uuid}?vm_vcpus=1
CURL GET /vm/snapshot/${host}/${uuid}
CURL POST /vm/snapshot/${host}/${uuid} <<< ''
CURL POST /vm/snapshot/${host}/${uuid}?name= <<< ''
CURL GET /vm/revert_snapshot/${host}/${uuid}?name=
CURL GET /vm/delete_snapshot/${host}/${uuid}?name=
CURL POST /vm/metadata/${host}/${uuid} <<< '{"key":"val"}'
CURL POST /vm/cdrom/${host}/${uuid}?dev=sda <<< '{"isoname":""}'
CURL POST /vm/detach_device/${host}/${uuid}?dev=sda <<< ''
CURL GET /vm/delete/${host}/${uuid}
echo "delete iso    " && CURL DELETE "/conf/iso/?name=${iso}"
echo "delete gold   " && CURL DELETE "/conf/gold/?name=${gold}&arch=${arch}"
echo "delete host   " && CURL DELETE "/conf/host/?name=${host}"
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
    install -v -C -m 0440 ca.pem       ${target}/pki/ca-cert.pem
    install -v -C -m 0440 ${file}.key  ${target}/pki/server-key.pem
    install -v -C -m 0440 ${file}.pem  ${target}/pki/server-cert.pem
    # docker create in docker-libvirtd.sh
---------------------------------------------------------
# -smbios type=1,serial=ds=nocloud;s=http://ip:port/__dmi.system-uuid__/
https://IP:PORT/uuid/meta-data
https://IP:PORT/uuid/user-data
https://IP:PORT/uuid/vendor-data
https://IP:PORT/uuid/network-config
