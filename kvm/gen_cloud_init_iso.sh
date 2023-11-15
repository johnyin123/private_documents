#!/usr/bin/env bash
ISO_FNAME=${ISO_FNAME:-cloud-init.iso}
VM_NAME=${VM_NAME:-vmsrv}
UUID=${UUID:-$(cat /proc/sys/kernel/random/uuid)}
PASSWORD=${PASSWORD:-password}
IPADDR=${IPADDR:-192.168.168.211/24}
GATEWAY=${GATEWAY:-192.168.168.1}
cat <<EOF
PASSWORD = ${PASSWORD}
IPADDR   = ${IPADDR}
GATEWAY  = ${GATEWAY}
EOF
#实例id，随便写个不冲突的
cat <<EOF > meta-data
instance-id: ${UUID}
EOF
cat <<EOF > network-config
network:
  version: 1
  config:
    - type: physical
      name: eth0
      # mac_address: '00:11:22:33:44:55'
      subnets:
         - type: static
           address: ${IPADDR}
           gateway: ${GATEWAY}
EOF
cat <<EOF > user-data
#cloud-config
hostname: ${VM_NAME}
manage_etc_hosts: true
user: root
password: ${PASSWORD}
chpasswd: { expire: False }
# timezone
timezone: Asia/Shanghai
users:
  - default
  - name: admin
    groups: sudo
    passwd: '$(mkpasswd --method=SHA-512 --rounds=4096 password)'
    lock-passwd: false
    ssh_pwauth: True
    chpasswd: { expire: False }
    shell: /bin/bash
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    ssh-authorized-keys:
      - ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDIcCEBlGLWfQ6p/6/QAR1LncKGlFoiNvpV3OUzPEoxJfw5ChIc95JSqQQBIM9zcOkkmW80ZuBe4pWvEAChdMWGwQLjlZSIq67lrpZiql27rL1hsU25W7P03LhgjXsUxV5cLFZ/3dcuLmhGPbgcJM/RGEqjNIpLf34PqebJYqPz9smtoJM3a8vDgG3ceWHrhhWNdF73JRzZiDo8L8KrDQTxiRhWzhcoqTWTrkj2T7PZs+6WTI+XEc8IUZg/4NvH06jHg8QLr7WoWUtFvNSRfuXbarAXvPLA6mpPDz7oRKB4+pb5LpWCgKnSJhWl3lYHtZ39bsG8TyEZ20ZAjluhJ143GfDBy8kLANSntfhKmeOyolnz4ePf4EjzE3WwCsWNrtsJrW3zmtMRab7688vrUUl9W2iY9venrW0w6UL7Cvccu4snHLaFiT6JSQSSJS+mYM5o8T0nfIzRi0uxBx4m9/6nVIl/gs1JApzgWyqIi3opcALkHktKxi76D0xBYAgRvJs= root@liveos
growpart:
  mode: auto
  devices: ['/']

# write_files:
# - content: |
#     mesg1
#     mesg2
#   path: /etc/test.file
#   permissions: '0644'

# every boot
bootcmd:
  - [ sh, -c, 'echo ran cloud-init again at \$(date) | sudo tee -a /root/bootcmd.log' ]
# run once for network static IP fix
runcmd:
    - [ sh, -c, 'ip a' ]
# final_message
final_message: |
  cloud-init has finished
  datasource: \$datasource
EOF
genisoimage -output "${ISO_FNAME}" -volid cidata -joliet -rock user-data meta-data network-config
echo 'mkisofs -o "${ISO_FNAME}" -V cidata -J -r user-data meta-data network-config'
rm -f user-data meta-data network-config
