# Use Nginx as SMTP proxy

## Backgournd
SMTP proxy would help us lots in MTA management. we can use it to 
* Doing authentication
* Load balancing
* Failover
* MTA routing
* Implement traffic control

Add a proxy layer will very helpful especially when managing a huge MTA clusters, the proxy will significantly increase the flexibility of cluster.

## Nginx
Well know http server, proxy, load balancer. A standard in modern C network programming.

### Archietecture
``` mermaid
graph LR
  N[Nginx proxy] --> MTA1
  N --> MTA2
  N --> MTAn
  N -->|Auth| A[Auth server]
  A -->|Result| N
  
```

### Configuration
```
mail {
    server_name       mail.example.com;
    auth_http         127.0.0.1:18080/auth;

    #smtp_auth         login plain cram-md5;
    smtp_auth         login plain;
    smtp_capabilities "SIZE 10485760" ENHANCEDSTATUSCODES 8BITMIME DSN;
    xclient           off;

    server {
        listen   20025;
        protocol smtp;
    }
}
```

## Authentication server
Nginx mail module rely on a http api to implement flexibility. Check this [document](https://nginx.org/en/docs/mail/ngx_mail_auth_http_module.html) for detail.

## Implementation

### Authentication server
* Use Nginx it self as authentication server
  * Extremely high performance
  * Can use the same Nginx instant in simply deployment

* Keep user / password as js code to maximize performance
  * Password in js file should be hashed
  * Can use [redis2-nginx-module](https://github.com/openresty/redis2-nginx-module) or [drizzle-nginx-module](https://github.com/openresty/drizzle-nginx-module) to store the user / password pair in database

### Compile
``` bash
wget https://nginx.org/download/nginx-1.19.1.tar.gz
wget https://www.openssl.org/source/openssl-1.1.1g.tar.gz
wget https://zlib.net/zlib-1.2.11.tar.gz
wget https://ftp.pcre.org/pub/pcre/pcre-8.44.tar.gz

git clone https://github.com/openresty/echo-nginx-module.git
git clone https://github.com/openresty/redis2-nginx-module.git
git clone https://github.com/nginx/njs.git


export PROXY_PREFIX=/path/to/proxy

./configure --with-mail --with-mail_ssl_module --prefix=$PROXY_PREFIX/proxy \
--with-pcre=$PROXY_PREFIX/pcre-8.44/ \
--with-openssl=$PROXY_PREFIX/openssl-1.1.1g/ \
--with-zlib=$PROXY_PREFIX/zlib-1.2.11/ \
--add-module=$PROXY_PREFIX/njs/nginx/ \
--add-module=$PROXY_PREFIX/echo-nginx-module/ \
--add-module=$PROXY_PREFIX/redis2-nginx-module/
make && make install

```
### Nginx
```
http {
    include       mime.types;
    default_type  application/octet-stream;

    js_import http.js;

    server {
        listen       18080;
        server_name  localhost;

        location /auth {
            js_content http.auth;
        }
    }
}
```
### njs
njs is Nginx implementation of ECMAScript 5.1, it aims to become the default script engine in Nginx.
Official document descript it as `"njs is a subset of the JavaScript language that allows extending nginx functionality"`.

#### user.js
``` javascript
export default {get_user}

var user = {
    'test': { 'password': '1234', 'server': '127.0.0.1', 'port': '10025' },
    'test2': { 'password': 'password', 'server': '127.0.0.1', 'port': '10025' }
};

function get_user() {
    return user;
}
```

#### http.js
``` javascript
import user_lib from 'user.js';
var user = user_lib.get_user();

function hello(r) {
    r.return(200, "Hello njs world!\n");
}

function auth(r) {
    r.log(r.headersIn['Auth-User']);
    r.log(r.headersIn['Auth-Pass']);

    r.headersOut['Auth-Status'] = 'Bad auth';

    if ('Auth-Salt' in r.headersIn) {
        r.log(r.headersIn['Auth-Salt']);
    }
    if (r.headersIn['Auth-Method'] == 'plain') {
        if (r.headersIn['Auth-User'] in user && user[r.headersIn['Auth-User']]['password'] == r.headersIn['Auth-Pass']) {
            r.log('plain ok');
            r.headersOut['Auth-Status'] = 'OK';
            r.headersOut['Auth-Server'] = '127.0.0.1';
            r.headersOut['Auth-Port'] = '10025';
        }
    } else if (r.headersIn['Auth-Method'] == 'cram-md5') {
        if (r.headersIn['Auth-User'] in user) {
            var pass = user[r.headersIn['Auth-User']]['password'];
            var h = require('crypto').createHmac('md5', pass);
            var d = h.update(r.headersIn['Auth-Salt']).digest('hex');
            r.log(d);
            if (d == r.headersIn['Auth-Pass']) {
                r.log('cram-md5 ok');
                r.headersOut['Auth-Status'] = 'OK';
                r.headersOut['Auth-Server'] = '127.0.0.1';
                r.headersOut['Auth-Port'] = '10025';
            }
        }
    }

    r.return(200);
}

export default {hello, auth};
```
### Cram-md5 && apop
These two SASL share the same machanism, cram-md5 usually used in SMTP protocol, while apop used in pop3.

Authenticate in cram-md5 for authentication server is easy but undocument. Nginx provide us a easy interface.
What we need to do is use hmac-md5 to hash `Auth-Salt` with "password for current user" as password.
Use the hash result to compare with `Auth-Pass`

## Reference
* https://docs.nginx.com/nginx/admin-guide/mail-proxy/mail-proxy
* https://nginx.org/en/docs/mail/ngx_mail_core_module.html
* https://nginx.org/en/docs/mail/ngx_mail_auth_http_module.html
* https://nginx.org/en/docs/njs/reference.html
* https://en.wikipedia.org/wiki/CRAM-MD5
* https://github.com/xeioex/njs-examples
