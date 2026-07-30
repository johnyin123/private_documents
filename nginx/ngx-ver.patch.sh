cat <<'EOD' | patch -p0
--- src/http/ngx_http_header_filter_module.c       2019-08-13 14:51:43.000000000 +0200
+++ src/http/ngx_http_header_filter_module.c       2020-03-31 02:08:18.160487422 +0200
@@ -279,7 +279,7 @@

     clcf = ngx_http_get_module_loc_conf(r, ngx_http_core_module);

-    if (r->headers_out.server == NULL) {
+    if (0 == 1) {
         if (clcf->server_tokens == NGX_HTTP_SERVER_TOKENS_ON) {
             len += sizeof(ngx_http_server_full_string) - 1;

@@ -448,7 +448,7 @@
     }
     *b->last++ = CR; *b->last++ = LF;

-    if (r->headers_out.server == NULL) {
+    if (0 == 1) {
         if (clcf->server_tokens == NGX_HTTP_SERVER_TOKENS_ON) {
             p = ngx_http_server_full_string;
             len = sizeof(ngx_http_server_full_string) - 1;


EOD
cd "${NGINX_PACKAGE_DIR}"
cat <<'EOD' | patch -p0
--- src/http/v2/ngx_http_v2_filter_module.c     2020-03-31 04:26:34.815493201 +0200
+++ src/http/v2/ngx_http_v2_filter_module.c     2020-03-31 04:27:56.871878980 +0200
@@ -259,7 +259,7 @@

     clcf = ngx_http_get_module_loc_conf(r, ngx_http_core_module);

-    if (r->headers_out.server == NULL) {
+    if (0 == 1) {

         if (clcf->server_tokens == NGX_HTTP_SERVER_TOKENS_ON) {
             len += 1 + nginx_ver_len;
@@ -463,7 +463,7 @@
         pos = ngx_sprintf(pos, "%03ui", r->headers_out.status);
     }

-    if (r->headers_out.server == NULL) {
+    if (0 == 1) {

         if (clcf->server_tokens == NGX_HTTP_SERVER_TOKENS_ON) {
             ngx_log_debug1(NGX_LOG_DEBUG_HTTP, fc->log, 0,
EOD
