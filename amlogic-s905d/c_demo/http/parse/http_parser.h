#ifndef __HTTP_PARSER_H_101839_224011826__INC__
#define __HTTP_PARSER_H_101839_224011826__INC__
#ifdef __cplusplus
extern "C" {
#endif

#ifdef HAVE_CONFIG_H
#  include "config.h"
#endif

#include <stddef.h>
#include <stdint.h>
struct req_line {
    const char *method;
    size_t method_size;
    const char *target;
    size_t target_size;
    int httpver_major;
    int httpver_minor;
};
struct status_line {
    int status_code;
    const char *reason;
    size_t reason_size;
    int httpver_major;
    int httpver_minor;
};
struct http_header {
    const char *name;
    size_t name_size;
    const char *value;
    size_t value_size;
};
struct req_line_parser {
    int state;
    const char *p, *m;
};
struct status_line_parser {
    int state;
    const char *p, *m;
};
struct http_headers_parser {
    int state;
    const char *p;
    const char *nm, *vm;
    size_t ns;
};
/* RFC5234 core rules refered by RFC7230 */
static inline int is_digit(char c) { return c >= '0' && c <= '9'; }
static inline int is_vchar(char c) { return c >= '\x21' && c <= '\x7e'; }
static inline int is_whitespace(char c) { return c == ' ' || c == '\t'; }
/* Common syntax components */
static inline int is_delimiters(char c) {
    return c == '(' || c == ')' || c == ',' || c == '/'
        || c == ':'  || c == ';' || c == '<' || c == '='
        || c == '>'  || c == '?' || c == '@' || c == '['
        || c == '\\' || c == ']' || c == '{' || c == '}'
        || c == '"';
}
static inline int is_tchar(char c) { return is_vchar(c) && !is_whitespace(c) && !is_delimiters(c); }
static inline int is_obs_text(char c) { return c < 0; }
/* #define STREQU5(A, B) (strncmp(A, B, 5) == 0) */
#define STREQU5(A, B) ((A[0] == B[0]) && (A[1] == B[1]) && (A[2] == B[2]) && (A[3] == B[3]) && (A[4] == B[4]))

enum { PARSE_OK = 0, PARSE_CONTINUE, PARSE_BAD_REQ, PARSE_INVALID, };
int parse_request_line(struct req_line_parser *parser, struct req_line *l, size_t *bytes_scanned, const char *input, size_t input_size);
int parse_status_line(struct status_line_parser *parser, struct status_line *l, size_t *bytes_scanned, const char *input, size_t input_size);
int parse_headers(struct http_headers_parser *parser, struct http_header headers[], uint32_t headers_count, uint32_t *headers_filled, size_t *bytes_scanned, const char *input, size_t input_size);
#ifdef __cplusplus
}
#endif
#endif
