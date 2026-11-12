#include "utils.h"
#include "const.h"
#define _ITEM(c, n)   [c] = #n,
const char *conn_state[] = { S_CONN_STATE(_ITEM) };
const size_t conn_state_len = ARRAY_LEN(conn_state);
#undef _ITEM
#define _ITEM(c, n)   [c] = #n,
const char *method_map[] = { S_METHOD(_ITEM) };
const size_t method_map_len = ARRAY_LEN(method_map);
#undef _ITEM
#define _ITEM(c, n)   [c] = #n,
const char *http_status[] = { S_HTTP_CODE(_ITEM) };
const size_t http_status_len = ARRAY_LEN(http_status);
#undef _ITEM
#define _ITEM(c, n)   [c] = #n,
const char *mime_type[] = { S_MIME_TYPE(_ITEM) };
const size_t mime_type_len = ARRAY_LEN(mime_type);
#undef _ITEM

#include "main.h"
#define _ITEM(c, n)   [c] = METHOD_FUNC_##n,
const method_func_t method_funcs[] = { S_METHOD(_ITEM) };
const size_t method_funcs_len = ARRAY_LEN(method_funcs);
#undef _ITEM
