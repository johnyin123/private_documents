#!/usr/bin/env bash
upstream() {
    cat <<'EOF'
# # tanent can multi points, upstream loadbalance: hash $arg_k$arg_e consistent; # ip_hash; # sticky;
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
    local PRE=${1:-}
    local AUTH=${2:-}
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
    location ${PRE}/vm/ {
        ${AUTH}auth_request @sso-auth;
        # # no cache!! mgr private access
        proxy_cache off;
        expires off;
        proxy_read_timeout 240s;
        location ~* ^${PRE}/vm/(?<apicmd>(ipaddr|blksize|netstat|desc|setmem|setcpu|list|start|reset|stop|delete|console|display|xml|ui))/(?<others>.*)$ {
            if (\$request_method !~ ^(GET)$) { return 405; }
            # # for server stream output
            proxy_buffering                    off;
            proxy_request_buffering            off;
            proxy_pass http://api_srv/vm/\$apicmd/\$others\$is_args\$args;
        }
        location ~* ^${PRE}/vm/(?<apicmd>(create|attach_device|detach_device|cdrom))/(?<others>.*)$ {
            if (\$request_method !~ ^(POST)$) { return 405; }
            # # for server stream output
            proxy_buffering                    off;
            proxy_request_buffering            off;
            proxy_pass http://api_srv/vm/\$apicmd/\$others\$is_args\$args;
        }
        location ~* ^${PRE}/vm/websockify/(?<kvmhost>.*)/(?<uuid>.*)$ {
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
    location ${PRE}/user/ {
        location ~* ^${PRE}/user/vm/websockify/(?<kvmhost>.*)/(?<uuid>.*)$ {
            proxy_cache off;
            expires off;
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
        location ~* ^${PRE}/user/vm/(?<apicmd>(list|start|reset|stop|console|display))/(?<kvmhost>.*)/(?<uuid>.*)$ {
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
    location = ${PRE}/admin.html { return 301 ${PRE}/ui/tpl.html; }
    location = ${PRE}/ui/tpl.html {
        ${AUTH}auth_request @sso-auth;
        alias ${OUT_DIR}/ui/tpl.html;
    }
    # # static resource # #
    # # ui/term/spice/novnc use api_srv serve, add rewrite
    # rewrite ^ /public\$uri break;proxy_pass http://api_srv;
    location ${PRE}/ui { alias ${OUT_DIR}/ui/; }
    location ${PRE}/term { alias ${OUT_DIR}/term/; }
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
    location / { return 301 https://\$host${PRE}/guest.html; }
    # # tanent user UI manager # #
    location = ${PRE}/guest.html { return 301 /ui/userui.html\$is_args\$args; }
EOF
    "${combine}" || cat <<EOF
    # # static resource # #
    # # ui/term/spice/novnc use api_srv serve, add rewrite
    # rewrite ^ /public\$uri break;proxy_pass http://api_srv;
    location ${PRE}/ui { alias ${OUT_DIR}/ui/; }
    location ${PRE}/term { alias ${OUT_DIR}/term/; }
    location ${PRE}/spice { alias ${OUT_DIR}/spice/; }
    location ${PRE}/novnc { alias ${OUT_DIR}/novnc/; }
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
    location / { return 301 https://\$host\$request_uri\$is_args\$args; }
    location ~* (\\.iso|\\/meta-data|\\/user-data)$ { set \$limit 0; root ${OUT_DIR}/cidata; }
    location ^~ /gold { set \$limit 0; alias ${OUT_DIR}/gold/; }
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
admin_api "${admin_uri_prefix}" "${auth}"
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
