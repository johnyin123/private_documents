#!/usr/bin/env bash
PASSWORD=password
#实例id，随便写个不冲突的
cat <<EOF > meta-data
instance-id: 10086  
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
           address: 192.168.23.14/24
           gateway: 192.168.23.1
EOF
cat <<EOF > user-data
#cloud-config
hostname: test
manage_etc_hosts: true
user: root
password: ${PASSWORD}
chpasswd: { expire: False }
# timezone
timezone: Asia/Shanghai
write_files:
- content: |
    mesg1
    mesg2
  path: /etc/test.file
  permissions: '0644'
# runcmd 执行一些命令
runcmd:
  - [echo, message]
# final_message
final_message: |
  cloud-init has finished
  datasource: \$datasource
EOF
echo "genisoimage -output my-cloud-init.iso -volid cidata -joliet -rock user-data meta-data network-config"

