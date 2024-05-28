cat > ~/.xserverrc <<"EOF"
#!/bin/sh
#Start an X server with power management disabled so that the screen never goes blank.
exec /usr/bin/X -s 0 -dpms -nolisten tcp "$@"
EOF

cat > ~/.xsession <<-EOF
#!/bin/sh
#This tells X server to start Chromium at startup
chromium-browser --start-fullscreen --window-size=1920,1080 --disable-infobars --noerrdialogs --incognito --kiosk http://localhost
EOF

sudo tee /etc/systemd/system/clock.service > /dev/null <<EOF
[Unit]
Description=Clock
After=network-online.target
DefaultDependencies=no

[Service]
User=myuser
ExecStart=/usr/bin/startx
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl enable clock
sudo systemctl restart clock
