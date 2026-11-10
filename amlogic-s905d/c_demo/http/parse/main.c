#include <stdio.h>
#include <getopt.h>
#include <string.h>
#include <stdlib.h>
#include "utils.h"
struct env g_env = {
    .trace_level = LOG_ERR,
};
const char *opt_short="h";
struct option opt_long[] = {
    { "help",    no_argument, NULL, 'h' },
    { "version", no_argument, NULL, 256 }, /* values > 255 */
    { 0, 0, 0, 0 }
};
static void usage(const char *prog) {
    fprintf(stderr,
        "Usage: %s\n"
        "    -h|--help help\n"
        "    --version\n"
        , prog);
    exit(0);
}
static int parse_command_line(int argc, char **argv) {
    int opt, option_index;
    while ((opt = getopt_long(argc, argv, opt_short, opt_long, &option_index)) != -1) {
        switch (opt) {
            case 'h':
                usage(argv[0]);
                return 0;
            case 256:
                fprintf(stdout, "version\n");
                return 0;
            default:
                usage(argv[0]);
                return 1;
        }
    }
    return 0;
}
#include "http_parser.h"
#define MAX_HEADERS   8
#define HDR_KEY_LEN   16
#define HDR_VAL_LEN   256
struct conn_t {
    size_t bytes_parsed;
    struct req_line req;
    uint32_t hdr_count;
    struct http_header hdr[MAX_HEADERS];
    struct req_line_parser req_parser;
    struct http_headers_parser hdr_parser;
};

#define S_METHOD(X) \
    X(METHOD_NONE,     NONE) \
    X(METHOD_GET,      GET) \
    X(METHOD_POST,     POST) \
    X(METHOD_PUT,      PUT) \
    X(METHOD_DELETE,   DELETE) \
    X(METHOD_HEAD,     HEAD) \
    X(METHOD_OPTIONS,  OPTIONS) \
    X(METHOD_PATCH,    PATCH) \
    X(METHOD_TRACE,    TRACE) \
    X(METHOD_CONNECT,  CONNECT)

#define _ITEM(c, n)   c,
enum method_t     { S_METHOD(_ITEM) };
#undef _ITEM
#define _ITEM(c, n)   [c] = #n,
static const char *method_map[] = { S_METHOD(_ITEM) };
static const int method_map_len = ARRAY_LEN(method_map);
#undef _ITEM
#define METHOD_STR(c) code2str((c), method_map, method_map_len, "NONE")
static inline const char *code2str(const uint16_t code, const char *tbl[], const size_t len, const char *nodef) {
    if(code<len) {
        const char *s = tbl[code];
        if(s) return s;
    }
    return nodef;
}
static inline enum method_t http_method(const char *m, size_t len) {
    for(int i=0;i<method_map_len;i++) {
        const char *s = METHOD_STR(i);
        if(strlen(s)==len && memcmp(m, s, len)==0) return i;
    }
    return METHOD_NONE;
}
#include <limits.h>
#define CPY_MEM_STR(dst, dst_size, src, src_size) snprintf(dst, dst_size, "%.*s", (int)src_size, src)
void test() {
    const char *buf = "GET /abc/bcd?aaa=1&bbb=2 HTTP/1.1\r\n"
"Host: localhost:9999\r\n"
"User-Agent: curl/8.14.1\r\n"
"Accept: */*\r\n\r\n"
"message";
    size_t buf_len = strlen(buf);
    struct conn_t conn = { 0 };
    char req[PATH_MAX];
    int ret = parse_request_line(&conn.req_parser, &conn.req, &conn.bytes_parsed, buf, buf_len);
    if (ret == PARSE_OK) {
        CPY_MEM_STR(req, sizeof(req), conn.req.target, conn.req.target_size);
        log_debug("M(%s) %d.%d %s", METHOD_STR(http_method(conn.req.method, conn.req.method_size)), conn.req.httpver_major, conn.req.httpver_minor, req);
        ret = parse_headers(&conn.hdr_parser, conn.hdr, ARRAY_LEN(conn.hdr), &conn.hdr_count, &conn.bytes_parsed, buf+conn.bytes_parsed, buf_len - conn.bytes_parsed);
        if (ret == PARSE_OK) {
            for (uint32_t i=0;i<conn.hdr_count;i++) {
                char skey[HDR_KEY_LEN], sval[HDR_VAL_LEN];
                CPY_MEM_STR(skey, sizeof(skey), conn.hdr[i].name, conn.hdr[i].name_size);
                CPY_MEM_STR(sval, sizeof(sval), conn.hdr[i].value, conn.hdr[i].value_size);
                log_debug("    %s='%s'", skey, sval);
            }
        };
    }
}
int main(int argc, char *argv[]) {
    const char* e_val = getenv("TRACE");
    if (e_val) g_env.trace_level = atoi(e_val);
    parse_command_line(argc, argv);
    test();
    log_info("Exit");
    return 0;
}
