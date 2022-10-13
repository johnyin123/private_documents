#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import hashlib, time, base64
from ldap3 import Server, Connection, ALL
from flask import Flask, request, jsonify, flash, make_response, render_template, render_template_string, redirect, url_for, send_file

app = Flask(__name__)
app.config['LDAP_URL'] = 'ldap://127.0.0.1:389'
app.config['UID_FMT'] = 'uid={uid},ou=people,dc=sample,dc=org'
app.config['KEY_FMT'] = '{prekey}{seconds}{uid}'
app.config['PREKEY'] = 'prekey'
app.config['EXPIRE'] = 36000
app.secret_key = 'some key'
login_html="""
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
    <meta http-equiv="X-UA-Compatible" content="IE=edge">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="robots" content="noindex, nofollow">
    <title> {{ title }} </title>
<style>
body {
  font-family: sans-serif;
  color: #333;
}
main {
  margin: 0 auto;
}
h1 {
  font-size: 2em;
  margin-bottom: 2.5em;
  margin-top: 2em;
  text-align: center;
}
form {
  border-radius: 0.2rem;
  border: 1px solid #CCC;
  margin: 0 auto;
  max-width: 16rem;
  padding: 2rem 2.5rem 1.5rem 2.5rem;
}
input {
  background-color: #FAFAFA;
  border-radius: 0.2rem;
  border: 1px solid #CCC;
  box-shadow: inset 0 1px 3px #DDD;
  box-sizing: border-box;
  display: block;
  font-size: 1em;
  padding: 0.4em 0.6em;
  vertical-align: middle;
  width: 100%;
}
input:focus {
  background-color: #FFF;
  border-color: #51A7E8;
  box-shadow: 0 1px 2px rgba(0, 0, 0, 0.075) inset, 0 0 5px rgba(81, 167, 232, 0.5);
  outline: 0;
}
label {
  color: #666;
  display: block;
  font-size: 0.9em;
  font-weight: bold;
  margin: 1em 0 0.25em 0;
}
button {
  background-color: #60B044;
  background-image: linear-gradient(#8ADD6D, #60B044);
  border-radius: 0.2rem;
  border: 1px solid #5CA941;
  box-sizing: border-box;
  color: #fff;
  cursor: pointer;
  display: block;
  font-size: 0.9em;
  font-weight: bold;
  margin: 2em 0 0.5em 0;
  padding: 0.5em 0.7em;
  text-align: center;
  text-decoration: none;
  text-shadow: 0 -1px 0 rgba(0, 0, 0, 0.3);
  user-select: none;
  vertical-align: middle;
  white-space: nowrap;
}
button:focus,
button:hover {
  background-color: #569E3D;
  background-image: linear-gradient(#79D858, #569E3D);
  border-color: #4A993E;
}
.alerts {
  margin: 2rem auto 0 auto;
  max-width: 30rem;
}
.alert {
  border-radius: 0.2rem;
  border: 1px solid;
  color: #fff;
  padding: 0.7em 1.5em;
}
.alert.error {
  background-color: #E74C3C;
  border-color: #C0392B;
}
.alert.success {
  background-color: #60B044;
  border-color: #5CA941;
}
@media only screen and (max-width: 480px) {
  form {
    border: 0;
  }
}
</style>
  </head>
  <body>
    <main>
      <h1>{{ title }}</h1>
      <form method="post">
        <label for="username">Username</label>
        <input id="username" name="username" value="{{ request.cookies.get('UID', '') }}" type="text" required autofocus>
        <label for="password">Password</label>
        <input id="password" name="password" type="password" required>
{%- if service %}
        <input type="hidden" name="service" value="{{ service }}" />
{%- else %}
        <label for="new-password">New password</label>
        <input id="new-password" name="new-password" type="password" pattern=".{8,}" oninvalid="SetCustomValidity('Password must be at least 8 characters long.')" required>
        <label for="confirm-password">Confirm new password</label>
        <input id="confirm-password" name="confirm-password" type="password" pattern=".{8,}" oninvalid="SetCustomValidity('Password must be at least 8 characters long.')" required>
{%- endif %}
        <button type="submit">submit</button>
      </form>
      <div class="alerts">
{%- with messages = get_flashed_messages(with_categories=true) %}
 {%- if messages %}
  {%- for category, message in messages %}
        <div class="alert {{ category }}">{{ message }}</div>
  {%- endfor %}
 {%- endif %}
{%- endwith %}
      </div>
    </main>
  </body>
</html>
    """
