Server:
# # 启动socat，监听tcp 5001端口，设置tun设备ip地址为10.0.0.1/24
nohup socat TCP-LISTEN:5001,reuseaddr TUN:10.0.0.1/24,up &> socat.log &
# # 启动kcptun，监听udp 5000端口，把数据都转发给127.0.0.1:5001
nohup kcptun-server --listen :5000 --target 127.0.0.1:5001 --mode fast2 &>srv.log &

Client：
nohup kcptun-client --remoteaddr Server-IP:5000 --localaddr :5001 --mode fast2 &>cli.log &
# # 启动socat，将tun设备所有数据包发送至127.0.0.1:5001
nohup socat TCP:127.0.0.1:5001 TUN:10.0.0.2/24,up &>socat.log &
