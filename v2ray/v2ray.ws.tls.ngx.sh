uuid=$(cat /proc/sys/kernel/random/uuid)
alterid=0
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
            "alterId": ${alterid}
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
    ssl_client_certificate /etc/nginx/ssl/ca.pem;
    ssl_verify_client on;
    proxy_intercept_errors on;
    error_page 400 495 496 497 = @400;
    location @400 { return 500 "bad boy"; }
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
  "log": {
    "access": "access.log",
    "error":  "error.log",
    "loglevel": "info"
  },
  "inbounds": [
    {
      "listen": "127.0.0.1",
      "port": 8888,
      "protocol": "http"
    },
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
                "alterId": ${alterid}
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "tlsSettings": {
          "allowInsecure": true,
          "disableSystemRoot": true,
          "certificates": [
            {
              //"certificate": [
              //  "-----BEGIN CERTIFICATE-----",
              //  "6X1Rkl53BhhoUhx+FuYAjfL2SE4g4nV5NbKVApjynycQmPtlf5ihz+CwxFivtS8i",
              //  "YipvxqZhPN+vV9fH",
              //  "-----END CERTIFICATE-----"
              //],
              //"key": [
              //  "-----BEGIN RSA PRIVATE KEY-----",
              //  "MIIEvwIBADANBgkqhkiG9w0BAQEFAASCBKkwggSlAgEAAoIBAQDC/+Y3OPE0V8YQ",
              //  "ZJfmJdQWx/cV9NYdqZYOj5KJjA==",
              //  "-----END RSA PRIVATE KEY-----"
              //],
              "certificateFile": "/path/to/certificate.crt",
              "keyFile": "/path/to/key.key",
              "usage": "encipherment"
              // verify,encipherment,issue
            }
          ]
        },
        "wsSettings": {
          "path": "${path}"
        }
      }
    }
  ]
}
EOF
cat <<EOF >lib.systemd.system.v2ray.service
[Unit]
Description=V2Ray Service
Documentation=https://www.v2ray.com/ https://www.v2fly.org/
After=network-online.target nss-lookup.target

[Service]
Type=simple
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
DynamicUser=true
NoNewPrivileges=true
Environment=V2RAY_LOCATION_ASSET=/etc/v2ray
ExecStart=/usr/bin/v2ray -config /etc/v2ray/config.json
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
