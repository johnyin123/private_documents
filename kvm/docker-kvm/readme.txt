vm backup: ../vm_backup.sh
cat <<EOF
# # cython
# pip install ${PROXY:+--proxy ${PROXY} } cython
# apt -y install python3-dev / libpython3-dev
# # dbi.py/database.py/database.py.sh all ok
for fn in config database flask_app main meta template utils vmmanager; do
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
# # CTRL_PANEL_SRV: https srv for user control panel, default https://META_SRV

USR -> config.CTRL_PANEL_SRV -> API
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
srv=http://127.0.0.1:5009 #https://vmm.registry.local
echo 'list host' && curl -k ${srv}/tpl/host/ | jq '.[]|{name: .name, arch: .arch}'
echo 'list iso' && curl -k ${srv}/tpl/iso/
host=host01
arch=x86_64
uefi=/usr/share/OVMF/OVMF_CODE.fd
# arch=aarch64
# uefi=/usr/share/AAVMF/AAVMF_CODE.fd
# vm_ram_mb_max=8192, vm_vcpus_max=8
# # -d '{}' # -d '@file.json'
echo 'create vm' && cat <<EOF | curl -k -H 'Content-Type:application/json' -X POST -d '@-' ${srv}/vm/create/${host}
{
 "vm_arch":"${arch}",
 ${uefi:+\"vm_uefi\": \"${uefi}\",}
 "vm_vcpus" : 2,
 "vm_ram_mb" : 2048,
 "vm_desc" : "测试VM",
 "vm_ip":"192.168.168.2/32",
 "vm_gw":"192.168.168.1"
}
EOF
echo 'update metadata' && cat <<EOF | curl -k -H 'Content-Type:application/json' -X POST -d '@-' ${srv}/vm/metadata/${host}/${uuid}
{
 "key1":1,
 "key2":"val"
}
EOF
# uuid=xxxx
echo 'list device allhost' && curl -k ${srv}/tpl/device/ | jq '.[]|{name: .name}'
echo 'list device on host' && curl -k ${srv}/tpl/device/${host} | jq '.[]|{name: .name}'
echo 'list gold image' && curl -k ${srv}/tpl/gold/${arch} | jq '.[]|{arch: .arch, name: .name, desc: .desc}'
echo 'list gold image' && curl -k ${srv}/tpl/gold/ | jq '.[]|{arch: .arch, name: .name, desc: .desc}'
device=local-disk
# gold=debian12
# gold="" is datadisk
# size => G
echo 'add disk' && cat <<EOF | curl -k -H 'Content-Type:application/json' -X POST -d '@-' ${srv}/vm/attach_device/${host}/${uuid}?dev=${device}
{
 ${gold:+\"gold\": \"${gold}\",}
 "size":2
}
EOF
dev=vda
echo 'del disk'        && curl -k -H 'Content-Type:application/json' -X POST -d '{}' ${srv}/vm/detach_device/${host}/${uuid}/${dev}
echo 'change cd media' && curl -k -H 'Content-Type:application/json' -X POST -d '{"dev":"sda", "isoname":"centos7-x86_64"}' ${srv}/vm/cdrom/${host}/${uuid}/${dev}
device=net-br-ext
device=debian_installcd
echo "add ${device} noargs" && curl -k -H 'Content-Type:application/json' -X POST -d '{}' ${srv}/vm/attach_device/${host}/${uuid}?dev=${device}
echo 'list host vms'   && curl -k ${srv}/vm/list/${host}            # from host
echo 'list a vm'       && curl -k ${srv}/vm/list/${host}/${uuid}    # from host
echo 'start vm'        && curl -k ${srv}/vm/start/${host}/${uuid}
echo 'display'         && curl -k ${srv}/vm/display/${host}/${uuid} #disp=console #?timeout_mins=10 #default config.TMOUT_MINS_SOCAT, prefix default None else add '/user' prefix
echo 'commn stop vm'   && curl -k ${srv}/vm/stop/${host}/${uuid}
echo 'commn reset vm'  && curl -k ${srv}/vm/reset/${host}/${uuid}
echo 'force stop vm'   && curl -k ${srv}/vm/stop/${host}/${uuid}?force=true # force stop. destroy
echo 'vm ipaddr'       && curl -k ${srv}/vm/ipaddr/${host}/${uuid}
echo 'undefine domain' && curl -k ${srv}/vm/delete/${host}/${uuid}
# # test qemu-hook auto upload
curl -X POST ${srv}/domain/prepare/begin/${uuid} -F "file=@a.xml"
curl --cacert /etc/libvirt/pki/ca-cert.pem \
    --key /etc/libvirt/pki/server-key.pem \
    --cert /etc/libvirt/pki/server-cert.pem \
    -X POST https://kvm.registry.local/domain/prepare/begin/vm1 \
    -F file=@/etc/libvirt/qemu/vm1.xml

echo 'update all guests dbtable' && {
    for host in $(curl -k ${srv}/tpl/host/ 2>/dev/null | jq -r '.[]|.name'); do
        curl -k ${srv}/vm/list/${host} 2>/dev/null | jq -r '.'
    done
}
echo 'list all guests in database' && curl -k ${srv}/vm/list/
echo 'get vm xml" && curl -k ${srv}/vm/xml/${host}/${uuid}
epoch=$(date -d "+$((10*24*3600)) second" +%s) #10 days
echo 'get tenant vm mgr page/token/expire' curl -k ${srv}/vm/ui/${host}/${uuid}?epoch=${epoch}
echo 'get vmip' && curl -k ${srv}/vm/ipaddr/${host}/${uuid}
echo 'get blk size' && curl -k ${srv}/vm/blksize/${host}/${uuid}?dev=vda
echo 'modify desc' && curl -k ${srv}/vm/desc/${host}/${uuid}?vm_desc=message
echo 'modify mem' && curl -k '${srv}/vm/setmem/${host}/${uuid}?vm_ram_mb=2000'
echo 'modify cpu' && curl -k '${srv}/vm/setcpu/${host}/${uuid}?vm_vcpus=2'
echo 'netstat' && curl -k '${srv}/vm/netstat/${host}/${uuid}?dev=52:54:00:a9:1f:16'
---------------------------------------------------------
# token='aG9zdDAxLzZmNWQ4YmY2LWQ1ODAtNDk0Ni05NTQxLTEzZmE5OGI0YWNmND9rPWc2S0h1T1A4R0lmVTVfZFlBN0lQX1EmZT0xNzQzNDM2Nzk5'
str_token='host01/6f5d8bf6-d580-4946-9541-13fa98b4acf4?k=g6KHuOP8GIfU5_dYA7IP_Q&e=1743436799'
echo 'get vminfo by token' && curl -k "${srv}/user/vm/list/${str_token}"
echo 'start vm by token'   && curl -k "${srv}/user/vm/start/${str_token}"
echo 'reset vm by token'   && curl -k "${srv}/user/vm/reset/${str_token}"
echo 'vm vnc by token'     && curl -k "${srv}/user/vm/display/${str_token}" #disp=console
echo 'stop vm by token'    && curl -k "${srv}/user/vm/stop/${str_token}"
echo 'force stop by token' && curl -k "${srv}/user/vm/stop/${str_token}?force=true"

srv=https://vmm.registry.local
host=host01
uuid=dc115783-b0bb-4a74-86df-063f25f51a1b
echo 'create snapshot'     && curl -k -X POST -d '{}' "${srv}/vm/snapshot/${host}/${uuid}?name=snap01" # -d '{name:"xxx"}'
echo 'list snapshot'       && curl -k "${srv}/vm/snapshot/${host}/${uuid}"
echo 'delete snapshot'     && curl -k "${srv}/vm/delete_snapshot/${host}/${uuid}?name=snap01"
echo 'revert snapshot'     && curl -k "${srv}/vm/revert_snapshot/${host}/${uuid}?name=<name>"
echo 'backup' && curl -k ${srv}/conf/backup/ -o backup.tgz
# restore on overwrite files exists in backup.tgz, others keep
# # tar c devices/ domains/ meta/ vars.json hosts.json devices.json golds.json iso.json | gzip > backup.tgz
echo 'restore' && curl -k -X POST -F 'file=@backup.tgz' ${srv}/conf/restore/
echo 'list domain tpl' && curl -k  ${srv}/conf/domains/
echo 'list device tpl' && curl -k  ${srv}/conf/devices/
echo 'add host' && cat <<EOF | curl -k -H 'Content-Type:application/json' -X POST -d '@-' ${srv}/conf/addhost/
{
  "name":"hostxx",
  "tpl":"domain",
  "url":"qemu+tls://192.168.168.1/system",
  "arch":"x86_64",
  "ipaddr":"192.168.168.1",
  "sshport":60022,
  "sshuser":"root",
  "cdrom.null":"on",
  "disk.file":"on",
  "disk.rbd":"n/a",
  "net.br-ext":"on"
}
EOF
POST,DELETE /conf/host/
POST,DELETE /conf/iso/
POST,DELETE /conf/gold/
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
