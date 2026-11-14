#include <stdio.h>
#include <getopt.h>
#include <stdlib.h>
#include "utils.h"
#include "main.h"
struct env g_env = {
    .trace_level = LOG_ERR,
    .server_sock = 0,
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
}
static int parse_command_line(int argc, char **argv) {
    int opt, option_index;
    while ((opt = getopt_long(argc, argv, opt_short, opt_long, &option_index)) != -1) {
        switch (opt) {
            case 'h':
                usage(argv[0]); exit(0);
            case 256:
                fprintf(stdout, "version\n");
                return 0;
            default:
                usage(argv[0]); exit(1);
        }
    }
    return (argc - optind);
}
static void cleanup() {
    log_info("cleanup");
    if(g_env.server_sock>0) close_socket(g_env.server_sock);
#if defined(__WIN32__)
    WSACleanup();
#endif
}
#include <signal.h>
void sig_func(int sig) { UNUSED(sig); exit(EXIT_FAILURE); }
int main(int argc, char *argv[]) {
    const char* e_val = getenv("TRACE");
    if (e_val) g_env.trace_level = atoi(e_val);
    for(int i=0;i<parse_command_line(argc, argv);i++) {
        log_debug("argument %d [%s]", i, argv[optind+i]);
    }
#if defined(__WIN32__)
    WSADATA wsaData;
    int iResult = WSAStartup(MAKEWORD(2 ,2), &wsaData);
    if(iResult != 0) { log_error("error at WSASturtup %d", iResult); return EXIT_SUCCESS; }
#else
    signal(SIGPIPE, SIG_IGN);
#endif
    atexit(cleanup);
    signal(SIGINT, sig_func);
    signal(SIGTERM, sig_func);
    g_env.server_sock = create_tcp_server("127.0.0.1", HTTP_PORT, 10);
    if(g_env.server_sock<0) { return EXIT_FAILURE; }
    event_loop(g_env.server_sock);
    log_info("Exit");
    return EXIT_SUCCESS;
}
