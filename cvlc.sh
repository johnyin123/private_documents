1.
cvlc v4l2:// :v4l2-vdev="/dev/video0" --sout '#transcode{vcodec=WMV2,vb=800,acodec=wma2,ab=128,channels,samplerate=44100}:http{dst=0.0.0.0:8080/stream.asf}' --no-sout-all --sout-keep
cvlc v4l2:// :v4l2-vdev="/dev/video0" --sout '#transcode{vcodec=WMV2,vb=400,wicodec=none}:http{dst=:8080/stream.asf}'
arecord  -f cd -t raw | oggenc - -r | ssh -p60022 root@10.32.166.33 mplayer -
