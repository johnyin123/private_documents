https://github.com/capjamesg/lru-cache

cloud-init clean -l
cloud-init init
cloud-init schema --system --annotate
cloud-init devel schema --system --annotate
if use NOCLOUD need dhcp, and meta server(ngx) on 169.254.169.254
if use ISO no deed dhcp
# <metadata>
#   <mdconfig:meta xmlns:mdconfig="urn:iso-meta">
#     <ipaddr>192.168.168.102/24</ipaddr>
#     <gateway>192.168.168.10</gateway>
#   </mdconfig:meta>
# </metadata>
---------------------------------------------------------
'~/.ssh/config
StrictHostKeyChecking=no
UserKnownHostsFile=/dev/null
Host 192.168.168.1
    Ciphers aes256-ctr,aes192-ctr,aes128-ctr
    MACs hmac-sha1
qemu-img convert -f qcow2 -O raw tpl.qcow2 ssh://user@host:port/path/to/disk.img
qemu-img convert -f qcow2 -O raw tpl.qcow2 rbd:cephpool/disk.raw:conf=/etc/ceph/ceph.conf
---------------------------------------------------------
apt install websockify # python3-websockify
websockify --token-plugin TokenFile --token-source ./token/ 6800
virsh domdisplay xxx
# vnc://127.0.0.1:0 5900 + port
echo 'vm1: 127.0.0.1:5900' > ./token/uuid.txt
# <graphics type='vnc' autoport='yes' listen='0.0.0.0' password='abc'/>
vnc_lite.html?host=192.168.168.1&port=6800&password=abc&path=websockify/?token=vm1
https://vmm.registry.local/novnc/vnc_lite.html?password=abc&path=websockify/?token=vm1
---------------------------------------------------------
srv=http://127.0.0.1:5009
# srv=https://vmm.registry.local
echo 'list host' && curl -k ${srv}/tpl/host/ | jq '.[]|{name: .name, arch: .arch}'
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

# uuid=xxxx
echo 'list device on host' && curl -k ${srv}/tpl/device/${host} | jq '.[]|{name: .name, type: .devtype}'
echo 'list gold image' && curl -k ${srv}/tpl/gold/${host} | jq '.[]|{arch: .arch, name: .name, desc: .desc}'
device=local-disk
# gold=debian12
# gold="" is datadisk
echo 'add disk' && cat <<EOF | curl -k -H 'Content-Type:application/json' -X POST -d '@-' ${srv}/vm/attach_device/${host}/${uuid}/${device}
{
 ${gold:+\"gold\": \"${gold}\",}
 "size":"10G"
}
EOF
dev=vda
echo 'del disk' && curl -k -H 'Content-Type:application/json' -X POST -d '{}' ${srv}/vm/detach_device/${host}/${uuid}/${dev}
device=net-br-ext
device=debian_installcd
echo "add ${device} noargs" && curl -k -H 'Content-Type:application/json' -X POST -d '{}' ${srv}/vm/attach_device/${host}/${uuid}/${device}
echo 'list host vms' && curl -k ${srv}/vm/list/${host}                # from host
echo 'list a vm on host' && curl -k ${srv}/vm/list/${host}/${uuid}    # from host
echo 'start vm' && curl -k ${srv}/vm/start/${host}/${uuid}
echo 'display vnc' && curl -k ${srv}/vm/display/${host}/${uuid}
echo 'stop vm' && curl -k ${srv}/vm/stop/${host}/${uuid}
echo 'force stop vm' && curl -k -X POST -d '{}' ${srv}/vm/stop/${host}/${uuid} # force stop. destroy
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
echo 'get freeip" && curl -k ${srv}/vm/freeip/
epoch=$(date -d "+$((10*24*3600)) second" +%s) #10 days
echo 'get tenant vm mgr page/token/expire' curl -k ${srv}/vm/ui/${host}/${uuid}/${epoch}
---------------------------------------------------------
# token='aG9zdDAxLzZmNWQ4YmY2LWQ1ODAtNDk0Ni05NTQxLTEzZmE5OGI0YWNmND9rPWc2S0h1T1A4R0lmVTVfZFlBN0lQX1EmZT0xNzQzNDM2Nzk5'
str_token='host01/6f5d8bf6-d580-4946-9541-13fa98b4acf4?k=g6KHuOP8GIfU5_dYA7IP_Q&e=1743436799'
echo 'get vminfo by token' && curl -k "${srv}/user/vm/list/${str_token}"
echo 'start vm by token' && curl -k "${srv}/user/vm/start/${str_token}"
echo 'vm vnc by token' && curl -k "${srv}/user/vm/display/${str_token}"
echo 'stop vm by token' && curl -k "${srv}/user/vm/stop/${str_token}"
echo 'force stop vm by token' && curl -k -X POST -d '{}' "${srv}/user/vm/stop/${str_token}"
---------------------------------------------------------
NGXSSL=/etc/nginx/ssl
install -v -d -m 0755 "${NGXSSL}"
install -v -C -m 0644 "ca.pem" "${NGXSSL}/kvm.ca.pem"
install -v -C -m 0644 "kvm.registry.local.pem" "${NGXSSL}/"
install -v -C -m 0644 "kvm.registry.local.key" "${NGXSSL}/"
install -v -C -m 0644 "vmm.registry.local.pem" "${NGXSSL}/"
install -v -C -m 0644 "vmm.registry.local.key" "${NGXSSL}/"

#libvirt client
KVMSSL=/etc/pki
install -v -d -m 0755 "${KVMSSL}"
install -v -d -m 0755 "${KVMSSL}/CA"
install -v -d -m 0755 "${KVMSSL}/private"
install -v -C -m 0644 "ca.pem" "${KVMSSL}/CA/cacert.pem"
install -v -C -m 0644 "cli.pem" "${KVMSSL}/clientcert.pem"
install -v -C -m 0644 "cli.key" "${KVMSSL}/private/clientkey.pem"


#libvirt server
KVM_SRV_SSL=/etc/libvirt/pki
install -v -d -m 0755 "${KVM_SRV_SSL}"
install -v -C -m 0444 "ca.pem" "${KVM_SRV_SSL}/cacert.pem"
install -v -C -m 0440 --group=qemu --owner=root "kvm1.local.key" "${KVM_SRV_SSL}/server-key.pem"
install -v -C -m 0444 --group=qemu --owner=root "kvm1.local.pem" "${KVM_SRV_SSL}/server-cert.pem"

# # cloud-init nocloud
Method 1: Line configuration
The “line configuration” is a single string of text which is passed to an instance at boot time via either the kernel command line or in the serial number exposed via DMI (sometimes called SMBIOS).
Example:
ds=nocloud;s=https://<host>/<path>/
# A valid seedfrom value consists of a URI which must contain a trailing /.
Available DMI variables for expansion in seedfrom URL
        dmi.baseboard-asset-tag
        dmi.baseboard-manufacturer
        dmi.baseboard-version
        dmi.bios-release-date
        dmi.bios-vendor
        dmi.bios-version
        dmi.chassis-asset-tag
        dmi.chassis-manufacturer
        dmi.chassis-serial-number
        dmi.chassis-version
        dmi.system-manufacturer
        dmi.system-product-name
        dmi.system-serial-number
        dmi.system-uuid
        dmi.system-version

# -smbios type=1,serial=ds=nocloud;s=http://ip:port/__dmi.system-uuid__/
https://IP:PORT/uuid/meta-data
https://IP:PORT/uuid/user-data
https://IP:PORT/uuid/vendor-data
https://IP:PORT/uuid/network-config
