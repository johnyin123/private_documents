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
echo "---------------------------------------------------"
fn=pymod
cat <<EOF > ${fn}.c
#include <Python.h>
int fib_from_python(int a) {
    int res;
    PyObject *pModule,*pFunc,*pArgs,*pValue;
    /* import */
    const char* module_name = "${fn}";
    PyObject *pName = PyUnicode_FromString(module_name);
    pModule = PyImport_Import(pName);
    Py_DECREF(pName); // Release the reference to the module name
    if (pModule == NULL) {
        PyErr_Print();
        return -1;
    }
    /* great_module.great_function */
    pFunc = PyObject_GetAttrString(pModule, "fib");
    /* build args */
    pArgs = PyTuple_New(1);
    PyTuple_SetItem(pArgs,0,PyLong_FromLong(a));
    /* call */
    pValue = PyObject_CallObject(pFunc, pArgs);
    res = PyLong_AsLong(pValue);
    Py_DECREF(pModule); // Release the reference when done
    return res;
}
int main(int argc, char *argv[]) {
    Py_Initialize();
    printf("fib = %d\n",fib_from_python(2));
    Py_Finalize();
    return 0;
}
EOF
cat <<EOF > ${fn}.py
def fib(n):
    a,b = 1, 1
    for i in range(n):
        a,b = a+b, a
    return a
EOF
gcc -c ${fn}.c -o ${fn}.o $(python3-config --includes)
gcc ${fn}.o $(python3-config --embed --ldflags) -o ${fn}
PYTHONPATH=`pwd` ./${fn}
echo "---------------------------------------------------"
fn=ctypedemo
cat <<EOF > ${fn}.c
#include <stdio.h>
void hello(const char *name) {
    printf("hello %s\n", name);
}
EOF
cat <<EOF > ${fn}_ctype.py
import ctypes

lib = ctypes.cdll.LoadLibrary('./${fn}.so')
lib.hello.argtypes = [ctypes.c_char_p]
lib.hello.restype = None

def hello(x:str):
    x = x.encode('utf-8')
    lib.hello(x)
EOF
cat <<EOF > test_${fn}.py
#!/usr/bin/env -S python3 -B
# -*- coding: utf-8 -*-
from ${fn}_ctype import hello
hello('i am here')
EOF
gcc -fpic -shared -o ${fn}.so ${fn}.c $(python3-config --includes --libs)
echo "---------------------------------------------------"
