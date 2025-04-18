#!/usr/bin/env bash
TARGET=/out
MONS=(/vmmapi/work/iso)
for dir in ${MONS[@]}; do
    rsync -avzP ${dir} ${TARGET}
done
inotifywait -e create,close_write,moved_to,delete -m --timefmt '%y%m%d%H%M' --format '%T %e %w %f' ${MONS[@]} | while read time event dir file; do
    echo "${time} ${event} ${dir} => ${TARGET}"
    rsync -avzP ${dir} ${TARGET}
done
:<<EOF
location ~* \.(iso)$ {
    autoindex off;
    root /${TARGET};
}
location ~* \/(meta-data|user-data)$ {
    autoindex off;
    root /${TARGET};
}
EOF
