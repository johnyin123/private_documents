#include "utils.h"
#include "const.h"
#define _ITEM(c, n)   [c] = #n,
const char *conn_state_map[] = { S_CONN_STATE(_ITEM) };
const size_t conn_state_map_len = ARRAY_LEN(conn_state_map);
#undef _ITEM
#define _ITEM(c, n)   [c] = #n,
const char *method_map[] = { S_METHOD(_ITEM) };
const size_t method_map_len = ARRAY_LEN(method_map);
#undef _ITEM
#define _ITEM(c, n)   [c] = #n,
const char *mime_map[] = { S_MIME_TYPE(_ITEM) };
const size_t mime_map_len = ARRAY_LEN(mime_map);
#undef _ITEM
#define _ITEM(c, n)   [c] = #n,
const char *http_code_map[] = { S_HTTP_CODE(_ITEM) };
const size_t http_code_map_len = ARRAY_LEN(http_code_map);
#undef _ITEM
