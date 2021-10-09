cvlc v4l2:// :v4l2-vdev="/dev/video0" :v4l2-adev="/dev/audio2" --sout '#transcode{vcodec=FLV1,vb=512,acodec=mpga,ab=64,samplerate=44100}:std{access=http{mime=video/x-flv},mux=ffmpeg{mux=flv},dst=0.0.0.0:8080/stream.flv}'
cvlc v4l2:// :v4l2-vdev="/dev/video0" --sout '#transcode{vcodec=WMV2,vb=800,acodec=wma2,ab=128,channels,samplerate=44100}:http{dst=0.0.0.0:8080/stream.asf}' --no-sout-all --sout-keep
cvlc v4l2:// :v4l2-vdev="/dev/video0" --sout '#transcode{vcodec=WMV2,vb=400,wicodec=none}:http{dst=:8080/stream.asf}'
arecord  -f cd -t raw | oggenc - -r | ssh -p60022 root@10.32.166.33 mplayer -
ssh <user>@<remotehost> 'arecord -f cd -t raw | oggenc - -r' | mplayer -
ssh <user>@<remotehost> 'arecord -f cd -D plughw:1 | ffmpeg -ac 1 -i - -f ogg -' | mplayer - -idle -demuxer ogg^C
arecord -l

