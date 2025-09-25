#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit
log() { echo "$(tput setaf 141)$*$(tput sgr0)" >&2; }

upstream() {
    cat <<'EOF'
upstream api_srv {
    server 127.0.0.1:5009 fail_timeout=0;
    keepalive 64;
}
upstream websockify_srv {
    server 127.0.0.1:6800;
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
    error_page 410 = @410;
    location @410 { return 410 '{"code":410,"name":"lberr","desc":"Access expired"}'; }
    error_page 502 = @502;
    location @502 { return 502 '{"code":502,"name":"lberr","desc":"backend server not alive"}'; }
    error_page 504 = @504;
    location @504 { return 504 '{"code":504,"name":"lberr","desc":"Gateway Time-out"}'; }
EOF
    return 0
}

admin_api() {
    local USERKEY=${1}
    local PRE=${2:-}
    local AUTH=${3:-}
    cat <<EOF
    ${AUTH}include /etc/nginx/http-enabled/jwt_sso_auth.inc;
    location ${PRE}/tpl/ {
        # # proxy cache default is on, so modify host|device|gold, should clear ngx cache
        ${AUTH}auth_request @sso-auth;
        # host/device/gold can cached by proxy_cache default
        location ~* ^${PRE}/tpl/(?<apicmd>(host|device|gold|iso))/(?<others>.*)$ {
            if (\$request_method !~ ^(GET)$) { return 405; }
            # # rewrite .....
            proxy_pass http://api_srv/tpl/\$apicmd/\$others\$is_args\$args;
        }
        return 404;
    }
    location = @prestart {
        internal;
        proxy_cache off;
        proxy_method 'GET';
        proxy_pass http://api_srv\$auth_request_uri;
        proxy_pass_request_body off;
        proxy_set_header Content-Length "";
    }
    location ${PRE}/vm/ {
        ${AUTH}auth_request @sso-auth;
        # # no cache!! mgr private access
        proxy_cache off;
        expires off;
        proxy_read_timeout 240s;
        location ~* ^${PRE}/vm/(?<apicmd>(snapshot))/(?<others>.*)$ {
            if (\$request_method !~ ^(GET|POST)$) { return 405; }
            # # for server stream output
            proxy_buffering                    off;
            proxy_request_buffering            off;
            proxy_pass http://api_srv/vm/\$apicmd/\$others\$is_args\$args;
        }
        location ~* ^${PRE}/vm/(?<apicmd>(ipaddr|blksize|netstat|desc|setmem|setcpu|list|start|reset|stop|delete|display|xml|ui|revert_snapshot|delete_snapshot))/(?<others>.*)$ {
            if (\$request_method !~ ^(GET)$) { return 405; }
            # # for server stream output
            proxy_buffering                    off;
            proxy_request_buffering            off;
            proxy_pass http://api_srv/vm/\$apicmd/\$others\$is_args\$args;
        }
        location ~* ^${PRE}/vm/(?<apicmd>(create|attach_device|detach_device|cdrom|metadata))/(?<others>.*)$ {
            if (\$request_method !~ ^(POST)$) { return 405; }
            # # for server stream output
            proxy_buffering                    off;
            proxy_request_buffering            off;
            proxy_pass http://api_srv/vm/\$apicmd/\$others\$is_args\$args;
        }
        location ~* ^${PRE}/vm/websockify/(?<kvmhost>.*)/(?<uuid>.*)$ {
            set \$auth_request_uri "/vm/websockify/\$kvmhost/\$uuid\$is_args\$args";
            auth_request @prestart;
            set \$userkey "${USERKEY}";
            secure_link \$arg_k,\$arg_e;
            secure_link_md5 "\$userkey\$secure_link_expires\$kvmhost\$uuid";
            if (\$secure_link = "") { return 403; }
            if (\$secure_link = "0") { return 410; }
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection \$connection_upgrade;
            proxy_pass http://websockify_srv/websockify/\$is_args\$args;
        }
        return 404;
    }
EOF
    return 0
}

tanent_api() {
    local PRE=${1}
    local USERKEY=${2}
    cat <<EOF
    # # tanent api
    location = @prestart_user {
        internal;
        proxy_cache off;
        proxy_method 'GET';
        proxy_pass http://api_srv\$user_auth_request_uri;
        proxy_pass_request_body off;
        proxy_set_header Content-Length "";
    }
    location ${PRE}/user/ {
        location ~* ^${PRE}/user/vm/websockify/(?<kvmhost>.*)/(?<uuid>.*)$ {
            proxy_cache off;
            expires off;
            # # first secure_link check, then auth_request
            set \$user_auth_request_uri "/vm/websockify/\$kvmhost/\$uuid\$is_args\$args";
            auth_request @prestart_user;
            set \$userkey "${USERKEY}";
            secure_link \$arg_k,\$arg_e;
            secure_link_md5 "\$userkey\$secure_link_expires\$kvmhost\$uuid";
            if (\$secure_link = "") { return 403; }
            if (\$secure_link = "0") { return 410; }
            rewrite ^${PRE}/user(.*)$ \$1 break;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection \$connection_upgrade;
            proxy_pass http://websockify_srv;
        }
        location ~* ^${PRE}/user/vm/(?<apicmd>(snapshot))/(?<kvmhost>.*)/(?<uuid>.*)$ {
            # # no cache!! guest user api, guest private access
            proxy_cache off;
            expires off;
            set \$userkey "${USERKEY}";
            secure_link \$arg_k,\$arg_e;
            secure_link_md5 "\$userkey\$secure_link_expires\$kvmhost\$uuid";
            if (\$secure_link = "") { return 403; }
            if (\$secure_link = "0") { return 410; }
            if (\$request_method !~ ^(GET|POST)$ ) { return 405; }
            rewrite ^${PRE}/user(.*)$ \$1 break;
            proxy_pass http://api_srv;
        }
        location ~* ^${PRE}/user/vm/(?<apicmd>(list|start|reset|stop|display|revert_snapshot|delete_snapshot))/(?<kvmhost>.*)/(?<uuid>.*)$ {
            # # no cache!! guest user api, guest private access
            proxy_cache off;
            expires off;
            set \$userkey "${USERKEY}";
            secure_link \$arg_k,\$arg_e;
            secure_link_md5 "\$userkey\$secure_link_expires\$kvmhost\$uuid";
            if (\$secure_link = "") { return 403; }
            if (\$secure_link = "0") { return 410; }
            if (\$request_method !~ ^(GET)$ ) { return 405; }
            rewrite ^${PRE}/user(.*)$ \$1 break;
            proxy_pass http://api_srv;
        }
        location ~* ^${PRE}/user/vm/(?<apicmd>(cdrom))/(?<kvmhost>.*)/(?<uuid>.*)$ {
            # # no cache!! guest user api, guest private access
            proxy_cache off;
            expires off;
            set \$userkey "${USERKEY}";
            secure_link \$arg_k,\$arg_e;
            secure_link_md5 "\$userkey\$secure_link_expires\$kvmhost\$uuid";
            if (\$secure_link = "") { return 403; }
            if (\$secure_link = "0") { return 410; }
            if (\$request_method !~ ^(POST)$) { return 405; }
            rewrite ^${PRE}/user(.*)$ \$1 break;
            proxy_pass http://api_srv;
        }
        location ~* ^${PRE}/user/vm/(?<apicmd>(getiso))/(?<kvmhost>.*)/(?<uuid>.*)$ {
            # # /tpl/iso need cache
            set \$userkey "${USERKEY}";
            secure_link \$arg_k,\$arg_e;
            secure_link_md5 "\$userkey\$secure_link_expires\$kvmhost\$uuid";
            if (\$secure_link = "") { return 403; }
            if (\$secure_link = "0") { return 410; }
            if (\$request_method !~ ^(GET)$) { return 405; }
            set \$urieat '';
            # # just for eating uri -> /tpl/iso/,no args, can cache
            proxy_pass http://api_srv/tpl/iso/\$urieat;
            # rewrite ^.*$ /tpl/iso/ break;
            # # /tpl/iso/?k=XtaHHDjE_nULHFdM2Dsupw&e=1745423940. with args, can not cache
            # proxy_pass http://api_srv;
        }
        return 403;
    }
EOF
    return 0
}

admin_ui() {
    local PRE=${1}
    local OUT_DIR=${2}
    local AUTH=${3:-}
    cat <<EOF
    # # admin ui # #
    location = ${PRE}/admin.html { absolute_redirect off; return 301 ${PRE}/ui/tpl.html; }
    location = ${PRE}/ui/tpl.html {
        ${AUTH}auth_request @sso-auth;
        alias ${OUT_DIR}/ui/tpl.html;
    }
    # # static resource # #
    # # ui/term/spice/novnc use api_srv serve, add rewrite
    # rewrite ^ /public\$uri break;proxy_pass http://api_srv;
    location ${PRE}/ui    { alias ${OUT_DIR}/ui/; }
    location ${PRE}/term  { alias ${OUT_DIR}/term/; }
    location ${PRE}/spice { alias ${OUT_DIR}/spice/; }
    location ${PRE}/novnc { alias ${OUT_DIR}/novnc/; }
EOF
    return 0
}

tanent_ui() {
    local PRE=${1}
    local OUT_DIR=${2}
    local combine=${3:-}
    cat <<EOF
    # # default page is guest ui
    location / { absolute_redirect off; return 301 ${PRE}/guest.html; }
    # # tanent user UI manager # #
    location = ${PRE}/guest.html { absolute_redirect off; return 301 ${PRE}/ui/userui.html\$is_args\$args; }
EOF
    "${combine}" || cat <<EOF
    # # static resource # #
    # # ui/term/spice/novnc use api_srv serve, add rewrite
    # rewrite ^ /public\$uri break;proxy_pass http://api_srv;
    location ${PRE}/ui    { alias ${OUT_DIR}/ui/; }
    location ${PRE}/term  { alias ${OUT_DIR}/term/; }
    location ${PRE}/spice { alias ${OUT_DIR}/spice/; }
    location ${PRE}/novnc { alias ${OUT_DIR}/novnc/; }
EOF
    return 0
}

meta_data_srv() {
    local srv_name="${1}"
    local OUT_DIR=${2}
    cat <<EOF
}
server {
    listen 80;
    server_name ${srv_name};
    access_log off;
    log_not_found on;
    location / { return 301 https://\$host\$request_uri; }
    # # # # # # # # # # # # # # # # # # # # # # # # #
    # # only .iso|meta-data|user-data(include subdir resource)
    location ~* (\\.iso|\\/meta-data|\\/user-data)$ { access_log off; log_not_found on; set \$limit 0; root ${OUT_DIR}/cidata; }
    # # golds.json,iso.json, kvm support 301
    # location ^~ /gold { return 301 http://<addr>:8888/...; }
    location ^~ /gold { access_log off; log_not_found on; set \$limit 0; alias ${OUT_DIR}/gold/; }
    # /gold/uuid.iso => /gold/uuid.iso
    # /uuid.iso      => ${OUT_DIR}/iso/uuid.iso
}
EOF
    return 0
}
export PYTHONDONTWRITEBYTECODE=1
admin_srv_name="$(python3 -c 'import config; print(config.META_SRV)' || true)"
tanent_srv_name="$(python3 -c 'import config; print(config.CTRL_PANEL_SRV)' || true)"

userkey="$(python3 -c 'import config; print(config.CTRL_PANEL_KEY)' || true)"
outdir="$(python3 -c 'import config; print(config.DATA_DIR)' || true)"
##################################################
auth="#"
# auth="" # need auth
admin_uri_prefix="" # "/admin"
tanent_uri_prefix="" # "/tanent"

upstream
https_cfg_header "${admin_srv_name}"
admin_api "${userkey}" "${admin_uri_prefix}" "${auth}"
admin_ui "${admin_uri_prefix}" "${outdir}" "${auth}"

combine=false
[ "${tanent_srv_name}" == "${admin_srv_name}" ] && [ "${tanent_uri_prefix}" == "${admin_uri_prefix}" ] && combine=true

"${combine}" && {
    tanent_api "${tanent_uri_prefix}" "${userkey}"
    tanent_ui "${tanent_uri_prefix}" "${outdir}" "${combine}"
    meta_data_srv "${admin_srv_name}" "${outdir}"
} || {
    meta_data_srv "${admin_srv_name}" "${outdir}"
    https_cfg_header "${tanent_srv_name}"
    tanent_api "${tanent_uri_prefix}" "${userkey}"
    tanent_ui "${tanent_uri_prefix}" "${outdir}" "${combine}"
    echo "}"
}
log "ENV: DATA_DIR"
log "ENV: META_SRV"
log "ENV: CTRL_PANEL_SRV"
log "ENV: CTRL_PANEL_KEY"
log "DATA_DIR=/dev/shm/simplekvm META_SRV=simplekvm.registry.local CTRL_PANEL_SRV=user.registry.local CTRL_PANEL_KEY='newpassword' ./gen_ngx_conf.sh"
