#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("44394ce[2024-07-12T10:24:24+08:00]:ffmpeg.sh")
################################################################################

name=${1:?input err scale= $0 video.mkv}
scale=${scale--2:720,format=yuv420p}
frame=${frame-}

ffmpeg -hide_banner -i ${name} 2>&1 | grep Stream
ffmpeg -hide_banner -i ${name} 2>&1 | grep -o -Ei "Video:\s*([^ ]*)"
# # hevc to x264 for phicomm n1
# ffmpeg -i input -map 0 -c:v libx264 -crf 18 -vf format=yuv420p -c:a copy output.mkv
# ffmpeg -i input -vf scale=-1:720 -c:v libx264 -crf 18 -preset veryslow -c:a copy MyMovie_720p.mkv

# -movflags faststart 参数告诉 ffmpeg 重组 MP4 文件 atoms，将 moov 放到文件开头
# pv -f -F 'Converted: %b Elapsed: %t Current: %r Average: %a %p %e' "${name}" | ffmpeg -i pipe:0 \
ffmpeg -hide_banner -hwaccel auto -i ${name} -loglevel info \
    -movflags +faststart \
    -map 0:a:? -map 0:s:? -map 0:v:? \
    ${scale:+-vf scale=${scale}}  \
    ${frame:+-filter:v fps=fps=${frame}} \
    -c:a libmp3lame -b:a 128k -c:s copy \
    ${name%.*}.convert.mkv

ffmpeg -hide_banner -i ${name} 2>&1 | grep -o -Ei "Video:\s*([^ ]*)"

# cat > file.lst<<EOF
# file 1.mp4
# file 2.mp4
# EOF
# ffmpeg -f concat  -safe 0 -i file.lst -c copy out.mp4

# #Downgrade fps: from 60 to 30
# ffmpeg -i ${name} -r 30 ${name%.*}.convert.${name##*.}

# 增加字幕流
# ffmpeg -i video.mkv -i sub.ass -map 0 -map 1 -acodec copy -vcodec copy -scodec copy out.mkv
# ffmpeg -i input.mkv -i sub.srt -sub_charenc 'UTF-8' -f srt -map 0 -map 1:0 -c:v copy -c:a copy -c:s srt video.mkv
# ffmpeg -i input.mkv -i sub.srt -map 0 -map 1 -c copy youroutput.mkv
