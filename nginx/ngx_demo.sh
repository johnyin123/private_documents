#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("d310113[2021-11-30T12:15:44+08:00]:ngx_demo.sh")

set -o errtrace
set -o nounset
set -o errexit

:<<"EOF">location.txt
=：精确匹配，优先级最高。如果找到了这个精确匹配，则停止查找。
^~：URI 以某个常规字符串开头，不是正则匹配
~：区分大小写的正则匹配
~*：不区分大小写的正则匹配
/：通用匹配, 优先级最低。任何请求都会匹配到这个规则
# -----------------------------------------------------------------------------------------------------------------------------------
# Search-Order  Modifier   Description                                                    Match-Type        Stops-search-on-match
# -----------------------------------------------------------------------------------------------------------------------------------
#     1st      =       The URI must match the specified pattern exactly                  Simple-string              Yes
#     2nd      ^~      The URI must begin with the specified pattern                     Simple-string              Yes
#     3rd    (None)    The URI must begin with the specified pattern                     Simple-string               No
#     4th      ~       The URI must be a case-sensitive match to the specified Rx      Perl-Compatible-Rx      Yes (first match)
#     4th      ~*      The URI must be a case-insensitive match to the specified Rx    Perl-Compatible-Rx      Yes (first match)
#     N/A      @       Defines a named location block.                                   Simple-string              Yes
# -----------------------------------------------------------------------------------------------------------------------------------
EOF
cat <<EOF >speed_limit_demo.conf
server {
    listen 80;
    location = /favicon.ico { access_log off; log_not_found off; }
    location / {
        limit_speed one 100k;
        root /var/www;
    }
}
EOF

cat <<'EOF' >redis.conf
# redis-cli -x set curl/7.64.0 http://srv1
# redis-cli -x set curl/7.61.1 http://www.xxx.com
upstream srv1 {
    sticky;
    server 192.168.1.100:80;
}

upstream redis {
    server 127.0.0.1:6379;
}

server {
    listen 80;
    location / {
        # cache !!!!
        set $redis_key $uri;
        redis_pass     redis;
        default_type   text/html;
        error_page     404 = @fallback;
    }
    location /redis-test {
        eval_escalate on;
        eval $answer {
            set $redis_key "$http_user_agent";
            redis_pass redis;
        }
        proxy_pass $answer;
        error_page 404 502 504 = @fallback;
    }
    location @fallback {
        proxy_pass https://www.xxx.com;
    }
    # gzip -c index.html | redis-cli -x set /index.html
    # gzip -c index.html | redis-cli -x set /
    location /test/ {
        gunzip on;
        redis_gzip_flag 1;
        set $redis_key "$uri";
        redis_pass redis;
    }
    # location /test2/ {
    #     set $redis_key "$uri?$args";
    #     redis_pass 127.0.0.1:6379;
    #     error_page 404 502 504 = @fallback;
    # }
    # location @fallback {
    #     proxy_pass backed;
    # }
}
EOF

cat <<'EOF' >traffic_status.conf
# /{status_uri}/control?cmd=*`{command}`*&group=*`{group}`*&zone=*`{name}`*
# /control?cmd=reset&group=server&zone=*
server {
    listen 80;
    # listen 443 ssl;
    # ssl_certificate /etc/nginx/SSL/ca.pem
    # ssl_certificate_key /etc/nginx/SSL/site.key;
    # server_name status.example.org;
    # # force https
    # proxy_redirect http:// $scheme://;
    # if ($scheme = http ) {
    #     return 301 https://$server_name$request_uri;
    # }

    location / {
        vhost_traffic_status_display;
        vhost_traffic_status_display_format html;
    }
}
EOF
cat <<'EOF' > flv_movie.html
<!DOCTYPE html>
<html>
<head>
    <meta content="text/html; charset=utf-8" http-equiv="Content-Type">
    <title>flv.js demo</title>
    <style>
    .mainContainer {
    display: block;
    width: 1024px;
    margin-left: auto;
    margin-right: auto;
}
.urlInput {
    display: block;
    width: 100%;
    margin-left: auto;
    margin-right: auto;
    margin-top: 8px;
    margin-bottom: 8px;
}

