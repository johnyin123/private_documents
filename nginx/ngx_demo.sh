#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("95064e0[2021-12-17T06:58:32+08:00]:ngx_demo.sh")

set -o errtrace
set -o nounset
set -o errexit

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
cat <<'EOF' >rtmp_live_modules.conf
# # stream ssl -> rmtp -> rmtps
# # add blow to /etc/nginx/modules.conf
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
cat <<'EOF' >rtmp_live.conf
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
        add_header Cache-Control no-cache;
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
cat <<'EOF' >static_dynamic.conf
server {
    listen 80 reuseport;
    server_name _;
    # serve static files
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
cat <<'EOF' >limit_speed.conf
limit_speed_zone mylimitspeed $binary_remote_addr 10m;
server {
    listen 80 reuseport;
    server_name _;
    location = /favicon.ico { access_log off; log_not_found off; }
    location / {
        limit_speed mylimitspeed 100k;
        # limit_rate_after 5m; #下载了5M以后开始限速
        # limit_rate 100k;
        root /var/www;
    }
}
EOF
cat <<'EOF' >check_nofiles.ngx.sh
ps --ppid $(cat /var/run/nginx.pid) -o %p|sed '1d'|xargs -I{} cat /proc/{}/limits|grep open.files
EOF
cat <<'EOF' >redis.conf
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
cat <<'EOF' >traffic_status.conf
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
cat <<'EOF' > limit_conn.conf
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
cat <<'EOF' > limit_req.conf
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
cat <<'EOF' > auth_basic.conf
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
cat <<'EOF' > secure_link_cookie.conf
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
cat <<'EOF' > webdav.conf
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
    listen 8000 reuseport;
    server_name _;
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
cat <<'EOF' > mirror.conf
server {
    listen 80 reuseport;
    server_name _;
    location / {
        mirror /mirror;
        mirror_request_body off;
        proxy_pass http://127.0.0.1:82;
    }
    location = /mirror {
        internal;
        proxy_pass http://127.0.0.1:81;
        proxy_pass_request_body off;
        proxy_set_header Content-Length "";
        proxy_set_header X-Original-URI $request_uri;
    }
}
EOF
cat <<'EOF' > memory_cached.conf
server {
    listen 80 reuseport;
    server_name _;
    location / {
        set $memcached_key "$uri?$args";
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
cat <<'EOF' > ab_test.conf
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
cat <<'EOF' > split_client.conf
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
    listen 80 reuseport;
    server_name _;
    location / {
        index index${variant}.html;
        root /var/www;
    }
}
EOF
cat <<'EOF' > auth_request_by_secure_link.conf
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
cat <<'EOF' > s3_list_xslt.conf
upstream ceph_rgw_backend {
    server 192.168.168.131:80;
    keepalive 64;
}
server {
    listen 80 reuseport;
    server_name _;
    location / {
        proxy_redirect off;
        # header_more module remove x-amz-request-id
        more_clear_headers 'x-amz*';
        # OR
        # #remove x-amz-request-id
        # proxy_hide_header x-amz-request-id;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        # #Stops the local disk from being written to (just forwards data through)
        # proxy_max_temp_file_size 0;

        # Apply XSL transformation to the XML returned from S3 directory listing
        xslt_stylesheet /etc/nginx/http-available/s3_list.xsl;
        xslt_types application/xml;

        proxy_pass http://ceph_rgw_backend/public-bucket$uri;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
    }
}
EOF
cat <<'EOF' > s3_list.xsl
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
cat <<'EOF' > aws_s3auth.conf
# njs s3: git clone https://github.com/nginxinc/nginx-s3-gateway.git
# public-bucket MUST set bucket-policy.py to all read/write
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
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_hide_header x-amz-request-id;
        proxy_hide_header x-rgw-object-type;
        # #Stops the local disk from being written to (just forwards data through)
        # proxy_max_temp_file_size 0;
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
cat <<'EOF' > post_redirect.conf
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
cat <<'EOF' > x_accel.conf
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
cat <<'EOF' > js_test.conf
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
cat <<'EOF' >shorturl.conf
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
                r.return(res.status);
                return;
            }
            if (res.responseBody != r.variables.arg_code) {
                r.return(403, "code error");
                return;
            }
            r.internalRedirect('/download' + r.uri);
        }
    )
}
EOF
cat <<'EOF' >download_code.conf
# http_js_module & http_redis_module
# redis-cli -x set /public-bucket/fu 9901 [EX seconds]
# curl http//127.0.0.1/public-bucket/fu?code=xxxx
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
    location / {
        js_content download.check;
    }
    location /redis {
        internal;
        set $redis_key "$arg_key";
        redis_pass 127.0.0.1:6379;
    }
    location ~ /download/(.*) {
        internal;
        proxy_redirect off;
        proxy_set_header X-Forwarded-For $remote_addr;
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
cat <<'EOF' > secure_link_hash.conf
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
cat <<'EOF' > serve_static_rest_backend.conf
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
cat <<'EOF' > resolver.conf
server {
    listen 80 reuseport;
    server_name _;
    location ~ /to/(.*) {
        resolver 127.0.0.1;
        proxy_set_header Host $1;
        proxy_pass http://$1;
    }
    location /proxy {
        resolver 127.0.0.1;
        set $target http://proxytarget.example.com;
        proxy_pass $target;
    }
}
EOF
cat <<'EOF' > reverse_proxy_cache_split.conf
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
        proxy_cache_valid any 30m;
        proxy_cache_methods GET HEAD POST;
        # proxy_cache_bypass $cookie_nocache $arg_nocache;
        proxy_pass http://127.0.0.1:9999;
    }
}
EOF
cat <<'EOF' > reverse_proxy_cache.conf
# ngx does not cache responses if proxy_buffering is set to off. It is on by default.
# 1MB keys_zone can store data for about 8000 keys
proxy_cache_path /usr/share/nginx/cache levels=1:2 keys_zone=STATIC:10m inactive=24h max_size=1g;
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
        expires $expires;
        add_header Cache-Control $control;
        # # Hidden / Pass X-Powered-By to client
        # proxy_hide_header X-Powered-By;
        # proxy_pass_header X-Powered-By;
        # #Disables processing of certain response header fields from the proxied server.
        # proxy_ignore_headers Cache-Control Expires Vary;
        # proxy_cache_bypass $cookie_nocache $arg_nocache $http_pragma;
        # proxy_cache_methods GET HEAD POST;
        # proxy_cache_key $proxy_host$request_uri$cookie_jessionid;
        proxy_pass http://127.0.0.1:9999;
        proxy_set_header Host $host;
        proxy_buffering on;
        proxy_cache STATIC;
        proxy_cache_valid 200 302 1d;
        proxy_cache_valid 404 1h;
        proxy_cache_use_stale error timeout invalid_header updating http_500 http_502 http_503 http_504;
    }
}
EOF
cat <<'EOF' > cache_static.conf
server {
    listen 80 reuseport;
    server_name _;
    location ~* \.(?:ico|css|js|gif|jpe?g|png)$ {
        expires 30d;
        add_header Vary Accept-Encoding;
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
cat <<'EOF' > cros.conf
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
cat <<'EOF' > error_page.conf
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
cat <<'EOF' > websocket.conf
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
    }
}
EOF
cat <<'EOF' >addition.conf
server {
    listen 80 reuseport;
    server_name _;
    location / {
        empty_gif;
    }
    location /b.html {
        add_before_body /add_before;
        return 200 "body";
    }
    location /a.html {
        add_after_body /add_after;
        return 200 "body";
    }
    location /add_before {
        return 200 "before";
    }
    location /add_after {
        return 200 "after";
    }
}
EOF
cat <<'EOF' > sub_filter.conf
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
cat <<'EOF' > header.conf
# copy this file to /etc/nginx/http-conf.d/
# need headers-more-nginx-module
# hidden Server: nginx ...
more_set_headers 'Server: my-server';
# # OR
# proxy_pass_header Server;
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
access_log /var/log/nginx/access_debug.log access_debug if=$is_error;
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
