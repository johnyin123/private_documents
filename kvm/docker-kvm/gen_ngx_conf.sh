#!/usr/bin/env bash
upstream() {
    cat <<'EOF'
# # tanent can multi points
upstream flask_app {
    hash $arg_k$arg_e consistent; # ip_hash; # sticky;
    server 127.0.0.1:5009 fail_timeout=0;
    keepalive 64;
}
upstream websockify {
    hash $arg_k$arg_e consistent;
    server 127.0.0.1:6800;
    keepalive 64;
}
map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}
EOF
    return 0
}

https_cfg_header() {
    local srv_name="${1}"
    cat <<EOF
server {
    listen 443 ssl;
    server_name ${srv_name};
    ssl_certificate     /etc/nginx/ssl/${srv_name}.pem;
    ssl_certificate_key /etc/nginx/ssl/${srv_name}.key;
    default_type application/json;
    error_page 403 = @403;
    location @403 { return 403 '{"code":403,"name":"lberr","desc":"Resource Forbidden"}'; }
    error_page 404 = @404;
    location @404 { return 404 '{"code":404,"name":"lberr","desc":"Resource not found"}'; }
    error_page 405 = @405;
    location @405 { return 405 '{"code":405,"name":"lberr","desc":"Method not allowed"}'; }
    error_page 502 = @502;
    location @502 { return 502 '{"code":502,"name":"lberr","desc":"backend server not alive"}'; }
    error_page 504 = @504;
    location @504 { return 504 '{"code":504,"name":"lberr","desc":"Gateway Time-out"}'; }
EOF
    return 0
}

admin_api() {
    local AUTH=${1:-}
    cat <<EOF
    ${AUTH}include /etc/nginx/http-enabled/jwt_sso_auth.inc;
    location /tpl/ {
        # # proxy cache default is on, so modify host|device|gold, should clear ngx cache
        ${AUTH}auth_request @sso-auth;
        # host/device/gold can cached by proxy_cache default
        location ~* ^/tpl/(host|device|gold|iso)/ {
            if (\$request_method !~ ^(GET)$) { return 405; }
            proxy_pass http://flask_app;
        }
        return 404;
    }
    location /vm/ {
        ${AUTH}auth_request @sso-auth;
        # # no cache!! mgr private access
        proxy_cache off;
        expires off;
        location ~* ^/vm/(ipaddr|blksize|netstat|desc|setmem|setcpu|list|start|reset|stop|delete|console|display|xml|ui|freeip)/ {
            if (\$request_method !~ ^(GET)$) { return 405; }
            # # for server stream output
            proxy_buffering                    off;
            proxy_request_buffering            off;
            proxy_pass http://flask_app;
        }
        location ~* ^/vm/(create|attach_device|detach_device|cdrom)/ {
            if (\$request_method !~ ^(POST)$) { return 405; }
            # # for server stream output
            proxy_buffering                    off;
            proxy_request_buffering            off;
            proxy_pass http://flask_app;
        }
        location ~* ^/vm/websockify/(?<kvmhost>.*)/(?<uuid>.*) {
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection \$connection_upgrade;
            proxy_pass http://websockify;
        }
        return 404;
    }
EOF
    return 0
}

tanent_api() {
    local USERKEY=${1}
    cat <<EOF
    # # tanent api
    location /user/ {
        location ~* ^/user/vm/websockify/(?<kvmhost>.*)/(?<uuid>.*) {
            proxy_cache off;
            expires off;
            set \$userkey "${USERKEY}";
            secure_link \$arg_k,\$arg_e;
            secure_link_md5 "\$userkey\$secure_link_expires\$kvmhost\$uuid";
            if (\$secure_link = "") { return 403; }
            if (\$secure_link = "0") { return 410; }
            rewrite ^/user(.*)$ \$1 break;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection \$connection_upgrade;
            proxy_pass http://websockify;
        }
        location ~* ^/user/vm/(list|start|reset|stop|console|display)/(?<kvmhost>.*)/(?<uuid>.*) {
            # # no cache!! guest user api, guest private access
            proxy_cache off;
            expires off;
            set \$userkey "${USERKEY}";
            secure_link \$arg_k,\$arg_e;
            secure_link_md5 "\$userkey\$secure_link_expires\$kvmhost\$uuid";
            if (\$secure_link = "") { return 403; }
            if (\$secure_link = "0") { return 410; }
            if (\$request_method !~ ^(GET)$ ) { return 405; }
            rewrite ^/user(.*)$ \$1 break;
            proxy_pass http://flask_app;
        }
        location ~* ^/user/vm/(cdrom)/(?<kvmhost>.*)/(?<uuid>.*) {
            # # no cache!! guest user api, guest private access
            proxy_cache off;
            expires off;
            set \$userkey "${USERKEY}";
            secure_link \$arg_k,\$arg_e;
            secure_link_md5 "\$userkey\$secure_link_expires\$kvmhost\$uuid";
            if (\$secure_link = "") { return 403; }
            if (\$secure_link = "0") { return 410; }
            if (\$request_method !~ ^(POST)$) { return 405; }
            rewrite ^/user(.*)$ \$1 break;
            proxy_pass http://flask_app;
        }
        location ~* ^/user/vm/(getiso)/(?<kvmhost>.*)/(?<uuid>.*) {
            # # /tpl/iso need cache
            set \$userkey "${USERKEY}";
            secure_link \$arg_k,\$arg_e;
            secure_link_md5 "\$userkey\$secure_link_expires\$kvmhost\$uuid";
            if (\$secure_link = "") { return 403; }
            if (\$secure_link = "0") { return 410; }
            if (\$request_method !~ ^(GET)$) { return 405; }
            set \$urieat '';
            # # just for eating uri -> /tpl/iso/,no args, can cache
            proxy_pass http://flask_app/tpl/iso/\$urieat;
            # rewrite ^.*$ /tpl/iso/ break;
            # # /tpl/iso/?k=XtaHHDjE_nULHFdM2Dsupw&e=1745423940. with args, can not cache
            # proxy_pass http://flask_app;
        }
        return 403;
    }
EOF
    return 0
}

admin_ui() {
    local OUT_DIR=${1}
    local AUTH=${2:-}
    cat <<EOF
    # # admin ui # #
    location = /admin.html { return 301 /ui/tpl.html; }
    location = /ui/tpl.html {
        ${AUTH}auth_request @sso-auth;
        alias ${OUT_DIR}/ui/tpl.html;
    }
    # # static resource # #
    # # ui/term/spice/novnc use flask_app serve, add rewrite
    # rewrite ^ /public\$uri break;proxy_pass http://flask_app;
    location /ui { alias ${OUT_DIR}/ui/; }
    location /term { alias ${OUT_DIR}/term/; }
    location /spice { alias ${OUT_DIR}/spice/; }
    location /novnc { alias ${OUT_DIR}/novnc/; }
EOF
    return 0
}

tanent_ui() {
    local OUT_DIR=${1}
    local combine=${2:-}
    cat <<'EOF'
    # # default page is guest ui
    location / { return 301 https://$server_name/guest.html; }
    # # tanent user UI manager # #
    location = /guest.html { return 301 /ui/userui.html$is_args$args; }
EOF
    "${combine}" || cat <<EOF
    # # static resource # #
    # # ui/term/spice/novnc use flask_app serve, add rewrite
    # rewrite ^ /public\$uri break;proxy_pass http://flask_app;
    location /ui { alias ${OUT_DIR}/ui/; }
    location /term { alias ${OUT_DIR}/term/; }
    location /spice { alias ${OUT_DIR}/spice/; }
    location /novnc { alias ${OUT_DIR}/novnc/; }
EOF
    return 0
}

meta_data_srv() {
    local srv_name="${1}"
    local OUT_DIR=${2}
    cat <<EOF
    # # # # # # # # # # # # # # # # # # # # # # # # #
    # # only .iso|meta-data|user-data(include subdir resource)
    location ~* (\\.iso|\\/meta-data|\\/user-data)$ { set \$limit 0; root ${OUT_DIR}/cidata; }
    location ^~ /gold { set \$limit 0; alias ${OUT_DIR}/gold/; }
    # /gold/uuid.iso => /gold/uuid.iso
    # /uuid.iso      => ${OUT_DIR}/iso/uuid.iso
}
server {
    listen 80;
    server_name ${srv_name};
    location / { return 301 https://\$server_name\$request_uri\$is_args\$args; }
    location ~* (\\.iso|\\/meta-data|\\/user-data)$ { set \$limit 0; root ${OUT_DIR}/cidata; }
    location ^~ /gold { set \$limit 0; alias ${OUT_DIR}/gold/; }
}
EOF
    return 0
}

admin_srv_name="$(python3 -c 'import config; print(config.META_SRV)' || true)"
tanent_srv_name="$(python3 -c 'import config; print(config.CTRL_PANEL_SRV)' || true)"

userkey="$(python3 -c 'import config; print(config.MYKEY_CTRL_PANEL)' || true)"
outdir="$(python3 -c 'import config; print(config.OUTDIR)' || true)"
combine=false
[ "${tanent_srv_name:-x}" == "${admin_srv_name:-y}" ] && combine=true
# auth="#"
auth="" # need auth

upstream
https_cfg_header "${admin_srv_name}"

admin_api "${auth}"
admin_ui "${outdir}" "${auth}"

"${combine}" && {
    tanent_api "${userkey}"
    tanent_ui "${outdir}" "${combine}"
    meta_data_srv "${admin_srv_name}" "${outdir}"
} || {
    meta_data_srv "${admin_srv_name}" "${outdir}"
    https_cfg_header "${tanent_srv_name}"
    tanent_api "${userkey}"
    tanent_ui "${outdir}" "${combine}"
    echo "}"
}
