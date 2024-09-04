#!/bin/bash

# NFSPATH='192.168.168.1:/volume'
# FSTYPE='nfs4'
# OPTIONS=defaults
NFSPATH='root@192.168.168.1:/home/johnyin/disk/docker_home'
FSTYPE='sshfs'
OPTIONS=port=60022,allow_other

MNT_POINT='/home/johnyin/mame'
IDLE_TMOUT='30'
# # eat first /
SVC_NAME=${MNT_POINT#/*}
SVC_NAME="${SVC_NAME//\//-}"
echo $SVC_NAME

cat <<EOF> ${SVC_NAME}.mount
[Unit]
Description=nfs mount
After=network-online.target
DefaultDependencies=no

[Mount]
What=${NFSPATH}
Where=${MNT_POINT}
Type=${FSTYPE}
Options=${OPTIONS}
StandardOutput=journal

[Install]
WantedBy=multi-user.target
EOF


cat <<EOF> ${SVC_NAME}.automount
[Unit]
Description=nfs mount
Requires=network-online.target
#After=

[Automount]
Where=${MNT_POINT}
TimeoutIdleSec=${IDLE_TMOUT}

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF
systemctl daemon-reload
systemctl enable ${MNT_POINT}.mount
systemctl start ${MNT_POINT}.mount
systemctl status ${MNT_POINT}.mount
EOF