.centeredVideo {
    display: block;
    width: 100%;
    height: 576px;
    margin-left: auto;
    margin-right: auto;
    margin-bottom: auto;
}

.controls {
    display: block;
    width: 100%;
    text-align: left;
    margin-left: auto;
    margin-right: auto;
}
    </style>
</head>

<body>
    <div class="mainContainer">
    <video id="videoElement" class="centeredVideo" controls autoplay width="1024" height="576">Your browser is too old which doesn't support HTML5 video.</video>
    </div>
    <br>
    <div class="controls">
    <!--<button onclick="flv_load()">加载</button>-->
    <button onclick="flv_start()">开始</button>
    <button onclick="flv_pause()">暂停</button>
    <button onclick="flv_destroy()">停止</button>
    <input style="width:100px" type="text" name="seekpoint" />
    <button onclick="flv_seekto()">跳转</button>
    </div>
    <script src="flv.min.js"></script>
    <script>
    var player = document.getElementById('videoElement');
    if (flvjs.isSupported()) {
        var flvPlayer = flvjs.createPlayer({
            type: 'flv',
            // "isLive": true,
            url: '你的视频.flv'
        });
        flvPlayer.attachMediaElement(videoElement);
        flvPlayer.load(); //加载
    }

    function flv_start() {
        player.play();
    }

    function flv_pause() {
        player.pause();
    }

    function flv_destroy() {
        player.pause();
        player.unload();
        player.detachMediaElement();
        player.destroy();
        player = null;
    }

    function flv_seekto() {
        player.currentTime = parseFloat(document.getElementsByName('seekpoint')[0].value);
    }
    </script>
</body>
</html>
EOF
cat <<'EOF' > flv_movie.conf
# flv mp4流媒体服务器, https://github.com/Bilibili/flv.js
# apt -y install yamdi
server {
    listen 80;
    root /movie/;
    limit_rate_after 5m; #在flv视频文件下载了5M以后开始限速
    limit_rate 100k;     #速度限制为100K
    index index.html;
    location ~ \.flv {
        flv;
    }
}
EOF
cat <<'EOF' > fcgiwrap.conf
# apt -y install fcgiwrap
# mkdir -p /var/www/cgi-bin && chmod 755 /var/www/cgi-bin
# cat <<CGIEOF > /var/www/cgi-bin/test.cgi
# #!/bin/bash
# printf "Content-type: text/html\n\n"
# cat << EDOC
# <html><body>CGI Script Test Page</body></html>"
# EDOC
# CGIEOF
# chmod 755 /var/www/cgi-bin/test.cgi
# systemctl enable fcgiwrap --now
# curl localhost/cgi-bin/test.cgi
server {
    listen 80;
    location = /login {
        rewrite ^ /cgi-bin/test.cgi;
    }
    location /cgi-bin/ {
        internal;
        root /var/www;
        fastcgi_pass unix:/var/run/fcgiwrap.socket;
        include /etc/nginx/fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    }
}
EOF
cat <<'EOF' > auth_basic.conf
server {
    listen 80;
    # username=user
    # password=password
    # printf "${username}:$(openssl passwd -apr1 ${password})\n" >> /etc/nginx/.htpasswd
    location / {
        auth_basic "Restricted Content";
        auth_basic_user_file /etc/nginx/.htpasswd;
    }
}
EOF
cat <<'EOF' > url_map.conf
# http://example.com/?p=contact        /contact
# http://example.com/?p=static&id=career   /career
# http://example.com/?p=static&id=about    /about
map $arg_p $url_p {
    contact    /contact;
    static     $url_id;
    # default value will be an empty string
}
map $arg_id $url_id {
    career     /career;
    about      /about;
    default    /about;
}
server {
    listen 80;
    if ($url_p) {
        # if '$url_p' variable is not an empty string
        return 301 $url_p;
    }
    location / {
        root /var/www;
    }
}
EOF
cat <<'EOF' > secure_link_demo.conf
# mkdir -p /var/www/validate && echo "downfile" > /var/www/validate/file.txt
# #!/bin/bash
# write_header() {
#     local code=${1:-200}
#     printf "Status: %s\n" ${code}
#     printf "Content-type: text/html\n\n"
# }
# do_get() {
#     write_header
#     cat << EDOC
# <html><body>
# <form id="loginForm" method="POST" action="">
# <button type="submit">Login</button>
# </form>
# </body></html>"
# EDOC
# }
# do_post() {
#     mykey=prekey
#     sec=360 #360 seconds
#     query=$(head --bytes="$CONTENT_LENGTH")
#     [ -z "$QUERY_STRING" ] && {
#     write_header 403
#     return
#     }
#     eval $QUERY_STRING
#     local secure_link_expires=$(date -d "+${sec} second" +%s)
#     local key=$(echo -n "${mykey}${secure_link_expires}${uri}" | /usr/bin/openssl md5 -binary | /usr/bin/openssl base64 | /usr/bin/tr '+ /' '-_' | /usr/bin/tr -d =)
#     printf "Location: ${uri}?k=${key}&e=${secure_link_expires}\n"
#     write_header 302
# }
# case "$REQUEST_METHOD" in
#     GET)   do_get;;
#     POST)  do_post;;
#     *)     write_header 405;;
# esac

