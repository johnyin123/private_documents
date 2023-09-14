from flask import Flask,render_template,request
from flask_socketio import SocketIO
import paramiko

async_mode = None
app = Flask(import_name=__name__,
            static_url_path='/python',   # 配置静态文件的访问url前缀
            static_folder='static',      # 配置静态文件的文件夹
            template_folder='templates') # 配置模板文件的文件夹

app.config['SECRET_KEY'] = "lyshark"
socketio = SocketIO(app)

def ssh_cmd():
    tran = paramiko.Transport(('192.168.150.129', 22,))
    tran.start_client()
    tran.auth_password('root', '1233')
    chan = tran.open_session()
    chan.get_pty(height=492,width=1312)
    chan.invoke_shell()
    return chan

sessions = ssh_cmd()

@app.route("/")
def index():
    return render_template("index.html")

# 出现消息后,率先执行此处
@socketio.on("message",namespace="/Socket")
def socket(message):
    print("接收到消息:",message)
    sessions.send(message)
    ret = sessions.recv(4096)
    socketio.emit("response", {"Data": ret.decode("utf-8")}, namespace="/Socket")
    print(message)

# 当websocket连接成功时,自动触发connect默认方法
@socketio.on("connect",namespace="/Socket")
def connect():
    ret = sessions.recv(4096)
    socketio.emit("response", {"Data": ret.decode("utf-8")}, namespace="/Socket")
    print("链接建立成功..")

# 当websocket连接失败时,自动触发disconnect默认方法
@socketio.on("disconnect",namespace="/Socket")
def disconnect():
    print("链接建立失败..")

if __name__ == '__main__':
    socketio.run(app,debug=True,host="0.0.0.0")

