#ifndef __CONST_H_125937_2249162611__INC__
#define __CONST_H_125937_2249162611__INC__
#ifdef __cplusplus
extern "C" {
#endif

#ifdef HAVE_CONFIG_H
#  include "config.h"
#endif

#define S_CONN_STATE(X) \
    X(ST_NONE,   NONE)  \
    X(ST_HEAD,   HEAD)  \
    X(ST_PROP,   PROP)  \
    X(ST_BODY,   BODY)  \
    X(ST_RESP,   RESP)  \
    X(ST_CLOSE,  CLOSE)
extern const char *conn_state[];
extern const int conn_state_len;
#define STATE_STR(c)  (const char *)code2ptr((c), (const void **)(const void **)conn_state, conn_state_len, "N/A")
#define _ITEM(c, n)   c,
enum conn_state_t { S_CONN_STATE(_ITEM) };
#undef _ITEM

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
extern const int method_map_len;
extern const char *method_map[];
#define METHOD_STR(c) (const char *)code2ptr((c), (const void **)method_map, method_map_len, "NONE")
#define _ITEM(c, n)   c,
enum method_t     { S_METHOD(_ITEM) };
#undef _ITEM

#define S_HTTP_CODE(X) \
    X(100,      Continue) \
    X(200,      OK) \
    X(400,      Bad Request) \
    X(403,      Forbidden) \
    X(404,      Not Found) \
    X(405,      Method Not Allowed) \
    X(406,      Not Acceptable) \
    X(413,      Request Entity Too Large) \
    X(414,      Request-URI Too Long) \
    X(500,      Internal Server Error) \
    X(501,      Not Implemented) \
    X(503,      Service Unavailable) \
    X(505,      HTTP Version not supported)
extern const char *http_status[];
extern const int http_status_len;
#define STATUS_STR(c) (const char *)code2ptr((c), (const void **)http_status, http_status_len, "No Defined")
#define _ITEM(c, n)   HTTP_##c = c,
enum http_code_t  { S_HTTP_CODE(_ITEM) };
#undef _ITEM

#define S_MIME_TYPE(X) \
    X(MIME_BIN,       application/octet-stream) \
    X(MIME_JSON,      application/json) \
    X(MIME_TEXT,      text/plain; charset=utf-8)
extern const char *mime_type[];
extern const int mime_type_len;
#define MIME_STR(c)   (const char *)code2ptr((c), (const void **)mime_type, mime_type_len, "application/octet-stream")
#define _ITEM(c, n)   c,
enum mime_t       { S_MIME_TYPE(_ITEM) };
#undef _ITEM

static inline const void *code2ptr(const uint16_t code, const void *tbl[], const size_t tbl_len, void *nodef) {
    const void *s = nodef;
    if(code<tbl_len) { s = tbl[code]; }
    return s;
}
#include <string.h>
static inline enum method_t http_method(const char *m, size_t len) {
    for(int i=0;i<method_map_len;i++) {
        const char *s = METHOD_STR(i);
        if(strlen(s)==len && memcmp(m, s, len)==0) return i;
    }
    return METHOD_NONE;
}
#ifdef __cplusplus
}
#endif
#endif