server {
    listen 80;
    location = /login {
        rewrite ^ /cgi-bin/login;
    }
    location /cgi-bin/ {
        internal;
        root /var/www;
        fastcgi_pass unix:/var/run/fcgiwrap.socket;
        include /etc/nginx/fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    }
    location /validate {
        set $mykey prekey;
        secure_link $arg_k,$arg_e;
        secure_link_md5 "$mykey$secure_link_expires$uri";
        if ($secure_link = "") { return 302 /login?uri=$uri; }
        #if ($secure_link = "") { return 403; }
        if ($secure_link = "0") { return 410; }
        alias /var/www;
    }
}
EOF
cat <<'EOF' > secure_link.conf
map $uri $allow_file {
    default                none;
    "~*/s/(?<name>.*).txt" $name;
    "~*/s/(?<name>.*).mp4" $name;
}
# mkdir -p /var/www/secure/hls/ && echo "HLS FILE" > /var/www/secure/hls/file.txt
# mkdir -p /var/www/files/ && echo "FILES FILE" > /var/www/files/file.txt
# mkdir -p /var/www/s/ && echo "S FILE" > /var/www/s/file.txt
server {
    listen 80;
    ## Basic Secured URLs
    # echo -n 'hls/file.txtprekey' | openssl md5 -hex
    # curl http://${srv}/videos/071f5f362f9362f1d14a3ece3b0c37e6/hls/file.txt
    location /videos {
        secure_link_secret prekey;
        if ($secure_link = "") { return 403; }
        rewrite ^ /secure/$secure_link;
    }
    location /secure {
        internal;
        root /var/www;
    }
    ## Secured URLs that Expire
    # sec=3600
    # expire=$(date -d "+${sec} second" +%s)
    # client_ip=192.168.168.1
    # echo -n "${expire}/files/file.txt${client_ip} prekey" | openssl md5 -binary | openssl base64 | tr +/ -_ | tr -d =
    # curl --interface "${client_ip}" "http://${srv}/files/file.txt?k=XXXXXXXXXXXXXX&e=${expire}"
    location /files {
        root /var/www;
        secure_link $arg_k,$arg_e;
        secure_link_md5 "$secure_link_expires$uri$remote_addr prekey";
        if ($secure_link = "") { return 403; }
        if ($secure_link = "0") { return 410; }
    }
    ## Securing Segment Files with an Expiration Date
    # agent="curl/7.74.0"
    # echo -n "prekey${expire}file${agent}" | openssl md5 -binary | openssl base64 | tr +/ -_ | tr -d =
    # curl "http://${srv}/s/file.txt?md5=XXXXXXXXXXXXXX&expires=${expire}"
    location /s {
        root /var/www;
        secure_link $arg_md5,$arg_expires;
        secure_link_md5 "prekey$secure_link_expires$allow_file$http_user_agent";
        if ($secure_link = "") { return 403; }
        if ($secure_link = "0") { return 410; }
    }
}
EOF
cat <<'EOF' > secure_link_cookie.conf
server {
    listen 80;
    # sec=3600
    # secure_link_expires=$(date -d "+${sec} second" +%s)
    # uri=/login.cgi
    # secure_link_md5="prekey$secure_link_expires$uri"
    # keys=$(echo -n "${secure_link_md5}" | openssl md5 -binary | openssl base64 | tr +/ -_ | tr -d =)
    # curl -H "Cookie: md5=${keys}" -H "Cookie: expires=${secure_link_expires}" "http://${srv}${uri}"
    location / {
        root /var/www;
        secure_link $cookie_md5,$cookie_expires;
        secure_link_md5 "prekey$secure_link_expires$uri";
        if ($secure_link = "") { return 403; }
        if ($secure_link = "0") { return 410; }
    }
}
EOF
cat <<'EOF' > webdav.conf
server {
    listen 80;
    # mkdir -p /var/www/tmp/client_temp && chown nobody:nobody /var/www -R
    # curl --upload-file bigfile.iso http://localhost/upload/file1
    location /upload {
        # Do not allow PUT to a file that already exists,
        if (-f $request_filename) {
            set $deny "A";
        }
        if ($request_method = PUT) {
            set $deny "${deny}B";
        }
        # return a conflict error instead.
        if ($deny = AB) {
            return 409 "upload file exists!!";
        }
        client_max_body_size 10000m;
        # root /var/www;
        alias /var/www;
        client_body_temp_path /var/www/tmp/client_temp;
        dav_methods  PUT;
        create_full_put_path   on;
        dav_access all:r;
        # limit_except GET {
        #     allow 192.168.168.0/24;
        #     deny all;
        # }
    }
    # mykey=prekey
    # sec=3600
    # secure_link_expires=$(date -d "+${sec} second" +%s)
    # request_method=GET/PUT
    # uri=/store/file.txt
    # secure_link_md5="$mykey$secure_link_expires$uri$request_method"
    # echo -n "${secure_link_md5}" | openssl md5 -binary | openssl base64 | tr +/ -_ | tr -d =
    # curl --upload-file bigfile.iso "http://${srv}${uri}?k=XXXXXXXXXXXXXX&e=${secure_link_expires}"
    # curl http://${srv}${uri}?k=XXXXXXXXXXXXXX&e=${secure_link_expires}
    # location ~* /documents/(.*) { set $key $1; }
    # location ~ ^/(?<port>123[0-9])(?:/|$) { rewrite "^/\d{4}(?:/(.*))?" /$1 break; proxy_pass http://127.0.0.1:$port; }
    location /store {
        set $mykey prekey;
        if ($request_method !~ ^(PUT|GET)$ ) {
            return 444 "444 METHOD(PUT/GET)";
        }
        if ($request_method = GET) {
            set $mykey getkey;
        }
        alias /var/www;
        secure_link $arg_k,$arg_e;
        secure_link_md5 "$mykey$secure_link_expires$uri$request_method";
        if ($secure_link = "") { return 403; }
        if ($secure_link = "0") { return 410; }
        client_max_body_size 10000m;
        client_body_temp_path /var/www/tmp/client_temp;
        # root /var/www;
        dav_methods  PUT DELETE MKCOL COPY MOVE;
        create_full_put_path   on;
        dav_access             group:rw  all:r;
        # limit_except GET {
        #     allow 192.168.168.0/24;
        #     deny all;
        # }
    }
}
EOF
cat <<'EOF' > gateway_transparent_proxy.conf
# iptables -t nat -A PREROUTING -p tcp -m tcp --dport 80 -j DNAT --to-destination ${gate_ip}:${gate_port}
server {
    listen 8000;
    location / {
        # proxy_method      POST;
        # proxy_set_body    "token=$http_apikey&token_hint=access_token";
        proxy_pass $scheme://$host$request_uri;
        proxy_set_header Host $http_host;
        proxy_buffers 256 4k;
        proxy_max_temp_file_size 0k;
    }
}
EOF
cat <<'EOF' > memory_cached.conf
server {
    listen 80;
    location / {
        set            $memcached_key "$uri?$args";
        memcached_pass 127.0.0.1:11211;
        error_page     404 502 504 = @fallback;
    }
    location @fallback {
        return 200 "@fallback 404 502 504";
        #proxy_pass     http://backend;
    }
}
EOF
cat <<'EOF' > ab_test.conf
upstream a {
    server 127.0.0.1:3001;
}
upstream b {
    server 127.0.0.1:4001;
}
server {
    listen 3001;
    location / {
        return 200 "Served from site A! \n\n";
    }
}
server {
    listen 4001;
    location / {
        return 200 "Served from site B!! <<<<-------------------------- \n\n";
    }
}
split_clients "${arg_token}" $dynamic {
    95%     a;
    *       b;
}
server {
    listen 80;
    location / {
        if ($http_cookie ~* "shopware_sso_token=([^;]+)(?:;|$)") {
            set $token "$1";
        }
        proxy_set_header X-SHOPWARE-SSO-Token $token;
        proxy_set_header Host $host;
        proxy_pass http://$dynamic$uri$is_args$args;
    }
}
EOF
cat <<'EOF' > split_client.conf
server {
    listen 8098;
    return 200 "Results:
Server Address:\t $server_addr:$server_port
Network Remote Address:\t $remote_addr
Current time:\t\t $time_local
Request URI:\t\t $request_uri\n\n";
}
upstream backend {
    server 172.16.239.200:8098;
}
server {
    listen 80;
    location / {
        proxy_pass http://backend;
        proxy_bind $split_ip;
        proxy_set_header X-Forwarded-For $remote_addr;
    }
}
split_clients "$request_uri$remote_port" $split_ip {
    10%    172.16.239.200;
    10%    172.16.239.201;
    10%    172.16.239.202;
    10%    172.16.239.203;
    10%    172.16.239.204;
    10%    172.16.239.205;
    10%    172.16.239.206;
    10%    172.16.239.207;
    10%    172.16.239.208;
    *      172.16.239.209;
}
EOF
cat <<'EOF' > split_client.conf
split_clients "${remote_addr}" $variant {
    0.5%     .one;
    2.0%     .two;
    *    "";
}
server {
    listen 80;
    location / {
        index index${variant}.html;
        root /var/www;
    }
}
EOF
cat <<'EOF' > auth_request_by_secure_link.conf
server {
    listen 80;
    location / {
        auth_request /auth;
        root /var/www;
    }
    # srv=127.0.0.1
    # sec=3600
    # secure_link_expires=$(date -d "+${sec} second" +%s)
    # secure_link_md5="prekey$secure_link_expires"
    # keys=$(echo -n "${secure_link_md5}" | openssl md5 -binary | openssl base64 | tr +/ -_ | tr -d =)
    # curl -H "Cookie: md5=${keys}" -H "Cookie: expires=${secure_link_expires}" "http://${srv}/files.txt"
    location = /auth {
        internal;
        secure_link $cookie_md5,$cookie_expires;
        secure_link_md5 "prekey$secure_link_expires";
        if ($secure_link = "") { return 401; }
        if ($secure_link = "0") { return 410; }
        return 200 "$cookie_md5,$cookie_expires";
    }
}
EOF
cat <<'EOF' > auth_request.conf
# # # login.cgi
# #!/bin/bash
# error_msg() {
#     local fmt=$1
#     shift || true
#     printf "CGI: $fmt" "$@" >&2
# }
# # get_param $query key
# get_param() {
#     echo "$1" | tr '&' '\n' | grep "^$2=" | head -1 | sed "s/.*=//" # | urldecode
# }
# # $1 = name
# # $2 = value
# # $3 = expires seconds
# # $4 = path
# setcookie() {
#     # value=$( echo -n "$2" | urlencode )
#     value="$2"
#     [ -z "$4" ] && path="" || { path="; Path=$4"; }
#     echo -n "Set-Cookie: $1=$value$path; expires="
#     date -u --date="$3 seconds" "+%a, %d-%b-%y %H:%M:%S GMT"
# }
# write_header() {
#     local code=${1:-200}
#     printf "Status: %s\n" ${code}
#     printf "Content-type: text/html\n\n"
# }
# do_get() {
#     [ -z "$QUERY_STRING" ] && {
#         write_header 403
#         echo "NEED <uri> back address "
#         return
#     }
#     write_header
#     cat << EDOC
# <html><body>
# <form id="loginForm" method="POST" action="">
# <input type="text" id="uid" name="uid" value="">
# <input type="password" id="passwd" name="passwd" value="">
# <button type="submit">Login</button>
# </form>
# </body></html>
# EDOC
# }
# do_post() {
#     [ -z "$QUERY_STRING" ] && {
#         write_header 403
#         echo "NEED <uri> back address "
#         return
#     }
#     local query=$(head --bytes="${CONTENT_LENGTH:-0}")
#     local uid=$(get_param "${query}" "uid")
#     local passwd=$(get_param "${query}" "passwd")
#     local uri=get_param "$QUERY_STRING" "uri"
#     error_msg "LOGIN POST: uid=%s,passwd=%s | ${query} | uri=${uri}\n" "$uid" "$passwd"
#     [ -z "${uid}" ] && {
#         printf "Location: /login?$QUERY_STRING\n"
#         write_header 302
#         return
#     }
#     setcookie "uid" "$uid" 360
#     printf "Location: ${uri}\n"
#     write_header 302
# }
# case "$REQUEST_METHOD" in
#     GET)   do_get;;
#     POST)  do_post;;
#     *)     write_header 405;;
# esac
# # # auth.cgi
# #!/bin/bash
# write_header() {
#     local code=${1:-200}
#     printf "Status: %s\n" ${code}
#     printf "Content-type: text/html\n\n"
# }
# # get_param $query key
# get_param() {
#     echo "$1" | tr '&' '\n' | grep "^$2=" | head -1 | sed "s/.*=//" # | urldecode
# }
# do_get() {
#     {
#         echo "***** auth get : *****"
#         env | grep "X-MY"
#     } >&2
#     [ -z "${HTTP_COOKIE}" ] && {
#         write_header 401
#         return
#     }
#     local uid=get_param "${HTTP_COOKIE}" "uid"
#     [ -z "$uid" ] && write_header 401 || write_header 200
#     return
# }
# case "$REQUEST_METHOD" in
#     GET)   do_get;;
#     *)     write_header 405;;
# esac
#
server {
    listen 80;
    error_page 401 = @error401;
    location @error401 {
        return 302 /login?uri=$request_uri;
    }
    error_page 500 @process_backend_error;
    location @process_backend_error {
        return 200 "backend: $backend_status";
    }
    location / {
        auth_request /auth;
        auth_request_set $backend_status $upstream_status;
        root /var/www;
    }
    location = /auth {
        internal;
        # # proxy_method      POST;
        # # proxy_set_body    "token=$http_apikey&token_hint=access_token";
        # proxy_pass_request_body off;                 # no data is being transferred
        # proxy_set_header Content-Length '0';
        # proxy_set_header X-MY-FUCK $cookie_uid;
        # if ($http_cookie ~* "uid=([^&]+)") {
        #     set $token "$1";
        # }
        # proxy_pass http://127.0.0.1/valid;
        rewrite ^ /cgi-bin/auth.cgi;
    }
    location = /login {
        rewrite ^ /cgi-bin/login.cgi;
    }
    location = /valid {
        rewrite ^ /cgi-bin/auth.cgi;
    }
    location /cgi-bin/ {
        internal;
        root /var/www;
        fastcgi_pass unix:/var/run/fcgiwrap.socket;
        include /etc/nginx/fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    }
}
EOF
cat <<'EOF' > aws_s3auth.conf
# public-bucket MUST set bucket-policy.py to all read/write
upstream ceph_rgw_backend {
    server 192.168.168.131:80;
    server 192.168.168.132:80;
    server 192.168.168.133:80;
    keepalive 64;
}
server {
    listen 81;
    client_max_body_size 6000M;
    location / {
    proxy_redirect off;
    proxy_set_header X-Forwarded-For $remote_addr;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
        proxy_pass http://ceph_rgw_backend;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
    }
}
server {
    listen 80;
    # srv=192.168.168.1
    # mykey=prekey
    # sec=3600
    # secure_link_expires=$(date -d "+${sec} second" +%s)
    # request_method=GET/PUT
    # uri=/file.txt
    # secure_link_md5="$mykey$secure_link_expires$uri$request_method"
    # keys=$(echo -n "${secure_link_md5}" | openssl md5 -binary | openssl base64 | tr +/ -_ | tr -d =)
    # curl --upload-file bigfile.iso "http://${srv}${uri}?k=${keys}&e=${secure_link_expires}"
    # curl curl -X PUT http://localhost:8080/hello.txt -d 'Hello there!'
    # curl "http://${srv}${uri}?k=${keys}&e=${secure_link_expires}"
    location / {
        set $mykey prekey;
        if ($request_method !~ ^(PUT|GET)$ ) {
            return 444 "444 METHOD(PUT/GET)";
        }
        if ($request_method = GET) {
            set $mykey getkey;
        }
        secure_link $arg_k,$arg_e;
        secure_link_md5 "$mykey$secure_link_expires$uri$request_method";
        if ($secure_link = "") { return 403; }
        if ($secure_link = "0") { return 410; }
        client_max_body_size 10000m;
        proxy_pass http://ceph_rgw_backend/public-bucket${uri};
    }
}
EOF
cat <<'EOF' > sub_filter.conf
# ...........................
# sub_filter '</body>' '<a href="http://xxxx"><img style="position: fixed; top: 0; right: 0; border: 0;" sr    c="http://s3.amazonaws.com/github/ribbons/forkme_right_gray_6d6d6d.png" alt="xxxxxxxxxxxx"></a></body>';
# sub_filter '</head>' '<link rel="stylesheet" type="text/css" href="/fuck/gray.css"/></head>';
# sub_filter_once on;
# ...........................
# HTML {
# filter: grayscale(100%);
# -webkit-filter: grayscale(100%);
# -moz-filter: grayscale(100%);
# -ms-filter: grayscale(100%);
# -o-filter: grayscale(100%);
# filter: url(desaturate.svg#grayscale);
# filter:progid:DXImageTransform.Microsoft.BasicImage(grayscale=1);
# -webkit-filter: grayscale(1);
# }
# ............................
server {
    listen 80;
    location / {
        sub_filter '</body>' '<a href="http://www.xxxx.com"><img style="position: fixed; top: 0; right: 0; border: 0;" src="https://res.xxxx.com/_static_/demo.png" alt="bj idc"></a></body>';
        proxy_set_header referer http://www.xxx.net; #如果网站有验证码，可以解决验证码不显示问题
        sub_filter_once on;
        # sub_filter_types text/html;
        root /var/www;
    }
}
EOF
