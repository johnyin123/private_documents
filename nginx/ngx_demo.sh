#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("56eb439[2022-02-09T15:39:35+08:00]:ngx_demo.sh")

set -o errtrace
set -o nounset
set -o errexit
cat <<'EOF'>check_conf.sh
#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
str_ends() {
    [ "${1%*$2}" != "$1" ]
}
conf=${1:-dummy.http}
echo "check config ${DIRNAME}/${conf}"
target=/etc/nginx/http-enabled/${conf}.conf
str_ends "${conf}" "conf" && target=/etc/nginx/http-conf.d/${conf}
str_ends "${conf}" "module" && target=/etc/nginx/modules.d/${conf}.conf
str_ends "${conf}" "stream" && target=/etc/nginx/stream-enabled/${conf}.conf
rm -f ${target} && ln -s ${DIRNAME}/${conf} ${target}
nginx -t 2>&1 && {
    echo "[OK] check config ${DIRNAME}/${conf}"
} || {
    cat ${target}
    echo "[FAILED] check config ${DIRNAME}/${conf}"
}
rm -f ${target}
EOF
chmod 755 check_conf.sh
cat <<'EOF'>ssl_client_cert.http
# curl -k --key client_test.key --cert client_test.pem --cacert ca.pem  https://localhost/
server {
    listen 443 ssl reuseport;
    server_name _;
    ssl_certificate /etc/nginx/ssl/test.pem;
    ssl_certificate_key /etc/nginx/ssl/test.key;
    ssl_dhparam /etc/nginx/dh2048.pem;
    ssl_client_certificate /etc/nginx/ssl/ca.pem;
    ssl_verify_client on;
    location / { return 200 "$ssl_client_s_dn"; }
}
EOF
cat <<"EOF">location.txt
git clone https://github.com/nginx/nginx-tests.git
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
cat <<'EOF' >dash.html
<!DOCTYPE html>
<html lang="en">
    <head>
        <meta charset="UTF-8">
        <title>DASH Live Streaming</title>
        <link href="https://vjs.zencdn.net/7.5.5/video-js.css" rel="stylesheet">
        <script src="https://vjs.zencdn.net/7.5.5/video.js"></script>
    </head>
    <body>
        <h1>DASH Player</h1>
        <video id="player" class="video-js vjs-default-skin" width="720" controls preload="auto">
            <source src="/dash/test_src.mpd" type="application/dash+xml" />
        </video>
        <script>
            var player = videojs('#player');
        </script>
        <div id="footer">
              <font size="2">footer</font>
        </div>
    </body>
</html>
EOF
cat <<'EOF' >hls.html
<!DOCTYPE html>
<html lang="en">
    <head>
        <meta charset="UTF-8">
        <title>HLS Live Streaming</title>
        <link href="https://vjs.zencdn.net/7.5.5/video-js.css" rel="stylesheet">
        <script src="https://vjs.zencdn.net/7.5.5/video.js"></script>
    </head>
    <body>
        <h1>HLS Player</h1>
        <video id="player" class="video-js vjs-default-skin" width="720" controls preload="auto">
            <source src="/hls/test.m3u8" type="application/x-mpegURL" />
        </video>
        <script>
            var player = videojs('#player');
        </script>
        <div id="footer">
              <font size="2">footer</font>
        </div>
    </body>
</html>
EOF
cat <<'EOF' >rtmp.html
<!DOCTYPE html>
<html lang="en">
    <head>
        <meta charset="UTF-8">
        <title>RTMP Live Streaming</title>
        <title>Live Streaming</title>
        <link href="https://unpkg.com/video.js/dist/video-js.css" rel="stylesheet">
        <script src="https://unpkg.com/video.js/dist/video.js"></script>
        <script src="https://unpkg.com/videojs-flash/dist/videojs-flash.min.js"></script>
        <script src="https://unpkg.com/videojs-contrib-hls/dist/videojs-contrib-hls.js"></script>
    </head>
    <body>
        <h1>RTMP Player</h1>
        <video id="my_video_1" class="video-js vjs-default-skin" controls preload="auto" width="720" data-setup='{"techOrder": ["html5","flash"]}'>
            <source src="rtmp://127.0.0.1:1935/live/test" type="rtmp/mp4">
        </video>
        <div id="footer">
            <font size="2">footer</font>
        </div>
    </body>
