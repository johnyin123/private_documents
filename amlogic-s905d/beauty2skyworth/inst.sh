#!/usr/bin/env bash
cat <<EOF > beauty.service
[Unit]
Description=beauty r1 enum SKYWORTH remote control
After=graphical.target
    
[Service]
ExecStart=/usr/sbin/beauty

[Install]
WantedBy=graphical.target
EOF
ln -s /etc/johnyin/beauty/beauty.service /etc/systemd/system/beauty.service
ln -s /etc/johnyin/beauty/beauty /usr/sbin/beauty
