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
#include <limits.h>

#ifndef XSTR
#define XSTR(s)       STR(s)
#endif
#ifndef STR
#define STR(s)        #s
#endif
#ifndef CONFIG_EXT
#define CONFIG_EXT  ".conf"
#endif
#ifndef CONFIG_KLEN
#define CONFIG_KLEN  32
#endif
#ifndef CONFIG_VLEN
#define CONFIG_VLEN  512
#endif
struct conf_kv_t { char key[CONFIG_KLEN+1]; char val[CONFIG_VLEN+1]; };
static inline int __isspace(int c) { return (c==' '||c=='\t'||c=='\n'||c=='\v'||c=='\f'||c=='\r'); }
static inline char *trim(char *s) {
    while (__isspace((unsigned char)*s)) s++;
    char *end = s + strlen(s);
    while (end > s && __isspace((unsigned char)end[-1])) { *--end = '\0'; }
    return s;
}
#ifndef CONFIG_MMAP_CONF
static inline int get_conf(const char *appname, struct conf_kv_t *conf, size_t conf_len) {
    const char *dirs[] = { ".", getenv("HOME"), "/etc" };
    char buff[CONFIG_KLEN + CONFIG_VLEN + 32], path[PATH_MAX];
    FILE* file = NULL;
    int c;
    size_t rows = 0;
    if (!appname || !*appname || !conf || !conf_len) { return -1; }
    for (size_t i = 0; i < sizeof(dirs) / sizeof(dirs[0]); i++) {
        if (!dirs[i] || !*dirs[i]) continue;
        if (snprintf(path, sizeof(path), "%s/%s" CONFIG_EXT, dirs[i], appname) >= (int)sizeof(path)) continue;
        if ((file = fopen(path, "r")) != NULL) break;
    }
    if (!file) { return 0; /*exit(1);*/ }
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
        if(sscanf(p, " %" XSTR(CONFIG_KLEN) "[^ \r\n=] = %" XSTR(CONFIG_VLEN) "[^\r\n]", conf[rows].key, conf[rows].val) == 2) { rows++; }
    }
    fclose(file);
    return (int)rows;
}
#else
#include <fcntl.h>
#include <unistd.h>
#include <sys/mman.h>
#include <sys/stat.h>
static inline int get_conf(const char *appname, struct conf_kv_t *conf, size_t conf_len) {
    const char *dirs[] = { ".", getenv("HOME"), "/etc" };
    char path[PATH_MAX];
    struct stat sb;
    int fd = -1;
    if (!appname || !*appname || !conf || !conf_len) { return -1; }
    for (size_t i = 0; i < sizeof(dirs) / sizeof(dirs[0]); i++) {
        if (!dirs[i] || !*dirs[i]) continue;
        if (snprintf(path, sizeof(path), "%s/%s" CONFIG_EXT, dirs[i], appname) >= (int)sizeof(path)) continue;
        if ((fd = open(path, O_RDONLY)) != -1) break;
    }
    if (stat(path, &sb) == -1) { close(fd); return -1; }
    if (sb.st_size == 0) { close(fd); return -2; }
    char *file_mem = mmap(NULL, sb.st_size, PROT_READ|PROT_WRITE, MAP_PRIVATE, fd, 0);
    if (file_mem == MAP_FAILED) { close(fd); return -3; }
    close(fd);
    char *line, *running_buf = file_mem;
    size_t rows = 0;
    while (rows < conf_len && (line = strsep(&running_buf, "\n")) != NULL) {
        const char *p = trim(line);
        if(*p == '#' || *p == '\0') continue;
        /*sscanf fmt skip blanks*/
        if(sscanf(p, " %" XSTR(CONFIG_KLEN) "[^ \r\n=] = %" XSTR(CONFIG_VLEN) "[^\r\n]", conf[rows].key, conf[rows].val) == 2) { rows++; }
    }
    munmap(file_mem, sb.st_size);
    return (int)rows;
}
#endif
static inline bool conf_get(const struct conf_kv_t *conf, const size_t conf_len, const char *key, const char *scanfmt, void *dst) {
    for (size_t i=0;i<conf_len;i++) {
        if (strcasecmp(conf[i].key, key) == 0) {
            if (scanfmt) { sscanf(conf[i].val, scanfmt, dst); }
            else { *((const char**) dst) = conf[i].val; }
            return true;
        }
    }
    return false;
}
/*
    struct conf_kv_t myconf[20];
    int ret = get_conf("config", myconf, ARRAY_LEN(myconf));
    fprintf(stderr, "RET: %d\n", ret);
    if(ret > 0) {
        int port = 100;
        conf_get(myconf, ret, "port", "%d", &port);
        const char *name = "fule";
        conf_get(myconf, ret, "name", NULL, &name);
        // #include <inttypes.h>
        // int64_t  i64=1; "%" SCNd64, &i64
        // uint64_t u64=1; "%" SCNu64, &u64
        // fprintf(stderr, "%" PRId64 ",%" PRIu64 "\n", i64, u64);
    }
    return 0;
*/
#ifdef __cplusplus
}
#endif
#endif