</html>
EOF
cat <<'EOF' >rtmp_live_modules.module
# # add blow to /etc/nginx/modules.d
load_module modules/ngx_rtmp_module.so;
# # stream ssl -> rmtp -> rmtps
rtmp {
    server {
        listen 1935;
        chunk_size 4000;
        notify_method get;
        #rtmp://ip/live/streamname
        application live {
            live on;
            drop_idle_publisher 5s;
            record_path /var/www/flv;
            record_unique on;
            # exec_push ffmpeg -i rtmp://localhost:1935/live/$name -filter:v scale=-1:460 -c:a libfdk_aac -b:a 32k -c:v libx264 -b:v 128k -f flv /var/www/flv/$name.flv;
            # ffmpeg  -hide_banner -f video4linux2 -list_formats all -i /dev/video0
            # ffmpeg | cat > test.avi
            # ffmpeg -re -i demo.ts -acodec copy -f flv -method PUT http://localhost:9999/aaa
            # ffmpeg -f video4linux2 -i /dev/video0 -c:v libx264 -an -f flv rtmp://localhost:1935/live/mystream
            # ffmpeg -f video4linux2 -s 640x480 -i /dev/video0 -vf drawtext="fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf:text='%{localtime\:%T}':x=20:y=20:fontcolor=white" -vframes 1 $(date +%Y-%m-%d-%H-%M-%S).jpg
            # ffmpeg -framerate 5 -pattern_type glob -i '*.jpg' -c:v libx264 -r 30 -pix_fmt yuv420p out.mp4
            # ffmpeg -y -f alsa -i default -f v4l2 -i /dev/video0 -acodec aac -strict -2 -ac 1 -b:a 64k -vcodec libx264 -b:v 300k -r 30 -g 30 out.mp4
        }
        application hls {
            live on;
            hls on;
            hls_path /var/www/hls;
            hls_fragment 8s;
            on_publish http://localhost/auth;
            on_play http://localhost/auth;
            hls_cleanup off;
            # publish only from localhost
            # allow publish 127.0.0.1;
            # deny publish all;
            # allow play all;
        }
        application dash {
            live on;
            dash on;
            dash_path /var/www/dash;
        }
    }
}
EOF
cat <<'EOF' >http2.http
#curl -k --http2 https://localhost:8000 -vvv
#curl -k --http1.1 https://localhost:8000 -vvv
# # http2 must not be enabled on port 80 because it does not
# # work with HTTP 1.1, it returns binary data for a HTTP1.1 request
#curl --http2-prior-knowledge  http://localhost:8001
server {
    listen 8000 reuseport ssl http2;
    listen 8001 reuseport http2;
    server_name _;
    ssl_certificate /etc/nginx/ssl/test.pem;
    ssl_certificate_key /etc/nginx/ssl/test.key;
    ssl_trusted_certificate /etc/nginx/ssl/ca.pem;
    location / {
        return 200 "value=$http2";
        # proxy_http_version 1.1;
        # proxy_pass http://test.com/;
    }
}
EOF
cat <<'EOF' >rtmp_live.http
# stats: curl http://localhost/stat
# # HLS test:
# ffmpeg -re -stream_loop -1 -i demo.mp4 -c copy -f flv rtmp://localhost:1935/hls/demo
# mpv http://localhost/hls/demo.m3u8
# # MPEG DASH test:
# ffmpeg -re -i demo.mp4 -vcodec copy -acodec copy -f flv rtmp://localhost:1935/dash/demo
# mpv http://localhost/dash/demo.mpd
server {
    listen 80 reuseport;
    location /auth {
        if ($arg_pass = 'password') { return 200; }
        # DEMO:return HTTP HEADER User-Agent
        return 404 "$http_user_agent";
    }
    location /stat {
        rtmp_stat all;
        # Use this stylesheet to view XML as web page in browser
        rtmp_stat_stylesheet stat.xsl;
        allow 192.168.168.0/24;
        deny all;
    }
    # copy rtmp stat.xsl to /var/www
    location /stat.xsl {
        root /var/www;
    }
    location /hls {
        types{
            application/vnd.apple.mpegurl m3u8;
            video/mp2t ts;
        }
        alias /var/www/hls;
        expires -1;
        # Value -1 means these headers are set as:
        # Expires:  current time minus 1 second
        # Cache-Control: no-cache
        add_header Cache-Control no-cache always;
        add_header Access-Control-Allow-Origin *;
        add_header Access-Control-Allow-Headers "Origin, X-Requested-With, Content-Type, Accept";
        add_header Access-Control-Allow-Methods "GET, POST, OPTIONS";
    }
    location /dash {
        # Serve DASH fragments
        alias /var/www/dash;
        add_header Cache-Control no-cache;
    }
}
EOF
cat <<'EOF' >static_dynamic.http
map $http_user_agent $badagent {
    default    0;
    ~*backdoor 1;
    ~webbandit 1;
    ~*(?i)(80legs|360Spider) 1;
}
server {
    listen 80 reuseport;
    server_name _;
    if ($badagent) { return 403; }
    # serve static files
    # location ~* "^/[a-z0-9]{40}\.(css|js)$" {
    location ~ ^/(images|javascript|js|css|flash|media|static)/ {
        alias /var/www/;
        expires 30d;
    }
    # pass dynamic content
    location / {
        proxy_buffer_size 4k;
        proxy_limit_rate 20000; #bytes per second
        # proxy_pass_request_headers off;
        # proxy_pass_request_body off;
        proxy_pass http://127.0.0.1:8080;
    }
}
EOF
cat <<'EOF' >limit_speed.http
limit_speed_zone mylimitspeed $binary_remote_addr 10m;
server {
    listen 80 reuseport;
    server_name _;
    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }
    # # Disable hidden files
    location ~ /\. { deny all; }
    # # Cache static files
    location ~* .(ogg|ogv|svg|svgz|eot|otf|woff|mp4|ttf|css|rss|atom|js|jpg|jpeg|gif|png|ico|zip|tgz|gz|rar|bz2|doc|xls|exe|ppt|tar|mid|midi|wav|bmp|rtf)$ {
        expires max; log_not_found off; access_log off;
    }
    location / {
        limit_speed mylimitspeed 100k;
        # limit_rate_after 5m; #下载了5M以后开始限速
        # limit_rate 100k;
        root /var/www;
    }
}
EOF
cat <<'EOF' >redirect_all_except_localhost.http
server {
    listen 80 reuseport;
    server_name _;
    location / {
        error_page 403 = @badip;
        allow 127.0.0.1;
        deny all;
        alias /var/www;
    }
    location @badip {
        return 301 $scheme://example.com/some-page;
    }
}
EOF
cat <<'EOF' >valid_referer.http
# curl -vvv -e "https://a.abc.com" 127.0.0.1
server {
    listen 80 reuseport;
    server_name _;
    valid_referers none blocked server_names *.example.com ~\.abc\.;
    if ($invalid_referer) { return 403; }
    # location ~* \.(gif|jpg|jpeg|png)$ {
    #     valid_referers none blocked ~.google. ~.bing. ~.yahoo. ~.facebook. ~.fbcdn. ~.ask. server_names ~($host);
    #     if ($invalid_referer) { return 444; }
    # }
    location / { return 200; }
}
EOF
cat <<'EOF' >dummy.http
# catch-all not matched server_name by default_server
# If no default server is defined, Nginx will use the first found server.
server {
    listen 80 default_server reuseport;
    # listen 443 ssl http2 default_server reuseport;
    # ssl_certificate /etc/nginx/ssl/test.pem;
    # ssl_certificate_key /etc/nginx/ssl/test.key;
    server_name _;
    access_log /var/log/nginx/access_err_domain.log main buffer=512k flush=5m;
    return 444;
}
EOF
cat <<'EOF' >check_nofiles.ngx.sh
ps --ppid $(cat /var/run/nginx.pid) -o %p|sed '1d'|xargs -I{} cat /proc/{}/limits|grep open.files
EOF
cat <<'EOF' >redis.http
# redis-cli -x set curl/7.61.1 http://www.xxx.com
upstream redis {
    server 127.0.0.1:6379;
}
server {
    listen 80 reuseport;
    server_name _;
    location / {
        # cache !!!!
        set $redis_key $uri;
        set $redis_db 0;
        set $redis_auth PASSWORD;
        redis_pass     redis;
        default_type   text/html;
        error_page     404 = @fallback;
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
}
EOF
: <<'EOF'
# # 设置某个key的过期时间为120秒
# EXPIRE [KEY] 120
# # 重置某个KEY的过期时间
# PERSIST [KEY]
# # 查看某个KEY的过期时间
# TTL [KEY]
# # 从队列尾部插入数据
# RPUSH [Queue_Key] [value]
# # 从队列头部插入数据
# LPUSH [Queue_Key] [value]
# # 获取 队列的长度
# LLEN [Queue_Key]
# # LPOP 从队列头部出一个数据
# LPOP [Queue_Key]
# # RPOP 从队列尾部出一个数据
# RPOP [Queue_Key]
server {
    listen 80 reuseport;
    server_name _;
    # GET /get?key=key
    location = /get {
        set_unescape_uri $key $arg_key;  # this requires ngx_set_misc
        redis2_query get $key;
        redis2_pass 127.0.0.1:6379;
    }
    # GET /set?key=one&val=first%20value
    location = /set {
        set_unescape_uri $key $arg_key;  # this requires ngx_set_misc
        set_unescape_uri $val $arg_val;  # this requires ngx_set_misc
        redis2_query set $key $val;
        redis2_pass 127.0.0.1:6379;
    }
    location = /counter {
        internal;
        redis2_query select 5;
        redis2_query incr count;
        redis2_pass 127.0.0.1:6379;
    }
}
EOF
cat <<'EOF' >traffic_status.http
# /{status_uri}/control?cmd=*`{command}`*&group=*`{group}`*&zone=*`{name}`*
# /control?cmd=reset&group=server&zone=*

# geoip_country                   /usr/share/GeoIP/GeoIP.dat;
vhost_traffic_status_zone;
# vhost_traffic_status_filter_by_set_key $geoip_country_code country::*;
server {
    listen 80 reuseport;
    server_name _;
    # listen 443 ssl reuseport;
    # ssl_certificate /etc/nginx/SSL/ca.pem
    # ssl_certificate_key /etc/nginx/SSL/site.key;
    # server_name status.example.org;
    # # force https
    # proxy_redirect http:// $scheme://;
    # if ($scheme = http ) {
    #     return 301 https://$server_name$request_uri;
    # }

    location / {
        access_log off;
        proxy_cache off;
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
cat <<'EOF' > flv_movie.http
# flv mp4流媒体服务器, https://github.com/Bilibili/flv.js
# apt -y install yamdi
server {
    listen 80 reuseport;
    server_name _;
    root /var/www/flv/;
    limit_rate_after 5m; #在flv视频文件下载了5M以后开始限速
    limit_rate 100k;     #速度限制为100K
    index index.html;
    location ~ \.flv {
        flv;
    }
}
EOF
cat <<'EOF' > limit_conn.http
limit_conn_zone $binary_remote_addr zone=connperip:10m;
limit_conn_zone $server_name zone=connperserver:10m;
server {
    listen 80 reuseport;
    server_name _;
    location / {
        limit_conn connperip 10;
        limit_conn connperserver 100;
        # limit_conn_log_level info;
        # limit_conn_status 501;
    }
}
EOF
cat <<'EOF' > limit_req_ddos.conf
# copy this file to /etc/nginx/http-conf.d/
# IP addresses (in the 192168.0.0/24 subnets) are not limited.
# All other IP addresses are limited
geo $limit{
    default 1;
    192.168.0.0/24 0;
}
map $limit $limit_key {
    0 "";
    1 $binary_remote_addr;
}
map $http_x_forwarded_for $clientRealIp {
    ""                              $limit_key;
    ~^(?P<firstAddr>[0-9\.]+),?.*$  $firstAddr;
}

# # 1m zone takes 16000 IP addresses
# limit single IP 50 concurrent control,
limit_conn_zone $clientRealIp zone=PerClientIPConnZone:10m ;
limit_conn PerClientIPConnZone 50;
limit_conn_status 503;
limit_conn_log_level warn;

# limit single IP/s 20 Request, with bursts not exceeding 50 requests.
limit_req_zone $clientRealIp zone=PerClientIPReqZone:10m rate=20r/s;
limit_req zone=PerClientIPReqZone burst=50 nodelay;
limit_req_status 503;
limit_req_log_level warn;

limit_conn_zone $server_name zone=PerSrvNameConnZone:10m;
limit_conn PerSrvNameConnZone 800;
limit_req_zone $server_name zone=PerSrvNameReqZone:10m rate=1000r/s;
limit_req zone=PerSrvNameReqZone burst=2000 nodelay;
EOF
cat <<'EOF' > limit_req.http
# error_log /var/log/nginx/error.log warn;
# limit_req_log_level warn;
limit_req_zone $binary_remote_addr zone=perip:10m rate=1r/s;
# limit_req_zone $server_name zone=perserver:10m rate=600r/m;
server {
    listen 80 reuseport;
    server_name _;
    # limit_req zone=perserver burst=10;
    location / {
        limit_req zone=perip burst=5;
    }
}
EOF
cat <<'EOF' > fcgiwrap.http
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
    listen 80 reuseport;
    server_name _;
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
cat <<'EOF' > auth_or_allow.http
server {
    listen 80 reuseport;
    server_name _;
    location / {
        satisfy any;
        # Allows access if all (all)
        # or at least one (any) of the
        # ngx_http_access_module, ngx_http_auth_basic_module,
        # ngx_http_auth_request_module, ngx_http_auth_jwt_module modules allow access.
        allow 192.168.1.0/32;
        deny  all;
        auth_basic "Restricted Content";
        auth_basic_user_file /etc/nginx/.htpasswd;
    }
}
EOF
cat <<'EOF' > auth_basic.http
server {
    listen 80 reuseport;
    server_name _;
    # username=user
    # password=password
    # printf "${username}:$(openssl passwd -apr1 ${password})\n" >> /etc/nginx/.htpasswd
    location / {
        auth_basic "Restricted Content";
        auth_basic_user_file /etc/nginx/.htpasswd;
    }
}
EOF
cat <<'EOF' > url_map.http
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
    listen 80 reuseport;
    server_name _;
    if ($url_p) {
        # if '$url_p' variable is not an empty string
        return 301 $url_p;
    }
    location / {
        disable_symlinks off;
        root /var/www;
    }
}
EOF
cat <<'EOF' > secure_link_demo.js
export default {gen_url};
function gen_url(r) {
    var SECRET_KEY = 'prekey';
    var uri = r.args['uri'];
    var secs = r.args['secs'];
    var d = new Date().valueOf();
    var epoch = Math.floor(d / 1000);
    // const expires = String(Math.round(expiresTimestamp / 1000));
    var secure_link_expires = epoch + secs;
    try {
    var key = require('crypto').createHash('md5')
        .update(SECRET_KEY).update(secure_link_expires).update(uri)
        .digest('base64url');
     } catch (err) {
        r.return(200, JSON.stringify({e:err.message}));
        return;
     }
    //r.return(302, `${uri}?k=${key}&e=${secure_link_expires}`);
    r.return(200, `${uri}?k=${key}&e=${secure_link_expires}`);
}
EOF
cat <<'EOF' > secure_link_demo.http
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
#         write_header 403
#         return
#     }
#     eval $QUERY_STRING
#     local secure_link_expires=$(date -d "+${sec} second" +%s)
#     # RFC 4648 compliant, re-entrant, base64url codec
#     local key=$(echo -n "${mykey}${secure_link_expires}${uri}" | /usr/bin/openssl md5 -binary | /usr/bin/openssl base64 | /usr/bin/tr '+ /' '-_' | /usr/bin/tr -d =)
#     printf "Location: ${uri}?k=${key}&e=${secure_link_expires}\n"
#     write_header 302
# }
# case "$REQUEST_METHOD" in
#     GET)   do_get;;
#     POST)  do_post;;
#     *)     write_header 405;;
# esac
js_import secure from js/secure_link_demo.js;
server {
    listen 80 reuseport;
    server_name _;
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
    #curl "http://127.0.0.1/?uri=/validate/stat.js.gz&secs=1000"
    location / {
        js_content secure.gen_url;
    }
}
EOF
cat <<'EOF' > secure_link.java
import java.io.IOException;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
//Java8+
//import java.util.Base64;
//Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
public class test
{
    public static void main(String[] args) throws IOException, NoSuchAlgorithmException {
        long ts = System.currentTimeMillis()/1000;
        ts = ts+3600;
        String value="prekey"+ts+"/myfile.txtGET";
        MessageDigest md = MessageDigest.getInstance("MD5");
        md.update(value.getBytes());
        byte[] digest = md.digest();
        System.out.println(java.util.Base64.getUrlEncoder().withoutPadding().encodeToString(digest));
    }
}
EOF
cat <<'EOF' > secure_link.http
map $uri $allow_file {
    default                none;
    "~*/s/(?<name>.*).txt" $name;
    "~*/s/(?<name>.*).mp4" $name;
}
# mkdir -p /var/www/secure/hls/ && echo "HLS FILE" > /var/www/secure/hls/file.txt
# mkdir -p /var/www/files/ && echo "FILES FILE" > /var/www/files/file.txt
# mkdir -p /var/www/s/ && echo "S FILE" > /var/www/s/file.txt
server {
    listen 80 reuseport;
    server_name _;
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
cat <<'EOF' > secure_link_cookie.http
server {
    listen 80 reuseport;
    server_name _;
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
cat <<'EOF' > upload.html
<html><head></head><body>
<input id="files" type="file" />
</body></html>
<script>
document.getElementById('files').addEventListener('change', function(e) {
    var file = this.files[0];
    var xhr = new XMLHttpRequest();
    if (! (crypto.randomUUID instanceof Function)) {
        crypto.randomUUID = function uuidv4() {
            return ([1e7]+-1e3+-4e3+-8e3+-1e11).replace(/[018]/g, c =>
                (c ^ crypto.getRandomValues(new Uint8Array(1))[0] & 15 >> c / 4).toString(16)
            );
        }
    }
    (xhr.upload || xhr).addEventListener('progress', function(e) {
        var done = e.position || e.loaded
        var total = e.totalSize || e.total;
        console.log('xhr progress: ' + Math.round(done/total*100) + '%');
    });
    xhr.addEventListener('load', function(e) {
        console.log('xhr upload complete', e, this.responseText);
    });
    xhr.open('put', '/upload/'+ crypto.randomUUID(), true);
    xhr.send(file);
});
</script>
EOF
cat <<'EOF' > webdav.http
server {
    listen 80 reuseport;
    server_name _;
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
    # request_method=GET/PUT/DELETE
    # uri=/store/file.txt
    # secure_link_md5="$mykey$secure_link_expires$uri$request_method"
    # echo -n "${secure_link_md5}" | openssl md5 -binary | openssl base64 | tr +/ -_ | tr -d =
    # curl --upload-file bigfile.iso "http://${srv}${uri}?k=XXXXXXXXXXXXXX&e=${secure_link_expires}"
    # curl http://${srv}${uri}?k=XXXXXXXXXXXXXX&e=${secure_link_expires}
    # location ~* /documents/(.*) { set $key $1; }
    # location ~ ^/(?<port>123[0-9])(?:/|$) { rewrite "^/\d{4}(?:/(.*))?" /$1 break; proxy_pass http://127.0.0.1:$port; }
    location /store {
        set $mykey prekey;
        if ($request_method !~ ^(PUT|GET|DELETE)$ ) {
            return 444 "444 METHOD(PUT/GET/DELETE)";
        }
        if ($request_method = GET) {
            set $mykey getkey;
        }
        # chown nginx.nginx /var/www -R
        autoindex on;
        autoindex_format json; #xml
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
cat <<'EOF' > stream_dns_proxy.stream
# copy this file to /etc/nginx/stream-enabled/
upstream dns_upstreams {
    server 172.16.0.11:53;
}
server {
    listen 53 udp reuseport;
    proxy_responses 1;
    proxy_timeout 1s;
    proxy_pass dns_upstreams;
}
EOF
cat <<'EOF' > https_proxy.http
# load_module modules/ngx_http_proxy_connect_module.so;
# curl -vvv -x http://localhost:8000 http://192.168.168.1:9999/img/bd_logo1.png -o /dev/null
# dynamic proxy_pass + proxy_cache possible · Issue #316 ...
# https://github.com/nginx/njs/issues/316
server {
    listen 8000 reuseport;
    server_name _;
    resolver 114.114.114.114 ipv6=off;
    # Enable "CONNECT" HTTP method support.
    proxy_connect;
    proxy_connect_connect_timeout 10s;
    proxy_connect_read_timeout 10s;
    proxy_connect_send_timeout 10s;
    # all / port-range
    proxy_connect_allow 443 563;
    # proxy_connect_address <addr> | off
    # forward proxy for non-CONNECT request
    location / {
        proxy_pass $scheme://$http_host;
        proxy_set_header Host $http_host;
        proxy_buffers 256 4k;
        proxy_max_temp_file_size 0k;
    }
}
EOF
cat <<'EOF' > reverse_transparent_proxy.http
# modify nginx.conf add `user root;`
# upstream `route add default gw 172.16.0.1`
# ip rule add fwmark 1 lookup 100
# ip route add local 0.0.0.0/0 dev lo table 100
# iptables -t mangle -A PREROUTING -p tcp -s 172.16.1.0/24 --sport 80 -j MARK --set-xmark 0x1/0xffffffff
server {
    listen 172.16.0.1:80 reuseport;
    server_name _;
    location / {
        proxy_bind $remote_addr transparent;
        proxy_pass http://172.16.0.11:80;
    }
}
EOF
cat <<'EOF' > gateway_transparent_proxy.http
# iptables -t nat -A PREROUTING -p tcp -m tcp --dport 80 -j DNAT --to-destination ${gate_ip}:${gate_port}
server {
    listen 8000 reuseport;
    server_name _;
    resolver 114.114.114.114 ipv6=off;
    location / {
        # proxy_method      POST;
        # proxy_set_body    "token=$http_apikey&token_hint=access_token";
        proxy_pass $scheme://$host$request_uri;
        proxy_set_header Host $http_host;
        # $http_host equals always the HTTP_HOST request header.
        # $host equals $http_host, lowercase and without the port number (if present),
        #    except when HTTP_HOST is absent or is an empty value.
        #    In that case, $host equals the value of the server_name directive
        #    of the server which processed the request.
        proxy_buffers 256 4k;
        proxy_max_temp_file_size 0k;
    }
}
EOF
cat <<'EOF' > mirror.http
# nc -klp9999
server {
    listen 80 reuseport;
    server_name _;
    location / {
        mirror @mirror;
        # whether the client request body is mirrored
        mirror_request_body off;
        alias /var/www/;
    }
    location = @mirror {
        internal;
        proxy_pass http://127.0.0.1:9999$request_uri;
        # whether the original request body is passed to the proxied server
        proxy_pass_request_body off;
        proxy_set_header Content-Length "";
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
EOF
cat <<'EOF' > mirror2.http
# when mirror slow, orig server slow too!!
# nc -klp9999
split_clients "${remote_addr}AAA" $mirror_allowed {
    30% 1;
    * "";
}
server {
    listen 80 reuseport;
    server_name _;
    location / {
        mirror @mirror;
        # whether the client request body is mirrored
        mirror_request_body off;
        alias /var/www/;
    }
    location = @mirror {
        internal;
        if ($mirror_allowed = "") { return 200; }
        proxy_pass http://127.0.0.1:9999$request_uri;
        # whether the original request body is passed to the proxied server
        proxy_pass_request_body off;
        proxy_set_header Content-Length "";
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
EOF
cat <<'EOF' > memory_cached.http
server {
    listen 80 reuseport;
    server_name _;
    location / {
        set $memcached_key "$uri?$args";
        # set $memcached_key $request_uri;
        # default_type text/html;
        memcached_next_upstream  not_found;
        memcached_pass 127.0.0.1:11211;
        error_page 404 502 504 = @fallback;
    }
    location @fallback {
        return 200 "@fallback 404 502 504";
        #proxy_pass http://backend;
    }
}
EOF
cat <<'EOF' > ab_test.http
upstream a {
    server 127.0.0.1:3001;
}
upstream b {
    server 127.0.0.1:4001;
}
server {
    listen 3001 reuseport;
    server_name _;
    location / {
        return 200 "Served from site A! \n\n";
    }
}
server {
    listen 4001 reuseport;
    server_name _;
    location / {
        return 200 "Served from site B!! <<<<-------------------------- \n\n";
    }
}
split_clients "${arg_token}" $dynamic {
    95%     a;
    *       b;
}
server {
    listen 80 reuseport;
    server_name _;
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
cat <<'EOF' > split_client.http
server {
    listen 8098 reuseport;
    server_name _;
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
    listen 80 reuseport;
    server_name _;
    location / {
        proxy_pass http://backend;
        proxy_bind $split_ip;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
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
cat <<'EOF' > split_client.http
split_clients "${remote_addr}" $variant {
    0.5%     .one;
    2.0%     .two;
    *    "";
}
server {
    listen 80 reuseport;
    server_name _;
    location / {
        index index${variant}.html;
        root /var/www;
    }
}
EOF
cat <<'EOF' > auth_request_by_secure_link.http
# ldap demo: https://github.com/nginxinc/nginx-ldap-auth
server {
    listen 80 reuseport;
    server_name _;
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
cat <<'EOF' > auth_request.http
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
    listen 80 reuseport;
    server_name _;
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
cat <<'EOF' > aws_s3_list.xslt
<?xml version="1.0"?>
<xsl:stylesheet version="1.1" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
    <xsl:output method="html" encoding="utf-8" indent="yes"/>
    <xsl:template match="/">
        <xsl:choose>
            <xsl:when test="//*[local-name()='Contents'] or //*[local-name()='CommonPrefixes']">
                <xsl:apply-templates select="*[local-name()='ListBucketResult']" />
            </xsl:when>
            <xsl:otherwise>
                <xsl:call-template name="no_contents"/>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:template>
    <xsl:template name="no_contents">
        <html>
            <head><title>Not Found</title></head>
            <body>
                <h1>Not Found</h1>
            </body>
        </html>
    </xsl:template>
    <xsl:template match="*[local-name()='ListBucketResult']">
        <xsl:text disable-output-escaping='yes'>&lt;!DOCTYPE html&gt;</xsl:text>
        <xsl:variable name="globalPrefix" select="*[local-name()='Prefix']/text()"/>
        <html>
            <head><title><xsl:value-of select="$globalPrefix"/></title></head>
            <body>
                <h1>Index of /<xsl:value-of select="$globalPrefix"/></h1>
                <hr/>
                <table id="list">
                    <thead>
                        <tr>
                            <th style="text-align: left; width:55%">Filename</th>
                            <th style="text-align: left; width:20%">File Size</th>
                            <th style="text-align: left; width:25%">Date</th>
                        </tr>
                    </thead>
                    <tbody>
                        <xsl:if test="string-length($globalPrefix) > 0">
                            <tr>
                                <td>
                                    <a href="../">..</a>
                                </td>
                            </tr>
                        </xsl:if>
                        <xsl:apply-templates select="*[local-name()='CommonPrefixes']">
                            <xsl:with-param name="globalPrefix" select="$globalPrefix"/>
                        </xsl:apply-templates>
                        <xsl:apply-templates select="*[local-name()='Contents']">
                            <xsl:with-param name="globalPrefix" select="$globalPrefix"/>
                        </xsl:apply-templates>
                    </tbody>
                </table>
            </body>
        </html>
    </xsl:template>
    <xsl:template match="*[local-name()='CommonPrefixes']">
        <xsl:param name="globalPrefix"/>
        <xsl:apply-templates select=".//*[local-name()='Prefix']">
            <xsl:with-param name="globalPrefix" select="$globalPrefix"/>
        </xsl:apply-templates>
    </xsl:template>
    <xsl:template match="*[local-name()='Prefix']">
        <xsl:param name="globalPrefix"/>
        <xsl:if test="not(text()=$globalPrefix)">
            <xsl:variable name="dirName" select="substring-after(text(), $globalPrefix)"/>
            <tr>
                <td>
                    <a href="/{text()}">
                        <xsl:value-of select="$dirName"/>
                    </a>
                </td>
                <td/>
                <td/>
            </tr>
        </xsl:if>
    </xsl:template>
    <xsl:template match="*[local-name()='Contents']">
        <xsl:param name="globalPrefix"/>
        <xsl:variable name="key" select="*[local-name()='Key']/text()"/>
        <xsl:if test="not($key=$globalPrefix)">
            <xsl:variable name="fileName" select="substring-after($key, $globalPrefix)"/>
            <xsl:variable name="date" select="*[local-name()='LastModified']/text()"/>
            <xsl:variable name="size" select="*[local-name()='Size']/text()"/>
            <tr>
                <td>
                    <a href="/{$key}">
                        <xsl:value-of select="$fileName"/>
                    </a>
                </td>
                <td>
                    <xsl:value-of select="$size"/>
                </td>
                <td>
                    <xsl:value-of select="$date"/>
                </td>
            </tr>
        </xsl:if>
    </xsl:template>
</xsl:stylesheet>
EOF
cat <<'EOF' > aws_s3auth.http
# njs s3: git clone https://github.com/nginxinc/nginx-s3-gateway.git
# public-bucket MUST set bucket-policy.py to all read/write
# curl http://127.0.0.1:81/public-bucket OUTPUT html by xslt module
upstream ceph_rgw_backend {
    server 192.168.168.131:80;
    server 192.168.168.132:80;
    server 192.168.168.133:80;
    keepalive 64;
}
server {
    listen 81 reuseport;
    server_name _;
    client_max_body_size 6000M;
    location / {
        proxy_redirect off;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_hide_header x-amz-request-id;
        proxy_hide_header x-rgw-object-type;
        # # header_more module remove x-amz-request-id
        # more_clear_headers 'x-amz*';
        # #Stops the local disk from being written to (just forwards data through)
        # proxy_max_temp_file_size 0;
        # Apply XSL transformation to the XML returned from S3 directory listing
        xslt_stylesheet /etc/nginx/http-available/aws_s3_list.xslt;
        xslt_types application/xml;
        proxy_pass http://ceph_rgw_backend;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
    }
}
server {
    listen 80 reuseport;
    server_name _;
    # srv=192.168.168.1
    # mykey=prekey
    # sec=3600
    # secure_link_expires=$(date -d "+${sec} second" +%s)
    # request_method=GET/PUT/DELETE
    # uri=/file.txt
    # secure_link_md5="$mykey$secure_link_expires$uri$request_method"
    # keys=$(echo -n "${secure_link_md5}" | openssl md5 -binary | openssl base64 | tr +/ -_ | tr -d =)
    # curl --upload-file bigfile.iso "http://${srv}${uri}?k=${keys}&e=${secure_link_expires}"
    # curl curl -X PUT http://localhost:8080/hello.txt -d 'Hello there!'
    # curl "http://${srv}${uri}?k=${keys}&e=${secure_link_expires}"
    location / {
        set $mykey prekey;
        if ($request_method !~ ^(PUT|GET|DELETE)$ ) { return 444 "444 METHOD(PUT/GET/DELETE)"; }
        if ($request_method = GET) { set $mykey getkey; }
        secure_link $arg_k,$arg_e;
        secure_link_md5 "$mykey$secure_link_expires$uri$request_method";
        if ($secure_link = "") { return 403; }
        if ($secure_link = "0") { return 410; }
        client_max_body_size 2048m;
        proxy_max_temp_file_size 0;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_pass http://ceph_rgw_backend/public-bucket$uri;
    }
}
EOF
cat <<'EOF' >x_accel_redirect2.http
server {
    listen 127.0.0.1:81 reuseport;
    server_name _;
    location / {
        # # you application here, if request valid add X-Accel-Redirect header!!!
        add_header X-Accel-Redirect "/internal_redirect/https://www.baidu.com$request_uri" always;
        return 200;
    }
}
limit_conn_zone $binary_remote_addr zone=addr:10m;
server {
    listen 80 reuseport;
    server_name _;
    location / {
        proxy_pass http://127.0.0.1:81;
    }
    # location ~* ^/internal_redirect/(.*?)/(.*) {
    location ~* ^/internal_redirect/(http|https):\/\/(.*?)/(.*) {
        internal;
        # Extract download url from the request
        set $download_uri $3;
        set $download_host $2;
        set $download_proto $1;
        # Extract the arguments from request.
        # That is the Signed URL part that you require to get the file from S3 servers
        if ($download_uri ~* "([^/]*$)" ) {
            set $filename $1;
        }
        # Compose download url
        set $download_url $download_proto://$download_host/$download_uri$is_args$args;
        # # Set download request headers
        # proxy_hide_header x-amz-id-2;
        # proxy_hide_header x-amz-request-id;
        # proxy_hide_header Set-Cookie;
        # proxy_ignore_headers Set-Cookie;
        # proxy_hide_header Content-Disposition;
        # add_header Content-Disposition 'attachment; filename="$filename"';
        # Activate the proxy buffering, without it limiting bandwidth speed in proxy will not work!
        proxy_buffering on;
        # Buffer 512 KB data
        proxy_buffers 32 16k;
        # Do not touch local disks when proxying content to clients
        proxy_max_temp_file_size 0;
        # Limit the connection to one per IP address
        limit_conn addr 1;
        # Limit the bandwidth to 300k
        proxy_limit_rate 300k;
        limit_conn_log_level info;
        proxy_set_header Host $download_host;
        # return 200 "$download_url $download_host";
        resolver 114.114.114.114 ipv6=off;
        resolver_timeout 5s;
        proxy_pass $download_url;
    }
}
EOF
cat <<'EOF' > post_redirect.http
server {
    listen 80 reuseport;
    server_name _;
    location / {
        # HTTP 307 only for POST requests:
        if ($request_method = POST) {
            return 307 https://api.example.com?request_uri;
        }
        # keep for non-POST requests:
        rewrite ^ https://api.example.com?request_uri permanent;
        client_max_body_size 10m;
    }
}
EOF
cat <<'EOF' > x_accel_redirect.http
# # X-accel allows for internal redirection to a location determined
# # by a header returned from a backend.
# echo "protected res" > /var/www/file.txt
# curl -vvv http://127.0.0.1/file.txt
server {
    listen 81 reuseport;
    server_name _;
    location / {
        # add_header X-Accel-Redirect "/protected$uri" always;
        add_header X-Accel-Redirect "/public-bucket$uri" always;
        add_header X-Accel-Buffering yes;
        # speed limit Byte/s
        add_header X-Accel-Limit-Rate 102400;
        # single download only
        add_header Accept-Ranges none;
        return 200;
    }
}
upstream ceph_rgw_backend {
    server 192.168.168.132;
    keepalive 64;
}
server {
    listen 80 reuseport;
    server_name _;
    location /protected {
        internal;
        alias /var/www;
    }
    location /public-bucket {
        internal;
        client_max_body_size 10000m;
        proxy_method $m;
        proxy_pass http://ceph_rgw_backend$uri;
    }
    location / {
        set $m $request_method;
        proxy_method GET;
        proxy_pass_request_body off; # no data is being transferred
        proxy_set_header Content-Length '0';
        # # Hidden / Pass X-Powered-By to client
        # proxy_hide_header X-Powered-By;
        # proxy_pass_header X-Powered-By;
        # #Disables processing of certain response header fields from the proxied server.
        # proxy_ignore_headers Cache-Control Expires Set-Cookie Vary;
        proxy_pass http://127.0.0.1:81/;
    }
}
EOF
cat <<'EOF' > js_test.http
# curl http://127.0.0.1/sum?asdbas=asdfads
# curl http://127.0.0.1/?url=www.baidu.com
# curl http://127.0.0.1/sub
# curl http://127.0.0.1/json
js_import test from js/js_test.js;
js_set $summary summary;
server {
    listen 80 reuseport;
    server_name _;
    resolver 8.8.8.8;
    resolver_timeout 5s;
    subrequest_output_buffer_size 20k;
    location / {
        js_content test.fetch_url;
    }
    location /sub {
        js_content test.sub;
    }
    location /task {
        internal;
        return 200 "http://www.xxx.com/abc/de";
    }
    location /sum {
        return 200 $summary;
    }
    location /json {
        js_content test.file;
    }
}
EOF
cat <<'EOF' > js_test.js
export default {file, get_env, fetch_url, summary, sub};
var fs = require('fs').promises;
function file(r) {
    fs.readFile("/etc/nginx/a.json").then((json) => {
        r.return(200, json);
    });
}
//////////////////////////
// env MYKEY;
// js_set $mykey get_env;
function get_env(r) {
    return process.env.MYKEY;
}
//////////////////////////
function fetch_url(r) {
    ngx.fetch(`http://${r.args.url}`)
        .then(reply => reply.text())
        .then(body => {
            r.headersOut['Content-Type'] = "text/html; charset=utf-8";
            r.return(200, body);
        })
        .catch(e => r.return(501, e.message));
}
function summary(r) {
    var a, s, h
    s = "JS summary\n\n"
    s += "Method: " + r.method + "\n"
    s += "HTTP version: " + r.httpVersion + "\n"
    s += "Host: " + r.headersIn.host + "\n"
    s += "Remote Address: " + r.remoteAddress + "\n"
    s += "URI: " + r.uri + "\n"
    s += "Headers:\n"
    for (h in r.headersIn) {
        s += "  header '" + h + "' is '" + r.headersIn[h] + "'\n"
    }
    s += "Args:\n"
    for (a in r.args) {
        s += "  arg '" + a + "' is '" + r.args[a] + "'\n"
    }
    s += r.requestBody
    return s
}
function baz(r) {
    r.status = 200
    r.headersOut.foo = 1234
    r.headersOut['Content-Type'] = "text/plain charset=utf-8"
    r.headersOut['Content-Length'] = 16
    r.sendHeader()
    r.send("nginx ")
    r.send("javascript")
    r.finish()
}
function sub(r) {
    r.subrequest(
        '/task', {
            method: 'GET',
        },
        function(res) {
            if (res.status != 200) {
                r.return(res.status);
                return;
            }
            r.error(res.responseBody)
            r.return(200, JSON.stringify({
                njsModuleVersion: njs.version,
                nginxVersion: r.variables.nginx_version
            }));
            //r.return(200, res.responseBody);
            // r.return(302, res.responseBody);
        }
    )
}
EOF
cat <<'EOF' >shorturl.http
# https://nginx.org/en/docs/njs/reference.html
# http_js_module & http_redis_module
# redis-cli -x set /abcdefg http://www.xxx.com [EX seconds]
# curl http://127.0.0.1/abcdefg -redirect-> www.xxx.com
js_import short from js/shorturl.js;
server {
    listen 80 reuseport;
    server_name _;
    subrequest_output_buffer_size 20k;
    location / {
        js_content short.shorturl;
    }
    location /redis {
        internal;
        set $redis_key "$arg_key";
        redis_pass 127.0.0.1:6379;
    }
}
EOF
cat <<'EOF' >shorturl.js
export default {shorturl};
function shorturl(r) {
    r.subrequest(
        '/redis', {
            method: 'GET',
            args: `key=${r.uri}`,
        },
        function(res) {
            if (res.status != 200) {
                r.return(res.status);
                return;
            }
            r.return(302, res.responseBody);
        }
    )
}
EOF
cat <<'EOF' >download_code.js
export default {check};
function check(r) {
    r.subrequest(
        '/redis', {
            method: 'GET',
            args: `key=${r.uri}`,
        },
        function(res) {
            if (res.status != 200) {
                r.headersOut['Content-Type'] = "text/html; charset=utf-8";
                r.return(res.status);
                return;
            }
            if (res.responseBody != r.variables.arg_code) {
                r.headersOut['Content-Type'] = "text/html; charset=utf-8";
                r.return(403, "code error");
                return;
            }
            r.internalRedirect('/download' + r.uri);
        }
    )
}
EOF
cat <<'EOF' >download_code.http
# http_js_module & http_redis_module
# redis-cli -x set /public-bucket/fu 9901 [EX seconds]
# curl http://127.0.0.1/public-bucket/fu?code=xxxx
upstream ceph_rgw_backend {
    server 192.168.168.131:80;
    keepalive 64;
}
js_path "/etc/nginx/js/";
js_import download from download_code.js;
server {
    listen 80 reuseport;
    server_name _;
    subrequest_output_buffer_size 20k;
    location = /favicon.ico { access_log off; log_not_found off; return 204; }
    location / {
        error_page 403 = @error403;
        if ($uri = '/') { return 200 "message"; }
        if ($arg_code = '') {
            add_header 'Content-Type' 'text/html charset=UTF-8';
            return 200 '<html><head></head><body>
<form method="GET" action="">
<input type="text" name="code" />
<button type="submit">Download</button>
</form>
</body></html>';
        }
        js_content download.check;
    }
    location /redis {
        internal;
        set $redis_db 0;
        set $redis_auth PASSWORD;
        set $redis_key "$arg_key";
        redis_pass 127.0.0.1:6379;
    }
    location ~ /download/(.*) {
        internal;
        proxy_redirect off;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_hide_header x-amz-request-id;
        proxy_hide_header x-rgw-object-type;
        proxy_pass http://ceph_rgw_backend/$1;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
    }
}
EOF
cat <<'EOF' > secure_link_hash.js
export default {secret_key, create_secure_link};
function secret_key(r) {
    return process.env.SECRET_KEY;
}
function create_secure_link(r) {
    return require('crypto').createHash('md5')
                            .update(r.uri).update(process.env.SECRET_KEY)
                            .digest('base64url');
}
EOF
cat <<'EOF' > secure_link_hash.http
# mkdir -p /etc/nginx/njs/
# cp secure_link_hash.js /etc/nginx/njs/
# sed -i "/env\s*SECRET_KEY/d" /etc/nginx/nginx.conf
# echo "env SECRET_KEY;" >> /etc/nginx/nginx.conf
js_import main from js/secure_link_hash.js;
js_set $new_foo main.create_secure_link;
js_set $secret_key main.secret_key;
server {
    listen 80 reuseport;
    server_name _;
    location /secure/ {
        error_page 403 = @login;
        secure_link $cookie_foo;
        secure_link_md5 "$uri$secret_key";
        if ($secure_link = "") { return 403; }
        #if ($secure_link = "0") { return 410; }
        return 200 "PASSED";
    }
    location @login {
        add_header Set-Cookie "foo=$new_foo; Max-Age=60";
        return 302 $request_uri;
    }
}
EOF
cat <<'EOF' > single_page.http
# send all requests to a single html page
# echo "base.html" > /var/www/base.html
server {
    listen 80 reuseport;
    server_name _;
    location / {
        root /var/www;
        try_files /base.html =404;
    }
}
EOF
cat <<'EOF' > serve_static_rest_backend.http
# serve all existing static files, proxy the rest to a backend
server {
    listen 80 reuseport;
    server_name _;
    location / {
        root /var/www/;
        try_files $uri $uri/ @backend;
        expires max;
        access_log off;
    }
    location ~ /\.git {
      deny all;
    }
    location @backend {
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_pass http://127.0.0.1:8080;
    }
}
EOF
cat <<'EOF' > resolver.http
server {
    listen 80 reuseport;
    server_name _;
    location ~ /to/(.*) {
        resolver 127.0.0.1;
        proxy_set_header Host $1;
        proxy_pass http://$1;
    }
    location /proxy {
        resolver 127.0.0.1 ipv6=off;
        # use proxy_pass with variables and the resolver directive to force nginx to resolve names at run-time;
        set $target http://proxytarget.example.com;
        proxy_pass $target;
    }
    location /proxypass {
        # echo "www.test.com 192.168.168.1" > dnsd.conf
        # busybox dnsd -c dnsd.conf -v -s
        resolver 127.0.0.1 ipv6=off;
        set $target http://www.test.com:9999;
        proxy_pass $target;
    }
}
EOF
cat <<'EOF' > redirect_to_cdn.http
split_clients $remote_addr $cdn_host {
    33% cdn1;
    33% cdn2;
    * cdn3;
}
server {
    listen 80 reuseport;
    server_name www.test.com;
    location /images/ {
        rewrite ^ http://$cdn_host.test.com$request_uri? permanent;
    }
}
EOF
cat <<'EOF' > cdn.http
proxy_cache_path /usr/share/nginx/cdn.test.com levels=1:2 keys_zone=testcdn:50m inactive=30m max_size=50m use_temp_path=off;
server {
    listen 80 reuseport;
    server_name cdn.test.com;
    location / {
        proxy_set_header Accept-Encoding "";
        proxy_pass https://www.test.com;
        proxy_redirect off;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_cache testcdn;
        proxy_cache_valid 200 304 30m;
        proxy_cache_valid 301 24h;
        proxy_cache_valid 500 502 503 504 0s;
        proxy_cache_valid any 1s;
        proxy_cache_min_uses 1;
        expires 12h;
    }
}
EOF
cat <<'EOF' > reverse_proxy_cache_split.http
proxy_cache_path /usr/share/nginx/cache1 levels=1:2 keys_zone=my_cache_hdd1:10m max_size=10g inactive=60m use_temp_path=off;
proxy_cache_path /usr/share/nginx/cache2 levels=1:2 keys_zone=my_cache_hdd2:10m max_size=10g inactive=60m use_temp_path=off;
split_clients $request_uri $my_cache {
    50% "my_cache_hdd1";
    50% "my_cache_hdd2";
}
server {
    listen 80 reuseport;
    server_name _;
    location / {
        proxy_cache $my_cache;
        proxy_ignore_headers Cache-Control;
        # Make sure your backend does not return Set-Cookie header.
        # If Nginx sees it, it disables caching.
        # http://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_ignore_headers
        proxy_ignore_headers "Set-Cookie";
        proxy_hide_header "Set-Cookie";

        proxy_cache_valid any 30m;
        proxy_cache_methods GET HEAD POST;
        # proxy_cache_bypass $cookie_nocache $arg_nocache;
        proxy_pass http://127.0.0.1:9999;
    }
}
EOF
cat <<'EOF' > reverse_proxy_cache.http
# ngx does not cache responses if proxy_buffering is set to off. It is on by default.
# 1MB keys_zone can store data for about 8000 keys
proxy_cache_path /usr/share/nginx/cache levels=1:2 keys_zone=STATIC:10m inactive=24h max_size=1g use_temp_path=off;
map $cache $control {
    1 "public, no-transform";
}
map $cache $expires {
    1 1d;
    default off; # or some other default value
}
map $uri $cache {
    ~*\.(js|css|png|jpe?g|gif|ico|html?)$ 1;
}
server {
    listen 80 reuseport;
    server_name _;
    location / {
        # disable nginx caching for certain file types
        set $no_cache "";
        if ($request_uri ~* \.gif$) {
          set $no_cache "1";
          set $expires off;
        }
        if ($args != "") {
            set $no_cache 1;
        }
        proxy_no_cache $no_cache;
        proxy_cache_bypass $no_cache;

        expires $expires;
        add_header Cache-Control $control;
        # add_header XXXX $upstream_http_xxxx;
        # # Hidden / Pass X-Powered-By to client
        # proxy_hide_header X-Powered-By;
        # proxy_pass_header X-Powered-By;
        # #Disables processing of certain response header fields from the proxied server.
        # proxy_ignore_headers Cache-Control Expires Vary;
        # proxy_cache_bypass $cookie_nocache $arg_nocache $http_pragma;
        # proxy_cache_methods GET HEAD POST;
        # proxy_cache_key $proxy_host$request_uri$cookie_jessionid;
        proxy_pass http://127.0.0.1:81;
        proxy_set_header Host $host;
        proxy_buffering on;
        # Make sure your backend does not return Set-Cookie header.
        # If Nginx sees it, it disables caching.
        # http://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_ignore_headers
        proxy_ignore_headers "Set-Cookie";
        proxy_hide_header "Set-Cookie";

        proxy_cache STATIC;
        proxy_cache_valid 200 302 1d;
        proxy_cache_valid 404 1h;
        proxy_cache_use_stale error timeout invalid_header updating http_500 http_502 http_503 http_504;
    }
}
server {
    listen 81 reuseport;
    server_name _;
    location / {
        alias /var/www/;
    }
}
EOF
cat <<'EOF' > blockips.conf
# copy this file to /etc/nginx/http-conf.d/
deny 178.238.234.1;
deny 76.90.254.19;
deny 85.17.26.68;     # spammy comments - Leaseweb
deny 85.17.230.23;    # spammy comments - Leaseweb
deny 173.234.11.105;  # junk referrers
deny 173.234.31.9;    # junk referrers - Ubiquityservers
deny 173.234.38.25;   # spammy comments
deny 173.234.153.30;  # junk referrers
deny 173.234.153.106; # spammy comments - Ubiquityservers
deny 173.234.175.68;  # spammy comments
deny 190.152.223.27;  # junk referrers
deny 195.191.54.90;   # odd behaviour, Mozilla, doesnt fetch js/css. Ended up doing a POST, prob a spambot
deny 195.229.241.174; # spammy comments - United Arab Emirates
deny 210.212.194.60;  # junk referrers + spammy comments
deny 76.91.248.49;    # bad bot
deny 1.4.0.0/17;
deny 1.10.16.0/20;
deny 1.116.0.0/14;
deny 5.34.242.0/23;
deny 5.72.0.0/14;
deny 5.134.128.0/19;
deny 14.4.0.0/14;
deny 14.245.0.0/16;
deny 23.235.48.0/20;
deny 27.111.48.0/20;
deny 27.122.32.0/20;
deny 27.126.160.0/20;
deny 31.11.43.0/24;
deny 31.222.200.0/21;
deny 36.0.8.0/21;
deny 36.37.48.0/20;
deny 37.139.49.0/24;
deny 37.148.216.0/21;
deny 37.246.0.0/16;
deny 41.72.64.0/19;
deny 42.0.32.0/19;
deny 42.1.56.0/22;
deny 42.1.128.0/17;
deny 42.52.0.0/14;
deny 42.83.80.0/22;
deny 42.96.0.0/18;
deny 42.123.36.0/22;
deny 42.128.0.0/12;
deny 42.160.0.0/12;
deny 42.194.8.0/22;
deny 42.194.12.0/22;
deny 42.194.128.0/17;
deny 43.229.52.0/22;
deny 43.236.0.0/16;
deny 43.250.64.0/22;
deny 43.250.116.0/22;
deny 43.252.80.0/22;
deny 43.252.152.0/22;
deny 43.252.180.0/22;
deny 43.255.188.0/22;
deny 45.64.88.0/22;
deny 45.117.208.0/22;
deny 45.121.144.0/22;
deny 46.29.248.0/22;
deny 46.29.248.0/21;
deny 46.148.112.0/20;
deny 46.151.48.0/21;
deny 46.232.192.0/21;
deny 46.243.140.0/24;
deny 46.243.142.0/24;
deny 49.8.0.0/14;
deny 49.128.104.0/22;
deny 58.87.64.0/18;
deny 59.254.0.0/15;
deny 60.233.0.0/16;
deny 61.11.224.0/19;
deny 61.13.128.0/17;
deny 61.45.251.0/24;
deny 62.182.152.0/21;
deny 64.234.224.0/20;
deny 66.231.64.0/20;
deny 67.213.128.0/20;
deny 67.218.208.0/20;
deny 72.13.16.0/20;
deny 78.31.184.0/21;
deny 78.31.211.0/24;
deny 79.173.104.0/21;
deny 80.76.8.0/21;
deny 81.22.152.0/23;
deny 83.175.0.0/18;
deny 85.121.39.0/24;
deny 86.55.40.0/23;
deny 86.55.42.0/23;
deny 88.135.16.0/20;
deny 91.194.254.0/23;
deny 91.195.254.0/23;
deny 91.198.127.0/24;
deny 91.200.248.0/22;
deny 91.203.20.0/22;
deny 91.207.4.0/22;
deny 91.209.12.0/24;
deny 91.212.104.0/24;
deny 91.212.198.0/24;
deny 91.212.201.0/24;
deny 91.212.220.0/24;
deny 91.213.126.0/24;
deny 91.213.172.0/24;
deny 91.216.3.0/24;
deny 91.217.10.0/23;
deny 91.220.35.0/24;
deny 91.220.62.0/24;
deny 91.220.163.0/24;
deny 91.223.89.0/24;
deny 91.226.97.0/24;
deny 91.229.210.0/24;
deny 91.230.110.0/24;
deny 91.230.252.0/23;
deny 91.234.36.0/24;
deny 91.235.2.0/24;
deny 91.236.74.0/23;
deny 91.236.120.0/24;
deny 91.237.198.0/24;
deny 91.238.82.0/24;
deny 91.239.24.0/24;
deny 91.239.238.0/24;
deny 91.240.163.0/24;
deny 91.240.165.0/24;
deny 91.242.217.0/24;
deny 91.243.115.0/24;
deny 93.175.240.0/20;
deny 94.26.112.0/20;
deny 94.154.128.0/18;
deny 95.216.0.0/15;
deny 101.192.0.0/14;
deny 101.199.0.0/16;
deny 101.202.0.0/16;
deny 101.203.128.0/19;
deny 101.248.0.0/15;
deny 101.252.0.0/15;
deny 103.2.44.0/22;
deny 103.10.68.0/22;
deny 103.12.216.0/22;
deny 103.16.76.0/24;
deny 103.20.36.0/22;
deny 103.23.8.0/22;
deny 103.36.64.0/22;
deny 103.41.124.0/22;
deny 103.41.180.0/22;
deny 103.42.115.0/24;
deny 103.55.28.0/22;
deny 103.57.248.0/22;
deny 103.61.4.0/22;
deny 103.228.60.0/22;
deny 103.229.36.0/22;
deny 103.230.144.0/22;
deny 103.231.84.0/22;
deny 103.232.136.0/22;
deny 103.232.172.0/22;
deny 103.236.32.0/22;
deny 103.242.184.0/22;
deny 104.143.112.0/20;
deny 104.255.136.0/21;
deny 106.96.0.0/14;
deny 108.166.224.0/19;
deny 109.94.208.0/20;
deny 110.44.128.0/20;
deny 110.232.160.0/20;
deny 113.20.160.0/19;
deny 114.8.0.0/16;
deny 115.85.133.0/24;
deny 116.78.0.0/15;
deny 116.128.0.0/10;
deny 116.144.0.0/15;
deny 116.146.0.0/15;
deny 117.100.0.0/15;
deny 118.177.0.0/16;
deny 118.185.0.0/16;
deny 119.232.0.0/16;
deny 120.48.0.0/15;
deny 120.92.0.0/17;
deny 120.92.128.0/18;
deny 120.92.192.0/19;
deny 120.92.224.0/20;
deny 121.100.128.0/18;
deny 122.129.0.0/18;
deny 122.202.96.0/19;
deny 123.136.80.0/20;
deny 124.68.0.0/15;
deny 124.70.0.0/15;
deny 124.157.0.0/18;
deny 124.242.0.0/16;
deny 124.245.0.0/16;
deny 125.31.192.0/18;
deny 125.58.0.0/18;
deny 125.169.0.0/16;
deny 128.13.0.0/16;
deny 128.168.0.0/16;
deny 128.191.0.0/16;
deny 129.47.0.0/16;
deny 129.76.64.0/18;
deny 130.148.0.0/16;
deny 130.196.0.0/16;
deny 130.201.0.0/16;
deny 130.222.0.0/16;
deny 131.100.148.0/22;
deny 132.145.0.0/16;
deny 132.232.0.0/16;
deny 132.240.0.0/16;
deny 134.18.0.0/16;
deny 134.22.0.0/16;
deny 134.23.0.0/16;
deny 134.33.0.0/16;
deny 134.73.0.0/16;
deny 134.127.0.0/16;
deny 134.172.0.0/16;
deny 134.209.0.0/16;
deny 136.228.0.0/16;
deny 136.230.0.0/16;
deny 137.76.0.0/16;
deny 137.105.0.0/16;
deny 137.171.0.0/16;
deny 138.36.148.0/22;
deny 138.43.0.0/16;
deny 138.128.224.0/19;
deny 138.200.0.0/16;
deny 138.216.0.0/16;
deny 138.249.0.0/16;
deny 139.47.0.0/16;
deny 139.167.0.0/16;
deny 139.188.0.0/16;
deny 140.143.128.0/17;
deny 140.167.0.0/16;
deny 140.204.0.0/16;
deny 141.136.16.0/24;
deny 141.136.22.0/24;
deny 141.136.27.0/24;
deny 141.178.0.0/16;
deny 141.253.0.0/16;
deny 143.49.0.0/16;
deny 143.64.0.0/16;
deny 143.135.0.0/16;
deny 143.189.0.0/16;
deny 144.207.0.0/16;
deny 145.231.0.0/16;
deny 146.3.0.0/16;
deny 147.7.0.0/16;
deny 147.119.0.0/16;
deny 147.220.0.0/16;
deny 148.154.0.0/16;
deny 148.178.0.0/16;
deny 148.185.0.0/16;
deny 148.248.0.0/16;
deny 149.109.0.0/16;
deny 149.114.0.0/16;
deny 149.118.0.0/16;
deny 149.143.64.0/18;
deny 150.10.0.0/16;
deny 150.22.128.0/17;
deny 150.25.0.0/16;
deny 150.40.0.0/16;
deny 150.107.106.0/23;
deny 150.107.220.0/22;
deny 150.121.0.0/16;
deny 150.126.0.0/16;
deny 150.129.136.0/22;
deny 150.141.0.0/16;
deny 150.230.0.0/16;
deny 150.242.36.0/22;
deny 151.123.0.0/16;
deny 151.192.0.0/16;
deny 151.212.0.0/16;
deny 151.237.184.0/22;
deny 152.136.0.0/16;
deny 152.147.0.0/16;
deny 153.14.0.0/16;
deny 153.93.0.0/16;
deny 155.40.0.0/16;
deny 155.66.0.0/16;
deny 155.73.0.0/16;
deny 155.108.0.0/16;
deny 155.204.0.0/16;
deny 155.249.0.0/16;
deny 157.115.0.0/16;
deny 157.162.0.0/16;
deny 157.186.0.0/16;
deny 157.195.0.0/16;
deny 157.231.0.0/16;
deny 157.232.0.0/16;
deny 158.54.0.0/16;
deny 158.58.0.0/17;
deny 158.90.0.0/17;
deny 159.85.0.0/16;
deny 159.100.0.0/18;
deny 159.111.0.0/16;
deny 159.135.0.0/16;
deny 159.151.0.0/16;
deny 159.219.0.0/16;
deny 159.223.0.0/16;
deny 159.229.0.0/16;
deny 160.14.0.0/16;
deny 160.21.0.0/16;
deny 160.180.0.0/16;
deny 160.181.0.0/16;
deny 160.200.0.0/16;
deny 160.222.0.0/16;
deny 160.235.0.0/16;
deny 160.240.0.0/16;
deny 160.255.0.0/16;
deny 161.59.0.0/16;
deny 161.66.0.0/16;
deny 161.71.0.0/16;
deny 161.189.0.0/16;
deny 161.232.0.0/16;
deny 162.211.236.0/22;
deny 163.47.19.0/24;
deny 163.50.0.0/16;
deny 163.58.0.0/16;
deny 163.59.0.0/16;
deny 163.227.128.0/21;
deny 163.254.0.0/16;
deny 164.6.0.0/16;
deny 164.60.0.0/16;
deny 164.137.0.0/16;
deny 165.102.0.0/16;
deny 165.192.0.0/16;
deny 165.205.0.0/16;
deny 165.209.0.0/16;
deny 167.74.0.0/18;
deny 167.87.0.0/16;
deny 167.97.0.0/16;
deny 167.103.0.0/16;
deny 167.162.0.0/16;
deny 167.175.0.0/16;
deny 167.224.0.0/19;
deny 168.129.0.0/16;
deny 170.67.0.0/16;
deny 170.113.0.0/16;
deny 170.114.0.0/16;
deny 170.120.0.0/16;
deny 170.179.0.0/16;
deny 171.22.0.0/16;
deny 171.25.0.0/17;
deny 171.26.0.0/16;
deny 172.103.64.0/18;
deny 175.103.64.0/18;
deny 176.47.0.0/16;
deny 176.61.136.0/22;
deny 176.61.136.0/21;
deny 176.65.128.0/17;
deny 176.97.116.0/22;
deny 176.97.152.0/22;
deny 177.36.16.0/20;
deny 177.74.160.0/20;
deny 178.159.176.0/20;
deny 178.216.48.0/21;
deny 180.178.192.0/18;
deny 180.236.0.0/14;
deny 181.118.32.0/19;
deny 185.3.132.0/22;
deny 185.11.140.0/24;
deny 185.11.143.0/24;
deny 185.68.156.0/22;
deny 185.72.68.0/22;
deny 185.75.56.0/22;
deny 185.93.187.0/24;
deny 186.1.128.0/19;
deny 186.96.96.0/19;
deny 186.148.160.0/19;
deny 186.195.224.0/20;
deny 188.239.128.0/18;
deny 188.247.135.0/24;
deny 188.247.230.0/24;
deny 190.2.208.0/21;
deny 190.9.48.0/21;
deny 190.13.80.0/21;
deny 192.5.103.0/24;
deny 192.12.131.0/24;
deny 192.26.25.0/24;
deny 192.31.212.0/23;
deny 192.40.29.0/24;
deny 192.43.153.0/24;
deny 192.43.154.0/23;
deny 192.43.156.0/22;
deny 192.43.160.0/24;
deny 192.43.175.0/24;
deny 192.43.176.0/21;
deny 192.43.184.0/24;
deny 192.54.39.0/24;
deny 192.54.73.0/24;
deny 192.54.110.0/24;
deny 192.67.16.0/24;
deny 192.67.160.0/22;
deny 192.84.243.0/24;
deny 192.86.85.0/24;
deny 192.88.74.0/24;
deny 192.100.142.0/24;
deny 192.101.44.0/24;
deny 192.101.181.0/24;
deny 192.101.200.0/21;
deny 192.101.240.0/21;
deny 192.101.248.0/23;
deny 192.125.0.0/17;
deny 192.133.3.0/24;
deny 192.152.0.0/24;
deny 192.152.194.0/24;
deny 192.154.11.0/24;
deny 192.158.51.0/24;
deny 192.160.44.0/24;
deny 192.171.64.0/19;
deny 192.189.25.0/24;
deny 192.190.49.0/24;
deny 192.190.97.0/24;
deny 192.195.150.0/24;
deny 192.197.87.0/24;
deny 192.203.252.0/24;
deny 192.206.114.0/24;
deny 192.219.120.0/21;
deny 192.219.128.0/18;
deny 192.219.192.0/20;
deny 192.219.208.0/21;
deny 192.226.16.0/20;
deny 192.229.32.0/19;
deny 192.231.66.0/24;
deny 192.234.189.0/24;
deny 192.245.101.0/24;
deny 193.0.129.0/24;
deny 193.23.126.0/24;
deny 193.25.48.0/20;
deny 193.26.64.0/19;
deny 193.43.134.0/24;
deny 193.104.41.0/24;
deny 193.104.94.0/24;
deny 193.104.110.0/24;
deny 193.105.207.0/24;
deny 193.105.245.0/24;
deny 193.107.16.0/22;
deny 193.138.244.0/22;
deny 193.139.0.0/16;
deny 193.150.120.0/24;
deny 193.164.11.0/24;
deny 193.177.64.0/18;
deny 193.189.116.0/23;
deny 193.222.50.0/24;
deny 193.243.0.0/17;
deny 194.0.177.0/24;
deny 194.1.152.0/24;
deny 194.29.185.0/24;
deny 194.38.0.0/18;
deny 194.50.116.0/24;
deny 194.54.156.0/22;
deny 194.110.160.0/22;
deny 195.20.141.0/24;
deny 195.78.108.0/23;
deny 195.88.190.0/23;
deny 195.182.57.0/24;
deny 195.190.13.0/24;
deny 195.191.56.0/23;
deny 195.191.102.0/23;
deny 195.225.176.0/22;
deny 196.1.109.0/24;
deny 196.42.128.0/17;
deny 196.44.112.0/20;
deny 196.63.0.0/16;
deny 196.188.0.0/14;
deny 196.193.0.0/16;
deny 196.247.0.0/16;
deny 197.154.0.0/16;
deny 198.13.0.0/20;
deny 198.14.128.0/19;
deny 198.14.160.0/19;
deny 198.20.16.0/20;
deny 198.23.32.0/20;
deny 198.45.32.0/20;
deny 198.45.64.0/19;
deny 198.48.16.0/20;
deny 198.56.64.0/18;
deny 198.57.64.0/20;
deny 198.62.70.0/24;
deny 198.62.76.0/24;
deny 198.96.224.0/20;
deny 198.99.117.0/24;
deny 198.102.222.0/24;
deny 198.148.212.0/24;
deny 198.151.16.0/20;
deny 198.151.64.0/18;
deny 198.151.152.0/22;
deny 198.160.205.0/24;
deny 198.162.208.0/20;
deny 198.169.201.0/24;
deny 198.177.175.0/24;
deny 198.177.176.0/22;
deny 198.177.180.0/24;
deny 198.177.214.0/24;
deny 198.178.64.0/19;
deny 198.179.22.0/24;
deny 198.181.32.0/20;
deny 198.181.64.0/19;
deny 198.183.32.0/19;
deny 198.184.193.0/24;
deny 198.184.208.0/24;
deny 198.186.25.0/24;
deny 198.186.208.0/24;
deny 198.187.64.0/18;
deny 198.187.192.0/24;
deny 198.190.173.0/24;
deny 198.199.212.0/24;
deny 198.202.237.0/24;
deny 198.204.0.0/21;
deny 198.205.64.0/19;
deny 198.212.132.0/24;
deny 199.5.152.0/23;
deny 199.5.229.0/24;
deny 199.26.96.0/19;
deny 199.26.137.0/24;
deny 199.26.207.0/24;
deny 199.26.251.0/24;
deny 199.33.222.0/24;
deny 199.34.128.0/18;
deny 199.46.32.0/19;
deny 199.58.248.0/21;
deny 199.60.102.0/24;
deny 199.71.56.0/21;
deny 199.71.192.0/20;
deny 199.84.55.0/24;
deny 199.84.56.0/22;
deny 199.84.60.0/24;
deny 199.84.64.0/19;
deny 199.87.208.0/21;
deny 199.88.32.0/20;
deny 199.88.48.0/22;
deny 199.89.16.0/20;
deny 199.89.198.0/24;
deny 199.120.163.0/24;
deny 199.165.32.0/19;
deny 199.166.200.0/22;
deny 199.184.82.0/24;
deny 199.185.192.0/20;
deny 199.196.192.0/19;
deny 199.198.160.0/20;
deny 199.198.176.0/21;
deny 199.198.184.0/23;
deny 199.198.188.0/22;
deny 199.200.64.0/19;
deny 199.212.96.0/20;
deny 199.223.0.0/20;
deny 199.230.64.0/19;
deny 199.230.96.0/21;
deny 199.233.85.0/24;
deny 199.233.96.0/24;
deny 199.245.138.0/24;
deny 199.246.137.0/24;
deny 199.246.213.0/24;
deny 199.246.215.0/24;
deny 199.248.64.0/18;
deny 199.249.64.0/19;
deny 199.253.32.0/20;
deny 199.253.48.0/21;
deny 199.253.224.0/20;
deny 199.254.32.0/20;
deny 200.3.128.0/20;
deny 200.22.0.0/16;
deny 201.169.0.0/16;
deny 201.182.0.0/16;
deny 202.0.192.0/18;
deny 202.20.32.0/19;
deny 202.21.64.0/19;
deny 202.27.96.0/23;
deny 202.27.98.0/24;
deny 202.27.99.0/24;
deny 202.27.100.0/22;
deny 202.27.120.0/22;
deny 202.27.161.0/24;
deny 202.27.162.0/23;
deny 202.27.164.0/22;
deny 202.27.168.0/24;
deny 202.39.112.0/20;
deny 202.40.32.0/19;
deny 202.40.64.0/18;
deny 202.61.108.0/24;
deny 202.68.0.0/18;
deny 202.80.152.0/21;
deny 202.148.32.0/20;
deny 202.148.176.0/20;
deny 202.183.0.0/19;
deny 202.189.80.0/20;
deny 203.0.116.0/22;
deny 203.2.200.0/22;
deny 203.9.0.0/19;
deny 203.31.88.0/23;
deny 203.34.70.0/23;
deny 203.34.71.0/24;
deny 203.86.252.0/22;
deny 203.148.80.0/22;
deny 203.149.92.0/22;
deny 203.169.0.0/22;
deny 203.189.112.0/22;
deny 203.191.64.0/18;
deny 204.19.38.0/23;
deny 204.44.32.0/20;
deny 204.44.192.0/20;
deny 204.44.224.0/20;
deny 204.48.16.0/20;
deny 204.52.255.0/24;
deny 204.57.16.0/20;
deny 204.75.147.0/24;
deny 204.75.228.0/24;
deny 204.80.198.0/24;
deny 204.86.16.0/20;
deny 204.87.199.0/24;
deny 204.89.224.0/24;
deny 204.106.128.0/18;
deny 204.106.192.0/19;
deny 204.107.208.0/24;
deny 204.126.244.0/23;
deny 204.128.151.0/24;
deny 204.128.180.0/24;
deny 204.130.167.0/24;
deny 204.147.240.0/20;
deny 204.155.128.0/20;
deny 204.187.155.0/24;
deny 204.187.156.0/22;
deny 204.187.160.0/19;
deny 204.187.192.0/19;
deny 204.187.224.0/20;
deny 204.187.240.0/21;
deny 204.187.248.0/22;
deny 204.187.252.0/23;
deny 204.187.254.0/24;
deny 204.194.64.0/21;
deny 204.194.184.0/21;
deny 204.225.159.0/24;
deny 204.225.210.0/24;
deny 204.238.137.0/24;
deny 204.238.170.0/24;
deny 204.238.183.0/24;
deny 205.137.0.0/20;
deny 205.142.104.0/22;
deny 205.144.0.0/20;
deny 205.144.176.0/20;
deny 205.151.128.0/19;
deny 205.159.45.0/24;
deny 205.159.174.0/24;
deny 205.159.180.0/24;
deny 205.166.77.0/24;
deny 205.166.84.0/24;
deny 205.166.130.0/24;
deny 205.166.168.0/24;
deny 205.166.211.0/24;
deny 205.172.176.0/22;
deny 205.172.244.0/22;
deny 205.175.160.0/19;
deny 205.189.71.0/24;
deny 205.189.72.0/23;
deny 205.203.0.0/19;
deny 205.203.224.0/19;
deny 205.207.134.0/24;
deny 205.210.107.0/24;
deny 205.210.139.0/24;
deny 205.210.171.0/24;
deny 205.210.172.0/22;
deny 205.214.96.0/19;
deny 205.214.128.0/19;
deny 205.233.224.0/20;
deny 205.236.185.0/24;
deny 205.236.189.0/24;
deny 205.253.0.0/16;
deny 206.51.29.0/24;
deny 206.81.0.0/19;
deny 206.127.192.0/19;
deny 206.130.188.0/24;
deny 206.143.128.0/17;
deny 206.189.0.0/16;
deny 206.195.224.0/19;
deny 206.197.28.0/24;
deny 206.197.29.0/24;
deny 206.197.77.0/24;
deny 206.197.165.0/24;
deny 206.203.64.0/18;
deny 206.209.80.0/20;
deny 206.224.160.0/19;
deny 206.226.0.0/19;
deny 206.226.32.0/19;
deny 206.227.64.0/18;
deny 207.22.192.0/18;
deny 207.32.128.0/19;
deny 207.45.224.0/20;
deny 207.110.64.0/18;
deny 207.110.96.0/19;
deny 207.110.128.0/18;
deny 207.183.192.0/19;
deny 207.226.192.0/20;
deny 207.230.96.0/19;
deny 207.234.0.0/17;
deny 207.254.128.0/21;
deny 208.81.136.0/21;
deny 208.90.0.0/21;
deny 209.51.32.0/20;
deny 209.66.128.0/19;
deny 209.95.192.0/19;
deny 209.97.128.0/18;
deny 209.145.0.0/19;
deny 209.182.64.0/19;
deny 209.198.176.0/20;
deny 210.79.128.0/18;
deny 210.87.64.0/18;
deny 216.59.128.0/18;
deny 220.154.0.0/16;
deny 221.132.192.0/18;
deny 223.0.0.0/15;
deny 223.25.252.0/22;
deny 223.168.0.0/16;
deny 223.169.0.0/16;
deny 223.170.0.0/16;
deny 223.171.0.0/16;
deny 223.172.0.0/16;
deny 223.173.0.0/16;
deny 223.201.0.0/16;
deny 223.254.0.0/16;
deny 69.64.147.24; # domain name hijacker
deny 150.70.0.0/16; # Trend Micro Bot
EOF
cat <<'EOF' > proxy_cache.conf
# copy this file to /etc/nginx/http-conf.d/
# mount -t tmpfs -o size=100M none /mnt
proxy_cache_path /dev/shm/cache levels=1:2 keys_zone=SHM_CACHE:10m inactive=24h max_size=512m use_temp_path=off;
proxy_cache SHM_CACHE;
# proxy_buffers 64 128k;
# proxy_busy_buffers_size 256k;
# proxy_buffer_size 64k;
proxy_cache_valid 200 302 1d;
proxy_cache_valid 404 5m;
# proxy_cache_use_stale error timeout invalid_header updating http_500 http_502 http_503 http_504;
# If the header includes the “Set-Cookie” field, such a response will not be cached.
# If the header includes the “Vary” field with the special value “*”, such a response will not be cached
# http://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_ignore_headers
proxy_ignore_headers "Set-Cookie" "X-Accel-Expires" "X-Accel-Limit-Rate" "X-Accel-Buffering";
# ngx does not cache responses if proxy_buffering is set to off. It is on by default.
proxy_buffering on;
EOF
cat <<'EOF' > cache_expiration.conf
# copy this file to /etc/nginx/http-conf.d/
# # kill cache
# add_header Last-Modified $date_gmt;
# add_header Cache-Control 'no-store, no-cache';
# if_modified_since off;
# expires off;
# etag off;
map $sent_http_content_type $expires {
    default                                 1M;
    ""                                      off;
    ~*text/css                              1y;
    ~*application/atom\+xml                 1h;
    ~*application/rdf\+xml                  1h;
    ~*application/rss\+xml                  1h;
    ~*application/json                      0;
    ~*application/ld\+json                  0;
    ~*application/schema\+json              0;
    ~*application/geo\+json                 0;
    ~*application/xml                       0;
    ~*text/calendar                         0;
    ~*text/xml                              0;
    ~*image/vnd.microsoft.icon              1w;
    ~*image/x-icon                          1w;
    ~*text/html                             0;
    ~*application/javascript                1y;
    ~*application/x-javascript              1y;
    ~*text/javascript                       1y;
    ~*application/manifest\+json            1w;
    ~*application/x-web-app-manifest\+json  0;
    ~*text/cache-manifest                   0;
    ~*text/markdown                         0;
    ~*audio/                                1M;
    ~*image/                                1M;
    ~*video/                                1M;
    ~*application/wasm                      1y;
    ~*font/                                 1M;
    ~*application/vnd.ms-fontobject         1M;
    ~*application/x-font-ttf                1M;
    ~*application/x-font-woff               1M;
    ~*application/font-woff                 1M;
    ~*application/font-woff2                1M;
    ~*text/x-cross-domain-policy            1w;
}
expires $expires;
EOF
cat <<'EOF' > cache_static.http
server {
    listen 80 reuseport;
    server_name _;
    location ~* \.(?:ico|css|js|gif|jpe?g|png)$ {
        expires 30d;
        add_header Vary Accept-Encoding;
        limit_rate_after 100k;
        limit_rate 100k;
        access_log off;
    }
    ## All static files will be served directly.
    location ~* ^.+\.(?:css|cur|js|jpe?g|gif|htc|ico|png|html|xml|otf|ttf|eot|woff|woff2|svg)$ {
        access_log off;
        expires 30d;
        add_header Cache-Control public;
        ## No need to bleed constant updates. Send the all shebang in one
        ## fell swoop.
        tcp_nodelay off;
        ## Set the OS file cache.
        open_file_cache max=3000 inactive=120s;
        open_file_cache_valid 45s;
        open_file_cache_min_uses 2;
        open_file_cache_errors off;
    }
}
EOF
cat <<'EOF' > cors.http
server {
    listen 80 reuseport;
    server_name api.localhost;
    location / {
        add_header 'Access-Control-Allow-Origin' 'http://api.localhost';
        add_header 'Access-Control-Allow-Credentials' 'true';
        add_header 'Access-Control-Allow-Headers' 'Authorization,Accept,Origin,DNT,X-CustomHeader,Keep-Alive,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Content-Range,Range';
        add_header 'Access-Control-Allow-Methods' 'GET,POST,OPTIONS,PUT,DELETE,PATCH';
        if ($request_method = 'OPTIONS') {
            add_header 'Access-Control-Allow-Origin' 'http://api.localhost';
            add_header 'Access-Control-Allow-Credentials' 'true';
            add_header 'Access-Control-Allow-Headers' 'Authorization,Accept,Origin,DNT,X-CustomHeader,Keep-Alive,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Content-Range,Range';
            add_header 'Access-Control-Allow-Methods' 'GET,POST,OPTIONS,PUT,DELETE,PATCH';
            add_header 'Access-Control-Max-Age' 1728000;
            add_header 'Content-Type' 'text/plain charset=UTF-8';
            add_header 'Content-Length' 0;
            return 204;
        }
        proxy_redirect off;
        proxy_set_header host $host;
        proxy_set_header X-real-ip $remote_addr;
        proxy_set_header X-forward-for $proxy_add_x_forwarded_for;
        proxy_pass http://127.0.0.1:3000;
  }
}
EOF
cat <<'EOF' > error_page2.http
# # When "The plain HTTP request was sent to HTTPS port" happens
# # redirect it to https version of current hostname, port and URI.
# error_page 497 https://$host:$server_port$request_uri;
error_page 400 /error/400.html;
error_page 401 /error/401.html;
error_page 403 /error/403.html;
error_page 404 /error/404.html;
error_page 410 /error/410.html;
error_page 500 /error/500.html;
error_page 501 /error/501.html;
error_page 502 /error/502.html;
error_page 503 /error/503.html;
error_page 504 /error/504.html;
error_page 505 /error/505.html;
server {
    listen 80 reuseport;
    server_name _;
    location ^~ /error/ {
        internal;
        root /var/www;
        allow all;
    }
}
EOF
cat <<'EOF' > error_page.http
# mkdir -p /etc/nginx/errors/
# echo "401" > /etc/nginx/errors/401
server {
    listen 80 reuseport;
    server_name _;
    error_page 401 /error/401.html;
    error_page 404 /error/404.html;
    error_page 500 502 503 504 /error/generic.html;
    # location ~ ^/error/(.*)$ { alias /etc/nginx/errors/$1; }
    location = /error/401.html { alias /etc/nginx/errors/401; }
    location = /error/404.html { alias /etc/nginx/errors/404; }
    location = /error/generic.html { alias /etc/nginx/errors/5xx; }
    location /401 { return 401; }
    location /404 { return 404; }
    location /500 { return 502; }
}
EOF
cat <<'EOF' > websocket.http
upstream backend {
    server 192.168.168.132;
    keepalive 64;
}
map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}
server {
    listen 80 reuseport;
    server_name _;
    location /chat/ {
        proxy_pass http://backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        # proxy_read_timeout 2s;
        # send_timeout 2s;
        # By default, the connection will be closed if the proxied server does
        # not transmit any data within 60 seconds. This timeout can be increased
        # with the proxy_read_timeout
    }
}
EOF
cat <<'EOF' >serve_static_if_not_found_proxypass.http
server {
    listen 80 reuseport;
    server_name _;
    location = /login {
        default_type "text/html";
        alias /var/www/login.html;
    }
    location / {
        alias /var/www/;
        try_files $uri @proxy;
    }
    location @proxy {
        proxy_pass http://www.test.com;
    }
}
EOF
cat <<'EOF' >auto_subdomain_if_folder_exists.http
# mkdir /var/www/sites/www/ && echo "www" > /var/www/sites/www/index.html
# curl -vvv -H "Host: www.test.com" http://localhost
server {
    listen 80 reuseport;
    server_name ~^(?<project>.+)\.test\.com$;
    if (!-d /var/www/sites/$project) {
        return 404 "$project not directory";
    }
    root /var/www/sites/$project;
}
EOF
cat <<'EOF' >change_upstream_errorpage.http
server {
    listen 80 reuseport;
    server_name _;
    location = /login {
        default_type "text/html";
        alias /var/www/login.html;
    }
    location / {
        proxy_pass http://www.test.com;
        # # whether proxied responses with codes greater than or equal to 300 should be passed to a client
        proxy_intercept_errors on;
        error_page 403 =200 @503.html;
        error_page 504 = @504;
    }
    location @503.html {
        return 200 "503 error";
    }
    location @504 {
        return 200 "$upstream_addr 504 error";
    }
}
EOF
cat <<'EOF' >ssi.http
server {
    listen 80 reuseport;
    server_name _;
    location = /test {
        ssi on;
        default_type text/html;
        return 200 '<!--#config timefmt="%A, %H:%M:%S" --><!--#set var="v" value="$date_gmt" --><!--#echo var="v" -->';
    }
}
EOF
cat <<'EOF' >addition.http
server {
    listen 80 reuseport;
    server_name _;
    # addition_types text/html;
    location /a.gif { empty_gif; }
    location / {
        # add_before_body /add_before;
        add_after_body /add_after;
        alias /var/www/;
    }
    location /add_before {
        return 200 "before";
    }
    location /add_after {
        internal;
        return 200 "<script>
var myDiv = document.createElement('div');
myDiv.id = 'div_id';
myDiv.innerHTML = '<h1>Hello World!</h1>';
document.body.appendChild(myDiv);
</script>";
    }
}
EOF
cat <<'EOF' > sub_filter.http
# ...........................
# NGX_CONF_BUFFER=4096
# <img src="data:image/png;base64,${base64}" alt="Red dot"/>
# sub_filter '</body>' '<a href="http://xxxx"><img style="position: fixed; top: 0; right: 0; border: 0;" src="http://s3.amazonaws.com/github/ribbons/forkme_right_gray_6d6d6d.png" alt="xxxxxxxxxxxx"></a></body>';
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
    listen 80 reuseport;
    listen unix:/var/run/nginx.sock;
    server_name _;
    location / {
        sub_filter '</body>' '<a href="http://www.xxxx.com"><img style="position: fixed; top: 0; right: 0; border: 0;" src="https://res.xxxx.com/_static_/demo.png" alt="bj idc"></a></body>';
        proxy_set_header referer http://www.xxx.net; #如果网站有验证码，可以解决验证码不显示问题
        sub_filter_once on;
        # sub_filter_types text/html;
        root /var/www;
    }
    location /allow_unix {
        allow unix:;
    }
    location /deny_unix {
        deny unix:;
    }
    # location /xslt {
    #     ssi on;
    #     sub_filter_types *;
    #     sub_filter root>foo bar;
    #     xslt_stylesheet test.xslt;
    # }
}
EOF
cat <<'EOF' > brotli-compress.conf
# copy this file to /etc/nginx/http-conf.d/
# curl -vvv -H "Accept-Encoding: gzip, deflate, br" http://localhost/test.html -o - | brotli -d -c
# curl -vvv -H "Accept-Encoding: gzip, deflate" http://localhost/test.html -o - | gzip -d -c
# curl -vvv -H "Accept-Encoding: deflate, br" http://localhost/test.html -o - | brotli -d -c
# need brotli module
brotli on;
brotli_static on;
brotli_comp_level 6;
brotli_buffers 16 8k;
brotli_min_length 256;
brotli_types
    application/atom+xml
    application/geo+json
    application/javascript
    application/x-javascript
    application/json
    application/ld+json
    application/manifest+json
    application/rdf+xml
    application/rss+xml
    application/vnd.ms-fontobject
    application/wasm
    application/x-web-app-manifest+json
    application/xhtml+xml
    application/xml
    font/eot
    font/otf
    font/ttf
    image/bmp
    image/svg+xml
    text/cache-manifest
    text/calendar
    text/css
    text/javascript
    text/markdown
    text/plain
    text/xml
    text/vcard
    text/vnd.rim.location.xloc
    text/vtt
    text/x-component
    text/x-cross-domain-policy;
EOF
cat <<'EOF' > more_tuning.conf
# copy this file to /etc/nginx/http-conf.d/
# need headers-more-nginx-module
# hidden Server: nginx ...
proxy_pass_header Server;
# # OR
# more_set_headers 'Server: my-server';
#
# map $http_x_forwarded_for $realipaddr {
#     "" $remote_addr;
#     ~^(?P<firstAddr>[0-9\.]+),?.*$ $firstAddr;
# }
# map $http_user_agent $bad_bots {
#     default 0;
#     ~*(AltaVista|Slurp|BlackWidow|Bot|ChinaClaw|Custo|DISCo|Download|Demon|eCatch|EirGrabber|EmailSiphon|EmailWolf|SuperHTTP|Surfbot|WebWhacker) 1;
#     ~*(Express|WebPictures|ExtractorPro|EyeNetIE|FlashGet|GetRight|GetWeb!|Go!Zilla|Go-Ahead-Got-It|GrabNet|Grafula|HMView|Go!Zilla|Go-Ahead-Got-It) 1;
#     ~*(rafula|HMView|HTTrack|Stripper|Sucker|Indy|InterGET|Ninja|JetCar|Spider|larbin|LeechFTP|Downloader|tool|Navroad|NearSite|NetAnts|tAkeOut|WWWOFFLE) 1;
#     ~*(GrabNet|NetSpider|Vampire|NetZIP|Octopus|Offline|PageGrabber|Foto|pavuk|pcBrowser|RealDownload|ReGet|SiteSnagger|SmartDownload|SuperBot|WebSpider) 1;
#     ~*(Teleport|VoidEYE|Collector|WebAuto|WebCopier|WebFetch|WebGo|WebLeacher|WebReaper|WebSauger|eXtractor|Quester|WebStripper|WebZIP|Wget|Widow|Zeus) 1;
#     ~*(Twengabot|htmlparser|libwww|Python|perl|urllib|scan|email|PycURL|Pyth|PyQ|WebCollector|WebCopy|webcraw) 1;
# }

add_header Set-Cookie "Path=/; HttpOnly; Secure";

# cache informations about FDs
open_file_cache max=200000 inactive=20s;
open_file_cache_valid 30s;
open_file_cache_min_uses 2;
open_file_cache_errors on;

# request timed out -- default 60
client_body_timeout 10s;
client_header_timeout 5s;

# if client stop responding, free up memory -- default 60
send_timeout 2s;

# Turn on session resumption, using a 10 min cache shared across nginx processes,
# as recommended by http://nginx.org/en/docs/http/configuring_https_servers.html
ssl_session_cache shared:SSL:10m;
ssl_session_timeout 10m;
keepalive_timeout 70;
# Buffer size of 1400 bytes fits in one MTU.
ssl_buffer_size 1400;
# # Enabling Forward Secrecy
# # openssl dhparam -out /etc/nginx/ssl/dh2048.pem 2048
# ssl_dhparam /etc/nginx/dh2048.pem;
# # stapling, OCSP在线查询证书吊销情况
# ssl_stapling on;
# ssl_stapling_verify on;

variables_hash_bucket_size 256;
EOF
cat <<'EOF'>diag_log_json.conf
# copy this file to /etc/nginx/http-conf.d/
js_import js/diag_log_json.js;
js_set $json_debug_log diag_log_json.debugLog;
map $status $is_error {
    # List of response codes that warrant a detailed log file
    400     1; # Bad request, including expired client cert
    495     1; # Client cert error
    502     1; # Bad gateway (an upstream server cannot be selected)
    504     1; # Gateway timeout (couldn't connect to selected upstream)
    default $multi_upstreams; # If we tried more than one upstream server
}
map $upstream_status $multi_upstreams {
    "~,"    1; # Includes a comma
    default 0;
}
log_format access_debug escape=none $json_debug_log;
access_log /var/log/nginx/access_debug.log access_debug buffer=512k flush=5m if=$is_error;
EOF
cat <<'EOF'>diag_log_json.js
export default { debugLog };
function debugLog(r) {
    var connection = {
        "serial": Number(r.variables.connection),
        "request_count": Number(r.variables.connection_requests),
        "elapsed_time": Number(r.variables.request_time)
    }
    if (r.variables.pipe == "p") {
        connection.pipelined = true;
    } else {
        connection.pipelined = false;
    }
    if ( r.variables.ssl_protocol !== undefined ) {
        connection.ssl = sslInfo(r);
    }
    var request = {
        "client": r.variables.remote_addr,
        "port": Number(r.variables.server_port),
        "host": r.variables.host,
        "method": r.method,
        "uri": r.uri,
        "http_version": Number(r.httpVersion),
        "bytes_received": Number(r.variables.request_length)
    };
    request.headers = {};
    for (var h in r.headersIn) {
        request.headers[h] = r.headersIn[h];
    }
    var upstreams = [];
    if ( r.variables.upstream_status !== undefined ) {
        upstreams = upstreamArray(r);
    }
    var response = {
        "status": Number(r.variables.status),
        "bytes_sent": Number(r.variables.bytes_sent),
    }
    response.headers = {};
    for (var h in r.headersOut) {
        response.headers[h] = r.headersOut[h];
    }
    return JSON.stringify({
        "timestamp": r.variables.time_iso8601,
        "connection": connection,
        "request": request,
        "upstreams": upstreams,
        "response": response
    });
}
function sslInfo(r) {
    var ssl = {
        "protocol": r.variables.ssl_protocol,
        "cipher": r.variables.ssl_cipher,
        "session_id": r.variables.ssl_session_id
    }
    if ( r.variables.ssl_session_reused  == 'r' ) {
        ssl.session_reused = true;
    } else {
        ssl.session_reused = false;
    }
    if ( r.variables.ssl_protocol == 'TLSv1.3' ) {
        if ( r.variables.ssl_early_data == '1' ) {
            ssl.zero_rtt = true;
        } else {
            ssl.zero_rtt = false;
        }
    }
    ssl.client_cert = clientCert(r);
    return ssl;
}

function clientCert(r) {
    var clientCert = {};
    clientCert.status = r.variables.ssl_client_verify;
    clientCert.serial = r.variables.ssl_client_serial;
    clientCert.fingerprint = r.variables.ssl_client_fingerprint;
    clientCert.subject = r.variables.ssl_client_s_dn;
    clientCert.issuer = r.variables.ssl_client_i_dn;
    clientCert.starts = r.variables.ssl_client_v_start;
    clientCert.expires = r.variables.ssl_client_v_end;
    if ( r.variables.ssl_client_v_remain == 0 ) {
        clientCert.expired = true;
    } else if ( r.variables.ssl_client_v_remain > 0) {
        clientCert.expired = false;
    }
    clientCert.pem = r.variables.ssl_client_raw_cert;

    return clientCert;
}

function upstreamArray(r) {
    var addr = r.variables.upstream_addr.split(', ');
    var connect_time = r.variables.upstream_connect_time.split(', ');
    var header_time = r.variables.upstream_header_time.split(', ');
    var response_time = r.variables.upstream_response_time.split(', ');
    var bytes_received = r.variables.upstream_bytes_received.split(', ');
    var bytes_sent = r.variables.upstream_bytes_sent.split(', ');
    var status = r.variables.upstream_status.split(', ');
    var i, addr_port, upstream = [];
    for (i=0; i < status.length; i++) {
        upstream[i] = {};
        addr_port = addr[i].split(':');
        if (addr_port[0] == "unix") {
            upstream[i].unix_socket = addr_port[1];
        } else {
            upstream[i].server_addr = addr_port[0];
            upstream[i].server_port = Number(addr_port[1]);
        }
        upstream[i].connect_time = Number(connect_time[i]);
        if (isNaN(upstream[i].connect_time)) upstream[i].connect_time = null;
        upstream[i].header_time = Number(header_time[i]);
        if (isNaN(upstream[i].header_time)) upstream[i].header_time = null;
        upstream[i].response_time = Number(response_time[i]);
        if (isNaN(upstream[i].response_time)) upstream[i].response_time = null;
        upstream[i].bytes_sent = Number(bytes_sent[i]);
        upstream[i].bytes_received = Number(bytes_received[i]);
        upstream[i].status = Number(status[i]);

        if (upstream[i].status == 502 && upstream[i].connect_time === null && upstream[i].response_time > 0) {
            upstream[i].info = "Connection failed / SSL error";
        }
        if (upstream[i].status == 502 && upstream[i].connect_time === null && upstream[i].response_time == 0) {
            upstream[i].info = "Not attempted / temporarily disabled";
        }
    }
    return upstream;
}
EOF
cat <<'EOF'>pagespeed.http
# # PageSpeed admin config
# # sharemem statistics
pagespeed Statistics on;
# # vhost statistics
pagespeed UsePerVhostStatistics on;
pagespeed StatisticsLogging on;
pagespeed StatisticsLoggingIntervalMs 60000;
pagespeed StatisticsLoggingMaxFileSizeKb 1024;
#buff size 0, no remain message
pagespeed MessageBufferSize 100000;
pagespeed LogDir /var/log/pagespeed;
pagespeed StatisticsPath /ngx_pagespeed_statistics;
pagespeed GlobalStatisticsPath /ngx_pagespeed_global_statistics;
pagespeed MessagesPath /ngx_pagespeed_message;
pagespeed ConsolePath /pagespeed_console;
# curl http://127.0.0.1/pagespeed_admin
pagespeed AdminPath /pagespeed_admin;
pagespeed GlobalAdminPath /pagespeed_global_admin;

# # page speed config
# best tmpfs
pagespeed FileCachePath /tmp/ngx_pagespeed_cache;
pagespeed on;

server {
    listen 80 reuseport;
    server_name _;
    # pagespeed on;
    location / {
        # pagespeed on;
        return 200;
    }
    # # page speed admin uri protecte
    location /ngx_pagespeed_statistics {
        auth_basic "PageSpeed Admin Dashboard";
        auth_basic_user_file /etc/nginx/htpasswd;
    }
    location /ngx_pagespeed_global_statistics {
        auth_basic "PageSpeed Admin Dashboard";
        auth_basic_user_file /etc/nginx/htpasswd;
    }
    location /ngx_pagespeed_message {
        auth_basic "PageSpeed Admin Dashboard";
        auth_basic_user_file /etc/nginx/htpasswd;
    }
    location /pagespeed_console {
        auth_basic "PageSpeed Admin Dashboard";
        auth_basic_user_file /etc/nginx/htpasswd;
    }
    location ~ ^/pagespeed_admin {
        auth_basic "PageSpeed Admin Dashboard";
        auth_basic_user_file /etc/nginx/htpasswd;
    }
    location ~ ^/pagespeed_global_admin {
        auth_basic "PageSpeed Admin Dashboard";
        auth_basic_user_file /etc/nginx/htpasswd;
    }
}
EOF
