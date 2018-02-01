# -*- coding: utf-8 -*-

from __future__ import print_function
from flask import current_app, render_template, abort, request, make_response, flash, redirect, url_for, json
from flask_login import current_user, login_required
from . import module
from .host_ctrl import VirtHost

protocol = ["ssh", "libssh2", "qemu"]
host = {
    "connection" : "10.32.151.250:60022",
    "protocol" : "ssh",
    "username" : "root",
    "password" : "password",
    "key" : None
}
 
@module.route("/")
def index():
    vhost = VirtHost(host)
    status = vhost.connect()
    if status is False:
        return "NO CONNECT !!!!", 200
    domains = vhost.listAllDomains()
    res = []
    for domain in domains:
        res.append({ "name": domain.name(), "uuid":  domain.UUIDString(), "state": domain.isActive()})
    return render_template("/virt_mgr/index.html", all_domains = res)
