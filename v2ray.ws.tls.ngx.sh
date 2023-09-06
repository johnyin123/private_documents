uuid=$(cat /proc/sys/kernel/random/uuid)
path=/wssvc
#V2Ray自4.18.1后支持TLS1.3
cat <<EOF > v2ray.srv.config.json
{
  "inbounds": [
    {
      "port": 10000,
      "listen":"127.0.0.1",
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "${uuid}",
            "alterId": 0
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "${path}"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
EOF

cat <<EOF > v2ray.http
server {
    listen 443 ssl;
    server_name _;
    ssl_certificate /etc/nginx/ssl/test.pem;
    ssl_certificate_key /etc/nginx/ssl/test.key;
    # ssl_protocols       TLSv1 TLSv1.1 TLSv1.2;
    # ssl_protocols       TLSv1.3;
    # ssl_client_certificate /etc/nginx/ssl/ca.pem;
    # ssl_verify_client on;
    location ${path} { #与V2Ray配置中的path保持一致
        if (\$http_upgrade != "websocket") {
            # WebSocket协商失败时返回404
            return 404;
        }
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF

cat <<EOF > v2ray.cli.config.json
{
  "inbounds": [
    {
      "port": 1080,
      "listen": "127.0.0.1",
      "protocol": "socks",
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      },
      "settings": {
        "auth": "noauth",
        "udp": false
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "vmess",
      "settings": {
        "vnext": [
          {
            "address": "<you v2srv address>",
            "port": 443,
            "users": [
              {
                "id": "${uuid}",
                "alterId": 64
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "tlsSettings": {
          "allowInsecure": false,
          "disableSystemRoot": true
          "certificates": [
            {
              "certificateFile": "/path/to/certificate.crt",
              "keyFile": "/path/to/key.key",
              "usage": "verify" //encipherment,issue
            }
          ]
        }
        "wsSettings": {
          "path": "${path}"
        }
      }
    }
  ]
}
EOF
