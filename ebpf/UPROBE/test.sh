#!/usr/bin/env bash
cat <<EOF > test.c
#include <stdio.h>
#include <unistd.h>
int foo(int a, int b)
{
    sleep(1);
    return a + b;
}
int main()
{
    int i = 0;
    while(1)
    {
        foo(i++, i);
        sleep(1);
    }
    return 0;
}
EOF
gcc test.c -o ~/testprog
rm test.c
nm /root/testprog  | grep foo
echo "long func_offset = 0x$(nm /root/testprog  | grep foo | awk '{print $1}');"
