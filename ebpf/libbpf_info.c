static void print_libbpf_ver() { 
    fprintf(stderr, "libbpf: %d.%d\n", libbpf_major_version(), libbpf_minor_version()); 
}
