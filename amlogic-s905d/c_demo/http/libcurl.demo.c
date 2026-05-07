#include <curl/curl.h>
//const char *my_ca_buffer = "-----BEGIN CERTIFICATE-----\n"
//                       "-----END CERTIFICATE-----\n";
//struct curl_blob blob;
//blob.data = (void *)my_ca_buffer;
//blob.len = strlen(my_ca_buffer);
//blob.flags = CURL_BLOB_COPY; /* Use CURL_BLOB_COPY, buffer might be freed before the transfer completes*/
//curl_easy_setopt(curl, CURLOPT_CAINFO_BLOB, &blob);    /* Set the CA bundle from the memory blob*/

#define USERAGENT       "curl (Linux GCC) by johnyin"
enum method_t { HTTP_GET, HTTP_POST };
enum cont_type_t { POST_FORM=0, POST_JSON=1 };
static const char *s_content[] = { "Content-Type: application/x-www-form-urlencoded; charset=utf-8", "Content-Type: application/json; charset=utf-8" };
static inline const char *get_post_content(enum cont_type_t type) { return s_content[type]; }
int url_escape(const char *data, char *out, size_t out_size);
int fetch_url(enum method_t method, const char *url, const char *body, char *output, size_t output_size, enum cont_type_t post_type);
#define get_url(url, output, output_size) fetch_url(HTTP_GET, url, NULL, output, output_size, POST_FORM)
#define post_url(url, body, output, output_size, cont_type) fetch_url(HTTP_POST, url, body, output, output_size, cont_type)
struct url_t {
    char scheme[8];
    char user[32];
    char password[32];
    char options[64];
    char host[128];
    char port[8];
    char path[1024];
    char query[1024];
    char fragment[32];
};
#define URL_SCHEME_DEFAULT_PORT_MAP(X) \
    X("http",  "80")  \
    X("ws",    "80")  \
    X("https", "443") \
    X("wss",   "443") \
    X("ftp",   "21")
int split_url(const char *s_url, struct url_t *url);
/////////////////////////////////////////////////////////////////////////////
#include <stdlib.h>
#include <string.h>
#define log_debug(fmt,args...)
#define log_info(fmt,args...)
#define log_error(fmt,args...)

