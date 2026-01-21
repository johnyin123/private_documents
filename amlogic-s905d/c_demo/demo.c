/*
(cd curl && CFLAGS=-fPIC ./configure --without-ssl --without-libpsl \
    --without-zlib --without-brotli --without-zstd  \
    --enable-shared=no --enable-static=yes \
    --without-ldap --disable-ldap --disable-ldaps \
    --disable-alt-svc \
    --disable-docs \
    --disable-ipfs \
    --disable-rtsp && make) || echo  'error~~~~~~~'
(cd cjson && make static) || echo  'error~~~~~~~'
(cd wsserver && make) || echo  'error~~~~~~~'
*/
#include <stdio.h>
#include <getopt.h>
#include <string.h>
#include <stdlib.h>
#include <curl/curl.h>
#include "demo.h"
#include "cJSON.h"

static int test_cjson() {
    const char *json_string = "{\"name\":\"Example\", \"value\":123}";
    cJSON *json = cJSON_Parse(json_string);
    if (json == NULL) {
        printf("Error parsing JSON\n");
        return 1;
    }
    cJSON *name_item = cJSON_GetObjectItemCaseSensitive(json, "name");
    if (cJSON_IsString(name_item)) {
        printf("Name: %s\n", name_item->valuestring);
    }
    cJSON *value_item = cJSON_GetObjectItemCaseSensitive(json, "value");
    if (cJSON_IsNumber(value_item)) {
        printf("Value: %d\n", value_item->valueint);
    }
    cJSON_Delete(json); // Clean up memory
    return 0;
}
static int test_curl() {
    CURL *curl;
    CURLcode res;

    // Initialize the global libcurl environment
    curl_global_init(CURL_GLOBAL_ALL);

    // Initialize a curl easy handle
    curl = curl_easy_init();
    if(curl) {
        // Set the URL to fetch
        curl_easy_setopt(curl, CURLOPT_URL, "http://127.0.0.1/info");
        curl_easy_setopt(curl, CURLOPT_USERAGENT, "neusoft (Linux GCC)");
        // Follow redirects
        curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
        // Perform the request, res will get the return code
        res = curl_easy_perform(curl);
        // Check for errors
        if(res != CURLE_OK) {
            fprintf(stderr, "curl_easy_perform() failed: %s\n", curl_easy_strerror(res));
        }
        // Always cleanup
        curl_easy_cleanup(curl);
    }
    // Cleanup the global libcurl environment
    curl_global_cleanup();
    return 0;
}
int dllmain(int argc, char *argv[])
{
    for (int i = 0; i < argc; ++i) {
        debugln("input %d, %s\n", i, argv[i]);
    }
    test_curl();
    test_cjson();
    return 0;
}
