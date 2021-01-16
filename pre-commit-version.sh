#!/bin/sh
exec 1>&2
for f in $(git diff --cached --name-status  | grep -v '^D' | grep -E ".sh$"| sed 's/[A-Z][ \t]*//'); do
    __msg="$(git log --pretty='%h - %cI' -n 1 $f)"
    [ -z "${__msg}" ] && __msg="initversion - $(date --iso-8601=seconds)"
    echo "${f##*/} - ${__msg}"
    sed -i -E "s/^VERSION\+=.*$/VERSION+=(\"${f##*/} - ${__msg}\")/g" $f
    git add $f
done
exit 0