#define __PART_CPY(d, s) snprintf((d), sizeof(d), "%s", (s) ? (s) : "")
#define __PART_GET(p, v) do { if (curl_url_get(h, p, &v, 0)) v = NULL; } while (0)
#define __PART_FREE(p)   do { if (p) curl_free(p); } while (0)
static inline void set_default_port(struct url_t *u) {
    if (u->port[0]) return;
#define __DEFAULT_PORT(s, p) if (!strcmp(u->scheme, s)) { __PART_CPY(u->port, p); return; }
    URL_SCHEME_DEFAULT_PORT_MAP(__DEFAULT_PORT)
#undef __DEFAULT_PORT
}
int split_url(const char *s_url, struct url_t *url) {
    char *scheme, *user, *password, *options, *host, *port, *path, *query, *fragment;
    CURLU *h = curl_url();
    if(!h || !s_url || !url) return EXIT_FAILURE;
    memset(url, 0, sizeof(struct url_t));
    CURLUcode uc = curl_url_set(h, CURLUPART_URL, s_url, 0);
    if(uc != CURLUE_OK) {
        log_error("split url %s", curl_url_strerror(uc));
        curl_url_cleanup(h);
        return uc;
    }
    __PART_GET(CURLUPART_SCHEME, scheme);
    __PART_GET(CURLUPART_USER, user);
    __PART_GET(CURLUPART_PASSWORD, password);
    __PART_GET(CURLUPART_OPTIONS, options);
    __PART_GET(CURLUPART_HOST, host);
    __PART_GET(CURLUPART_PORT, port);
    __PART_GET(CURLUPART_PATH, path);
    __PART_GET(CURLUPART_QUERY, query);
    __PART_GET(CURLUPART_FRAGMENT, fragment);
    __PART_CPY(url->scheme, scheme);
    __PART_CPY(url->user, user);
    __PART_CPY(url->password, password);
    __PART_CPY(url->options, options);
    __PART_CPY(url->host, host);
    __PART_CPY(url->port, port);
    __PART_CPY(url->path, path);
    __PART_CPY(url->query, query);
    __PART_CPY(url->fragment, fragment);
    set_default_port(url);
    /* ensure path */
    /* if(!url->path[0]) strcpy(url->path, "/"); */
    __PART_FREE(scheme);
    __PART_FREE(user);
    __PART_FREE(password);
    __PART_FREE(options);
    __PART_FREE(host);
    __PART_FREE(port);
    __PART_FREE(path);
    __PART_FREE(query);
    __PART_FREE(fragment);
    curl_url_cleanup(h);
    return uc;
}
#undef __PART_CPY
#undef __PART_GET
#undef __PART_FREE
int url_escape(const char *data, char *out, size_t out_size) {
    CURL *curl = curl_easy_init();
    if (!curl) return -1;
    char *encoded = curl_easy_escape(curl, data, 0); // 0 = length calculated via strlen
    if(!encoded) return -2;
    if(strlen(encoded) >= out_size) return -3;
    strcpy(out, encoded);
    curl_free(encoded);
    curl_easy_cleanup(curl);
    return EXIT_SUCCESS;
}
struct buf_ctx_t { char *buf; size_t size; size_t used; };
static size_t write_cb(void *ptr, size_t size, size_t nmemb, void *userdata) {
    struct buf_ctx_t *ctx = (struct buf_ctx_t *)userdata;
    size_t total = size * nmemb;
    if (ctx->used + total >= ctx->size) total = ctx->size - ctx->used - 1; // keep space for '\0'
    if (total > 0) {
        memcpy(ctx->buf + ctx->used, ptr, total);
        ctx->used += total;
        ctx->buf[ctx->used] = '\0';
    }
    return size * nmemb;
}
int fetch_url(enum method_t method, const char *url, const char *body, char *output, size_t output_size, enum cont_type_t post_type) {
    if (!url || !output || output_size == 0) return -1;
    log_debug("%s %s BODY:[%s]", method==HTTP_GET ? "GET" : "POST", url, body ? body : "");
    CURL *curl = curl_easy_init();
    if (!curl) return -2;
    struct buf_ctx_t ctx = { .buf = output, .size = output_size, .used = 0 };
    output[0] = '\0';
    struct curl_slist *headers = NULL;
    if (method == HTTP_POST) headers = curl_slist_append(headers, get_post_content(post_type));
    curl_easy_setopt(curl, CURLOPT_URL, url);
    curl_easy_setopt(curl, CURLOPT_USERAGENT, USERAGENT);
    /* response handling */
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, write_cb);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, &ctx);
    // if(!g_cfg.ssl_verify) {
    //     curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, 0L);
    //     curl_easy_setopt(curl, CURLOPT_SSL_VERIFYHOST, 0L);
    // }
    /* networking behavior */
    curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
    // curl_easy_setopt(curl, CURLOPT_TIMEOUT, (long)g_cfg.TIMEOUT);
    // curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT, (long)g_cfg.TIMEOUT);
    if (method == HTTP_POST) {    /* POST setup */
        curl_easy_setopt(curl, CURLOPT_POST, 1L);
        curl_easy_setopt(curl, CURLOPT_POSTFIELDS, body);
        curl_easy_setopt(curl, CURLOPT_POSTFIELDSIZE, (long)strlen(body));
        curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
    }
    CURLcode res = curl_easy_perform(curl);
    if (res != CURLE_OK) {
        log_error("curl_easy_perform() failed: %s", curl_easy_strerror(res));
        if (method == HTTP_POST) curl_slist_free_all(headers);
        curl_easy_cleanup(curl);
        return -3;
    }
    long http_code = 0;
    curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &http_code);
    if (method == HTTP_POST) curl_slist_free_all(headers);
    curl_easy_cleanup(curl);
    if (http_code != 200)
        return (int)-http_code;
    log_debug("%s OUTPUT:[%s]", url, output);
    return (int)ctx.used;
}
