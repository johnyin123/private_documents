#define XSTR(s)       STR(s)
#define STR(s)        #s

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#define CONF_KEY_LEN  16
#define CONF_VAL_LEN  256
struct conf_kv_t {
    char key[CONF_KEY_LEN];
    char val[CONF_VAL_LEN];
};
static inline int __isspace(int c) { return (c==' '||c=='\t'||c=='\n'||c=='\v'||c=='\f'||c=='\r'); }
static inline void trim_end(char *s) {
    char *back = s + strlen(s);
    while(back > s && __isspace((unsigned char)*--back)) { *back = '\0'; }
}
static inline int get_conf(const char *appname, struct conf_kv_t *conf, size_t conf_len) {
    char buff[CONF_KEY_LEN + CONF_VAL_LEN];
    FILE* file;
    size_t pos = 0;
    snprintf(buff, sizeof(buff), "./%s.conf", appname);
    if(!(file=fopen(buff,"r"))) {
        snprintf(buff, sizeof(buff), "%s/%s.conf", getenv("HOME"), appname);
        if(!(file=fopen(buff,"r"))) {
            snprintf(buff, sizeof(buff), "/etc/%s.conf", appname);
            if(!(file=fopen(buff,"r"))) {
                fprintf(stderr, "Can't locate %s.conf: %s\n", appname, strerror(errno));
                exit(1);
            }
        }
    }
    while(fgets(buff,sizeof(buff),file)) {
        char *first_char = buff;
        while(__isspace((unsigned char)*first_char)) first_char++;
        if(*first_char == '#' || *first_char == '\0') continue;
        /*sscanf fmt skip blanks*/
        if(sscanf(buff, " %" XSTR(CONF_KEY_LEN) "[^ \r\n=] = %" XSTR(CONF_VAL_LEN) "[^\r\n]", conf[pos].key, conf[pos].val) == 2) {
            trim_end(conf[pos++].val);
        }
    }
    fclose(file);
    return pos;
}
/*
struct conf_kv_t myconf[32];
int ret = get_conf("app", myconf, ARRAY_LEN(myconf));
for(int i=0;i<ret;i++)
    fprintf(stderr, "CONF: %s = %s\n", myconf[i].key, myconf[i].val);
*/
