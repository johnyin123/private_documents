echo "download from https://github.com/meilisearch/meilisearch"

useradd -d /var/lib/meilisearch -b /bin/false -m -r meilisearch
mkdir -p /var/lib/meilisearch/dumps
mkdir -p /var/lib/meilisearch/snapshots
chown -R meilisearch:meilisearch /var/lib/meilisearch
chmod 750 /var/lib/meilisearch
# chown meilisearch:meilisearch /usr/bin/meilisearch
cat <<'EOF' > /etc/systemd/system/meilisearch.service
[Unit]
Description=Meilisearch
After=systemd-user-sessions.service

[Service]
Type=simple
WorkingDirectory=/var/lib/meilisearch
ExecStart=/usr/bin/meilisearch --config-file-path /etc/meilisearch.toml
User=meilisearch
Group=meilisearch

[Install]
WantedBy=multi-user.target
EOF

curl https://raw.githubusercontent.com/meilisearch/meilisearch/latest/config.toml > /etc/meilisearch.toml

master_key=$(openssl rand -hex 30)

sed --quiet -i -E \
    -e '/^\s*(env|master_key|db_path|dump_dir|snapshot_dir)\s*=.*/!p' \
    -e '$aenv = "production"' \
    -e "\$amaster_key = \"${}\"" \
    -e '$adb_path = "/var/lib/meilisearch/data"' \
    -e '$adump_dir = "/var/lib/meilisearch/dumps"' \
    -e '$asnapshot_dir = "/var/lib/meilisearch/snapshots"' \
    /etc/meilisearch.toml

sed --quiet -i -E \
    -e '/^\s*(no_analytics|max_indexing_memory|max_indexing_threads|http_payload_size_limit)\s*=.*/!p' \
    -e '$ano_analytics = true' \n
    -e '$amax_indexing_memory = "1 GiB"' \
    -e '$amax_indexing_threads = 1' \
    -e '$ahttp_payload_size_limit = "100 MB"' \
    /etc/meilisearch.toml

cat <<'EOF'
server {

    listen 443 ssl;
    listen [::]:443 ssl;

    http2 on;
    http3 on;
    quic_retry on;

    server_name meilisearch.example.com;

    access_log  /var/log/nginx/meilisearch.access.log;
    error_log   /var/log/nginx/meilisearch.error.log;

    ssl_certificate      /etc/letsencrypt/live/meilisearch.example.com/fullchain.pem;
    ssl_certificate_key  /etc/letsencrypt/live/meilisearch.example.com/privkey.pem;
    ssl_trusted_certificate /etc/letsencrypt/live/meilisearch.example.com/chain.pem;

    ssl_session_timeout  5m;
    ssl_session_cache shared:MozSSL:10m;
    ssl_session_tickets off;
    ssl_early_data on;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
    ssl_ecdh_curve X25519:prime256v1:secp384r1:secp521r1;
    ssl_stapling on;
    ssl_stapling_verify on;
    ssl_dhparam /etc/ssl/certs/dhparam.pem;

    location / {
        proxy_pass http://localhost:7700;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
# enforce HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name  meilisearch.example.com;
    return 301   https://$host$request_uri;
}
EOF