def base64UrlEncode(data):
    return str(base64.urlsafe_b64encode(data).rstrip(b'='), "utf-8")

def init_connection(url, binddn, password):
    srv = Server(url, get_info=ALL)
    conn = Connection(srv, user=binddn, password=password)
    conn.bind()
    return conn

@app.route('/userinfo', methods=['GET', 'POST'])
def userinfo():
    username = request.values.get('username')
    password = request.values.get('password')
    newpwd = request.values.get('new-password')
    confirmpwd = request.values.get('confirm-password')
    if username is None or password is None or newpwd is None or confirmpwd is None:
        return render_template_string(login_html, title="Change Password")
    if newpwd != confirmpwd:
        flash("new-password != confirm-password", "error")
        return render_template_string(login_html, title="Change Password")
    try:
        c = init_connection(app.config['LDAP_URL'], app.config['UID_FMT'].format(uid=username), password)
        changes = {"userPassword": [(MODIFY_REPLACE, newpwd)]}
        c.modify(app.config['UID_FMT'].format(uid=username), changes)
        c.unbind()
        flash("change password success", "success")
        return render_template_string(login_html, title="Change Password")
    except Exception as e:
        flash(e, "error")
        return render_template_string(login_html, title="Change Password")

@app.route('/login', methods=['GET', 'POST'])
def login():
    #request.args.get/request.form.get/request.values.get
    service = request.values.get("service", "/userinfo")
#    if request.method == "GET":
#        return render_template_string(login_html, service=service, title="Login")
    try:
        username = request.values.get('username')
        password = request.values.get('password')
        if username is None or password is None:
            return render_template_string(login_html, service=service, title="Login")
        # if request.environ.get('HTTP_X_REAL_IP') is not None:
        #     ip = request.environ.get('HTTP_X_REAL_IP')
        c = init_connection(app.config['LDAP_URL'], app.config['UID_FMT'].format(uid=username), password)
        status = c.bound
        c.unbind()
        if status:
            epoch = round(time.time() + app.config['EXPIRE'])
            key = app.config['KEY_FMT'].format(prekey=app.config['PREKEY'], uid=username, seconds=epoch)
            sec_key = base64UrlEncode(hashlib.md5(key.encode("utf-8")).digest())
            resp = make_response(redirect(service, 302))
            resp.set_cookie('KEY', sec_key, expires=epoch)
            resp.set_cookie('EXPIRES', str(epoch), expires=epoch)
            resp.set_cookie('UID', username, expires=epoch)
            # resp.headers['Location'] = service
            return resp
        else:
            flash("Username or Password Error", "error")
            return render_template_string(login_html, service=service, title="Login")
    except Exception as e:
        flash(e, "error")
        return render_template_string(login_html, service=service, title="Login")

@app.route('/logout', methods=['GET'])
def logout():
    # from flask_qrcode import QRcode
    # qrcode = QRcode(app)
    # resp = send_file(qrcode("message", mode="raw"), mimetype="image/png", download_name="a.png")
    resp = make_response(jsonify({"status": 200, "message": "logout success" }))
    resp.set_cookie('KEY', '', expires=0)
    resp.set_cookie('EXPIRES', '', expires=0)
    resp.set_cookie('UID', '', expires=0)
    return resp, 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080) #, debug=True)
