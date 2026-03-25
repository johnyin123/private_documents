printf "GET / HTTP/1.1\r\n\r\n" | nc 127.0.0.1 8080
printf "GET /index.html HTTP/1.1\r\nHost: example.com\r\nUser-Agent: nc\r\n\r\n" | nc 127.0.0.1 8080
printf "POST /test HTTP/1.1\r\nContent-Length: 5\r\n\r\nhello" | nc 127.0.0.1 8080
(printf "POST /test HTTP/1.1\r\nContent-Length: 5\r\n\r\n"; sleep 1; printf "hello") | nc 127.0.0.1 8080
# Header without colon
printf "GET / HTTP/1.1\r\nBadHeader\r\n\r\n" | nc 127.0.0.1 8080
# Signed char issue
printf "GET /\xff HTTP/1.1\r\n\r\n" | nc 127.0.0.1 8080
(
printf "POST /x HTTP/1.1\r\nHost: a\r\nContent-Length: 11\r\n\r\nhe"
sleep 1
printf "llo "
sleep 1
printf "world"
) | nc 127.0.0.1 8080

printf "GET / HTTP/1.1\r" | nc 127.0.0.1 8080

curl -v http://127.0.0.1:8080/small
curl -v http://127.0.0.1:8080/big
cat <<EOF | curl -X POST http://127.0.0.1:8080/small -d '@-'
{"username":"name", "password":"pass"}
EOF
dd if=/dev/random bs=10M count=10 | curl --data-binary @- http://127.0.0.1:8080/big
# # not work!!
# dd if=/dev/random bs=1M count=10 | curl -X POST --form "file=@/dev/stdin" http://127.0.0.1:8080/big
