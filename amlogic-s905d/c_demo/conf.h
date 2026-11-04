#ifndef __CONF_H_133255_1078767780__INC__
#define __CONF_H_133255_1078767780__INC__
#ifdef __cplusplus
extern "C" {
#endif

#ifdef HAVE_CONFIG_H
#  include "config.h"
#endif

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <limits.h>

#ifndef XSTR
#define XSTR(s)       STR(s)
#endif
#ifndef STR
#define STR(s)        #s
#endif
#ifndef CONF_KEY_LEN
#define CONF_KEY_LEN  32
#endif
#ifndef CONF_VAL_LEN
#define CONF_VAL_LEN  512
#endif
struct conf_kv_t {
    char key[CONF_KEY_LEN];
    char val[CONF_VAL_LEN];
};
static inline int __isspace(int c) { return (c==' '||c=='\t'||c=='\n'||c=='\v'||c=='\f'||c=='\r'); }
static inline char *trim(char *s) {
    while (__isspace((unsigned char)*s)) s++;
    char *end = s + strlen(s);
    while (end > s && __isspace((unsigned char)end[-1])) { *--end = '\0'; }
    return s;
}
static inline int get_conf(const char *appname, struct conf_kv_t *conf, size_t conf_len) {
    char buff[CONF_KEY_LEN + CONF_VAL_LEN + 8], path[PATH_MAX];
    FILE* file;
    int c;
    size_t rows = 0;
    if (!appname || !*appname || !conf || !conf_len) { return -1; }
    if (snprintf(path, sizeof(path), "./%s.conf", appname) >= (int)sizeof(path)) { return -2; }
    if(!(file=fopen(path, "r"))) {
        if (snprintf(path, sizeof(path), "%s/%s.conf", getenv("HOME") ? getenv("HOME") : "/etc", appname) >= (int)sizeof(path)) { return -3; }
        if(!(file=fopen(path,"r"))) {
            if (snprintf(path, sizeof(path), "/etc/%s.conf", appname) >= (int)sizeof(path)) { return -4; }
            if(!(file=fopen(buff,"r"))) {
                fprintf(stderr, "Can't locate %s.conf: %s\n", appname, strerror(errno));
                exit(1);
            }
        }
    }
    while(rows < conf_len && fgets(buff,sizeof(buff),file)) {
        /* Skip incomplete lines */
        size_t len = strlen(buff);
        if (len && buff[len - 1] != '\n' && !feof(file)) {
            while ((c = fgetc(file)) != '\n' && c != EOF);
            continue;
        }
        const char *p = trim(buff);
        if(*p == '#' || *p == '\0') continue;
        /*sscanf fmt skip blanks*/
        if(sscanf(buff, " %" XSTR(CONF_KEY_LEN) "[^ \r\n=] = %" XSTR(CONF_VAL_LEN) "[^\r\n]", conf[rows].key, conf[rows].val) == 2) {
            trim(conf[rows++].val);
        }
    }
    fclose(file);
    return (int)rows;
}
/*
    struct conf_kv_t myconf[20];
    int ret = get_conf("config", myconf, ARRAY_LEN(myconf));
    fprintf(stderr, "RET: %d\n", ret);
    for(int i=0;i<ret;i++)
        fprintf(stderr, "CONF: %s = %s||\n", myconf[i].key, myconf[i].val);
    return 0;
*/
#ifdef __cplusplus
}
#endif
#endif
