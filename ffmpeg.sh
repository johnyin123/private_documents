#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("b750249[2022-01-27T17:40:06+08:00]:ffmpeg.sh")
################################################################################

name=${1:?input err}
scale=${scale:--1:720}

ffmpeg -i ${name} 2>&1 | grep Stream

# pv -f -F 'Converted: %b Elapsed: %t Current: %r Average: %a %p %e' "${name}" | ffmpeg -i pipe:0 \
ffmpeg -hwaccel auto -i ${name} -v error -map 0:a:? -map 0:s:? -map 0:v:? -vf scale=${scale} -c:v libx265 -crf 18 \
    -c:a copy -c:s copy ${name%.*}.convert.${name##*.}

# ffmpeg -i ${name} -map 0:a -map 0:s -map 0:v -vf scale=-1:720 -c:v libx264 -crf 18 \
#     -c:a copy -c:s copy ${name%.*}.convert.${name##*.}
# ffmpeg -i ${name} -b 1000k ${name%.*}.convert.${name##*.}
# # -hwaccel
# 增加字幕流
# ffmpeg -i video.avi -i sub.ass -map 0:0 -map 0:1 -map 1 -c:a copy -c:v copy -c:s copy video.mkv

# cat > file.lst<<EOF
# file 1.mp4
# file 2.mp4
# EOF
# ffmpeg -f concat  -safe 0 -i file.lst -c copy out.mp4
