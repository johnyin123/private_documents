#include "fcgi_utils.h"
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <ctype.h>

struct env g_env = {
    .trace_level = 0,
};

#define _ITEM(c, n)   [c] = #n,
static const char *method_map[] = { S_METHOD(_ITEM) };
static const int method_map_len = ARRAY_LEN(method_map);
#define METHOD_STR(c) code2str((c), method_map, method_map_len, "NONE")
static const char *mime_type[] = { S_MIME_TYPE(_ITEM) };
static const int mime_type_len = ARRAY_LEN(mime_type);
#define MIME_STR(c)   code2str((c), mime_type, mime_type_len, "application/octet-stream")
#undef _ITEM
const char *code2str(const uint16_t code, const char *tbl[], const size_t len, const char *nodef) {
    if(code<len) {
        const char *s = tbl[code];
        if(s) return s;
    }
    return nodef;
}
enum method_t http_method(const char *m, size_t len) {
    for(int i=0;i<method_map_len;i++) {
        const char *s = METHOD_STR(i);
        if(strlen(s)==len && memcmp(m, s, len)==0) return i;
    }
    return METHOD_NONE;
}
const char* req_get_header(FCGX_Request *r, const char *key) {
    return FCGX_GetParam(key, r->envp);
}
const char* req_method(FCGX_Request *r) {
    return req_get_header(r, "REQUEST_METHOD");
}
const char* req_uri(FCGX_Request *r) {
    return req_get_header(r, "DOCUMENT_URI");
}
const char* req_query(FCGX_Request *r) {
    return req_get_header(r, "QUERY_STRING");
}
const char* req_cookie(FCGX_Request *r) {
    return req_get_header(r, "HTTP_COOKIE");
}
int req_content_length(FCGX_Request *r) {
    const char *len_str = req_get_header(r, "CONTENT_LENGTH");
    return len_str ? atoi(len_str) : 0;
}
bool query_get(const char *qs, const char *key, char *out, size_t out_sz) {
    if (!qs || !key || !out || out_sz == 0) return false;
    size_t key_len = strlen(key);
    const char *p = qs;
    while (*p) {
        if (strncmp(p, key, key_len) == 0 && p[key_len] == '=') {
            const char *val = p + key_len + 1;
            size_t i = 0;
            while (val[i] && val[i] != '&' && i < out_sz - 1) {
                out[i] = val[i];
                i++;
            }
            out[i] = '\0';
            return true;
        }
        while (*p && *p != '&') p++;
        if (*p == '&') p++;
    }
    return false;
}
static inline int hex(char c) {
    if ('0'<=c && c<='9') return c-'0';
    if ('a'<=c && c<='f') return c-'a'+10;
    if ('A'<=c && c<='F') return c-'A'+10;
    return -1;
}
void url_decode(char *s) {
    char *dst = s;
    while(*s) {
        if (*s == '%' &&
            isxdigit((unsigned char)s[1]) &&
            isxdigit((unsigned char)s[2])) {
            int hi = hex(s[1]);
            int lo = hex(s[2]);
            *dst++ = (char)((hi << 4) | lo);
            s += 3;
        } else if (*s == '+') {
            *dst++ = ' ';
            s++;
        } else {
            *dst++ = *s++;
        }
    }
    *dst = '\0';
}
int req_body(FCGX_Request *req, char *out, size_t out_len) {
    int len = req_content_length(req);
    if(len<=0||len>(int)out_len) return -1;
    return FCGX_GetStr(out, out_len, req->in);
}
void make_response(FCGX_Request *req, uint16_t status, enum mime_t mime, const char *format, ...) {
    va_list args;
    char json_str[BUF_SIZE]={0};
    va_start(args, format);
    int ret = vsnprintf(json_str, sizeof(json_str), format, args);
    va_end(args);
    if(ret < 0) return;
    size_t len = strlen(json_str);
    FCGX_FPrintF(req->out, "Status: %d\r\n"
        "%s\r\nContent-Type: %s\r\nContent-Length: %d\r\n"
        "\r\n"
        "%s", status, SRV_INFO, MIME_STR(mime), len, json_str);
}
bool get_cmd_output(const char* cmd, char *buf, size_t buf_len) {
    if(!buf || buf_len<=1) return false;
    FILE* pipe = popen(cmd, "r");
    if(!pipe) { buf[0] = '\0'; return false; }
    size_t n = fread(buf, 1, buf_len - 1, pipe);
    if(ferror(pipe)) n = 0;
    pclose(pipe);
    buf[n] = '\0';
    return (n>0);
}
bool starts_with(const char *str, const char *prefix) {
    return strncmp(str, prefix, strlen(prefix)) == 0;
}
bool ends_with(const char *str, const char *suffix) {
    if (!str || !suffix) return false;
    size_t lenstr = strlen(str);
    size_t lensuffix = strlen(suffix);
    if (lensuffix > lenstr) return false;
    // Use GCC __builtin_memcmp for optimization potential
    return __builtin_memcmp(str + lenstr - lensuffix, suffix, lensuffix) == 0;
}
bool read_file(const char *path, char *buf, size_t sz) {
    if(!buf || sz<=1) return false;
    FILE *f = fopen(path, "r");
    if(!f) { buf[0] = '\0'; return false; }
    size_t n = fread(buf, 1, sz - 1, f);
    if(ferror(f)) n = 0;
    fclose(f);
    buf[n] = '\0';
    return (n>0);
}
/* col1|col2|....| */
bool get_column(const char *src, int idx, char *out, size_t out_len, const char delm) {
    const char *start = src;
    const char *end;
    int current_col = 1;
    while (current_col < idx) {
        start = strchr(start, delm);
        if (!start) return false; /* out of bounds */
        start++;
        current_col++;
    }
    end = strchr(start, delm);
    size_t len = end ? (size_t)(end - start) : strlen(start);
    if(len >= out_len) len = out_len - 1;
    memcpy(out, start, len);
    out[len] = '\0';
    return true;
}
#ifdef UTIL_TEST_MAIN
/*----------------------------------------------------------------------------*/
struct env_t {
    int trace_level;
};
struct cfg_t {
    char ip[16];
    uint16_t port;
    char protocol[12];
    bool ssl_verify;
    struct env_t env;
};
extern struct cfg_t g_cfg;
/*----------------------------------------------------------------------------*/
//  X(TYPE, struct elem, json name,     decode func
#define ENV_JSON_TYPE_MAP(X)                     \
    X(INT,  trace_level, "trace_level", NULL)

