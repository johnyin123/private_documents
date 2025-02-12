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
echo 'list host' && curl -k ${srv}/tpl/host | jq '.[]|{name: .name, arch: .arch}'
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
device=net-br-ext
device=debian_installcd
echo "add ${device} noargs" && curl -k -H 'Content-Type:application/json' -X POST -d '{}' ${srv}/vm/attach_device/${host}/${uuid}/${device}
echo 'list host vms' && curl -k ${srv}/vm/list/${host}                # from host
echo 'list a vm on host' && curl -k ${srv}/vm/list/${host}/${uuid}    # from host
echo 'start vm' && curl -k ${srv}/vm/start/${host}/${uuid}
echo 'display vnc' && curl -k ${srv}/vm/display/${host}/${uuid}
echo 'stop vm' && curl -k ${srv}/vm/stop/${host}/${uuid}
echo 'force stop vm' && curl -k -X DELETE ${srv}/vm/stop/${host}/${uuid} # force stop. destroy
echo 'undefine domain' && curl -k ${srv}/vm/delete/${host}/${uuid}
# # test qemu-hook auto upload
curl -X POST ${srv}/domain/prepare/begin/${uuid} -F "file=@a.xml"
curl --cacert /etc/libvirt/pki/ca-cert.pem \
    --key /etc/libvirt/pki/server-key.pem \
    --cert /etc/libvirt/pki/server-cert.pem \
    -X POST https://kvm.registry.local/domain/prepare/begin/vm1 \
    -F file=@/etc/libvirt/qemu/vm1.xml
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
