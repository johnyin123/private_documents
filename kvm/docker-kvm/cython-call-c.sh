fn=examples
cat <<EOF > ${fn}.h
void hello(const char *name);
EOF
cat <<EOF > ${fn}.c
#include <stdio.h>
void hello(const char *name) {
    printf("hello %s\n", name);
}
EOF
cat <<EOF > ${fn}.pyx
cdef extern from "${fn}.h":
    void hello(const char *name)

def py_hello(name: bytes) -> None:
    hello(name)
EOF

cython ${fn}.pyx -o ${fn}.pyx.c
# gcc -fPIC -shared `python3-config --cflags --ldflags` ${fn}.pyx.c ${fn}.c -o ${fn}.so
gcc -fpic -c ${fn}.pyx.c -o ${fn}.pyx.o `python3-config --includes`
gcc -fpic -c ${fn}.c -o ${fn}.o
gcc -fpic -shared -o ${fn}.so ${fn}.pyx.o ${fn}.o `python3-config --libs`
rm -f ${fn}.pyx.c
cat <<EOF > test-${fn}.py
#!/usr/bin/env -S python3 -B
# -*- coding: utf-8 -*-
import ${fn}

if __name__ == '__main__':
    ${fn}.py_hello(b"world")
EOF