#define CONFIG_JSON_TYPE_MAP(X)                  \
    X(STR,  ip,         "ip",         NULL)      \
    X(INT,  port,       "port",       NULL)      \
    X(STR,  protocol,   "protocol",   NULL)      \
    X(BOOL, ssl_verify, "ssl_verify", NULL)      \
    X(OBJ,  env,        "env",        env_decode)

struct cfg_t g_cfg = {
    .protocol   = "http",
    .ssl_verify = true,
    .env = { .trace_level = 112, },
};
static int env_decode(cJSON *json, struct env_t *env) {
    if (!json || !env) return EXIT_FAILURE;
    #define X(kind, name, key, dec_func) DECODE_STEP(json, env, kind, name, key, dec_func)
    ENV_JSON_TYPE_MAP(X)
    #undef X
    return EXIT_SUCCESS;
}
int cfg_decode(const char *json_string, struct cfg_t *cfg) {
    cJSON *json = cJSON_Parse(json_string);
    if (!json || !json_string || !cfg) return EXIT_FAILURE;
    #define X(kind, name, key, dec_func) DECODE_STEP(json, cfg, kind, name, key, dec_func)
    CONFIG_JSON_TYPE_MAP(X)
    #undef X
    cJSON_Delete(json);
    return EXIT_SUCCESS;
}
void cfg_dump(const char *s, struct cfg_t *cfg, FILE *fp) {
    fprintf(fp, "%s, Configuration Dump\n", s);
    fprintf(fp, "    %s: %s\n", "ip", cfg->ip);
    fprintf(fp, "    %s: %d\n", "port", cfg->port);
    fprintf(fp, "    %s: %s\n", "protocol", cfg->protocol);
    fprintf(fp, "    %s: %s\n", "ssl_verify", cfg->ssl_verify ? "true":"false");
    fprintf(fp, "    %s:\n", "env");
    fprintf(fp, "        %s: %d\n", "trace_level", cfg->env.trace_level);
    fflush(fp);
}
int main() {
    const char *src="{\"ip\":\"127.0.0.1\",\"port\":9999, \"protocol\":\"https\", \"env\":{ \"trace_level\":8888 } }";
    cfg_dump("Before DECODE", &g_cfg, stderr);
    cfg_decode(src, &g_cfg);
    cfg_dump("After DECODE", &g_cfg, stderr);
}
#endif
