#include <stdio.h>
#include <string.h>
#define PCRE2_CODE_UNIT_WIDTH 8
#include <pcre2.h>
#include "http_regex.h"

struct RegexMatches {
    int nmatch;
    char *match[256];
    pcre2_code *re;
    pcre2_match_data *match_data; // Replaces pcre_extra and manual ovector
};
int getMatchsNum(regex _rm) {
    struct RegexMatches *rm = (struct RegexMatches*)_rm;
    return rm->nmatch;
}
const char* getMatchs(regex _rm, int idx) {
    struct RegexMatches *rm = (struct RegexMatches*)_rm;
    if(idx > rm->nmatch)
        return NULL;
    return rm->match[idx];
}
void regexdump(regex _rm, int fd) {
    struct RegexMatches *rm = (struct RegexMatches*)_rm;
    for(int i=0;i<getMatchsNum(rm);i++) dprintf(fd, "%d: [%s]\n", i, getMatchs(rm, i));
}
int regexnew(const char* pattern, regex* _rm) {
    struct RegexMatches **rm = (struct RegexMatches **)_rm;
    int errornumber;
    PCRE2_SIZE erroroffset;
    uint32_t options = PCRE2_DOTALL | PCRE2_MULTILINE;
    pcre2_code *re = pcre2_compile((PCRE2_SPTR)pattern, PCRE2_ZERO_TERMINATED, options, &errornumber, &erroroffset, NULL);
    if (re == NULL) {
        PCRE2_UCHAR buffer[256];
        pcre2_get_error_message(errornumber, buffer, sizeof(buffer));
        // debugln("PCRE2 compile failed at %d: %s\n", (int)erroroffset, buffer);
        return -1;
    }
    *rm = malloc(sizeof(struct RegexMatches));
    memset(*rm, 0, sizeof(struct RegexMatches));
    (*rm)->re = re;
    (*rm)->match_data = pcre2_match_data_create_from_pattern(re, NULL);
    return 1;
}
int regexfree(regex _rm) {
    struct RegexMatches *rm = (struct RegexMatches*)_rm;
    for(int i = 0; i < rm->nmatch; i++) {
        if(rm->match[i]) free(rm->match[i]);
    }
    pcre2_code_free(rm->re);
    pcre2_match_data_free(rm->match_data);
    free(rm);
    return 1;
}
int regexmatch(const char* subject, int subject_len, regex _rm) {
    struct RegexMatches *rm = (struct RegexMatches*)_rm;
    int rc = pcre2_match(rm->re, (PCRE2_SPTR)subject, subject_len, 0, 0, rm->match_data, NULL);
    if (rc < 0) {
        //if (rc != PCRE2_ERROR_NOMATCH) 
        //    debugln("PCRE2 matching error %d\n", rc);
        return -1;
    }
    PCRE2_SIZE *ovector = pcre2_get_ovector_pointer(rm->match_data);
    for (int i=1; i<rc && rm->nmatch<256; i++) {
        PCRE2_SIZE start = ovector[2*i];
        PCRE2_SIZE end = ovector[2*i+1];
        if (start == PCRE2_UNSET) continue;
        size_t len = end - start;
        rm->match[rm->nmatch] = malloc(len + 1);
        if (rm->match[rm->nmatch]) {
            memcpy(rm->match[rm->nmatch], subject + start, len);
            rm->match[rm->nmatch][len] = '\0';
            rm->nmatch++;
        }
    }
    // Return end of match for pointer advancement
    return (int)ovector[1];
}
void static regexreset(regex _rm) {
    struct RegexMatches *rm = (struct RegexMatches*)_rm;
    for(int i=0;i<rm->nmatch;i++) {
        if(rm->match[i] != NULL) {
            free(rm->match[i]);
            rm->match[i] = 0;
        }
    }
    rm->nmatch = 0;
}

struct regex_operator Regex = {
    .length = getMatchsNum,
    .get = getMatchs,
    .dump = regexdump,
    .alloc = regexnew,
    .free = regexfree,
    .match = regexmatch,
    .reset = regexreset,
};
#ifdef TEST
const char *msg = "GET /a HTTP/1.1\r\nHost: localhost:8880\r\nUser-Agent: Mozilla/5.0 (X11; U; Linux i686; zh-CN; rv:1.9.2.8) Gecko/20100722 Firefox/3.6.8\r\nAccept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8\r\nAccept-Language: zh-cn,zh;q=0.5\r\nAccept-Encoding: gzip,deflate\r\nAccept-Charset: GB2312,utf-8;q=0.7,*;q=0.7\r\nKeep-Alive: 115\r\nConnection: keep-alive\r\n\r\n";

int main(int argc, char *argv[]) {
    const char* req_pattern = "(GET|PUT|POST|OPTIONS|HEAD|DELETE|TRACE) ([/a-zA-Z%0-9]+) (HTTP/)(\\d.\\d)\\r\\n";
    const char* hdr_pattern = "([a-zA-Z0-9-]+): ([^\\r\\n]*)\\r\\n";
    const char *subject = msg;
    int subjectlen, retval;
    regex method_line, header_line;
    if ((retval= Regex.alloc(req_pattern, &method_line))<0) return 1;
    if ((retval = Regex.alloc(hdr_pattern, &header_line))<0) return 1;
    retval = Regex.match(subject, strlen(subject), method_line);
    if(retval > 0) {
        subject += retval;
        subjectlen = strlen(subject);
        while((subject < (msg + strlen(msg)))&&(retval = Regex.match(subject, subjectlen, header_line))>0) {
            subject += retval;
            subjectlen = strlen(subject);
        }
        Regex.dump(method_line, 2);
        Regex.dump(header_line, 2);
    }
    if (Regex.length(method_line) == 4) {
        const char* method = Regex.get(method_line, 0);
        const char* uri = Regex.get(method_line, 1);
        const char* version = Regex.get(method_line, 3);
        printf("found %s: %s: %s\n", method, uri, version);
        for(int i=0;i<Regex.length(header_line);i+=2) {
            const char* key = Regex.get(header_line, i);
            const char* val = Regex.get(header_line, i+1);
            printf("found %s: %s\n", key, val);
        }
    }
    Regex.free(method_line);
    Regex.free(header_line);
    return 1;
}
int main(int argc, char *argv[]) {
    const char* req_pattern = "^(GET|PUT|POST|HEAD) ([/a-zA-Z%0-9]+) HTTP/(\\d\\.\\d)\\r\\n([\\s\\S]*\\r\\n?)\\r\\n";
    const char *subject = msg;
    int retval;
    regex request;
    if ((retval = Regex.alloc(req_pattern, &request))<0) return 1;
    if ((retval = Regex.match(subject, strlen(subject), request)) > 0) {
        if (4 == Regex.length(request)) {
            const char* method = Regex.get(request, 0);
            const char* uri = Regex.get(request, 1);
            const char* version = Regex.get(request, 2);
            //const char* headers = Regex.get(request, 3);
            printf("found %s,%s,%s\n", method, uri, version);
        }
    }
    //Regex.dump(request, 2);
    Regex.free(request);
    return 1;
}
#endif
