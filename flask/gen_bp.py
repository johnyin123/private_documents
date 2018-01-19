#!/usr/bin/env python
# -*- coding: utf-8 -*-

from __future__ import print_function
from jinja2 import Environment, loaders
import random, argparse

index_html = """{# Text in this kind of brackets are comments #}
{# Text between {% %} is Jinja expression #}
{# Take a look at "e". It's a filter which escapes all HTML tags #}
{# Preventing them to be interpreted as normal HTML. #}
{# It's a security feature, use it on all untrusted variables #}
<h1>Hello, {{ name | e }}</h1>
<p>Your random number is {{ number | e }}</p>
{# We can test almost any condition #}
{% if number % 2 == 0: %}
<p>It is an even number, congratulations!</p>
{% else %}
<p>You were given an odd number, too bad!</p>
{% endif %}
{{ script | e }}
{# url_for('static', filename='style.css') #}
{# url_for('.static', filename='style.css') #}
{%- if current_user.is_authenticated %}
<li>
  <a href="#">{{current_user.name}}</a>
</li>
<li>
  <a href="{{ url_for("flask_login.logout") }}">Logout</a>
</li>
{%- else %}
<li><a href="{{ url_for("flask_login.login") }}">Login</a></li>
{%- endif %}

<textarea rows="10" cols="30">
    {{current_user.name}}
</textarea>"""

def test():
    dict_loader = loaders.DictLoader({
        "__init__.py": """# -*- coding: utf-8 -*-

from __future__ import print_function
from flask import Blueprint

module = Blueprint("{{ bp_name }}", __name__, template_folder="templates", static_folder="static")

from . import views""",

        "views.py": """# -*- coding: utf-8 -*-
'''
For URL Query parameter, use request.args
search = request.args.get("search")
page = request.args.get("page")

For Form input, use request.form
email = request.form.get('email')
password = request.form.get('password')

For data type application/json, use request.data
# data in string format and you have to parse into dictionary
data = request.data
dataDict = json.loads(data)
'''
from __future__ import print_function
from flask import current_app, render_template, abort, request, make_response, flash, redirect, url_for, json
from flask_login import current_user, login_required
from . import module
{%- if messages %} {%- endif %}

@module.route('/hello/')
@module.route('/hello/<name>', methods=['GET', 'POST'])
def hello(name=None):
    current_app.logger.debug('A value for debugging')
    current_app.logger.error('An error occurred')
    resp = make_response(render_template("{{ bp_name }}/hello.html", user=name))
    resp.headers['Content-type'] = 'text/xml; charset=utf-8'
    return resp


@module.route("/page/", defaults={"page": 4, "per_page":1}, methods=["GET", "POST"])
@module.route("/page/<int:page>/<int:per_page>", methods=["GET", "POST"])
def pagination(page, per_page):
    #page = 4
    #per_page = 1
    offset = (page - 1) * per_page
    # 分页方法
    users = User.query.offset(offset).limit(per_page)
    # 等同于下面的 slice 方法
    # users = User.query.slice(3, 4)
    return users


@module.route("{{ uri }}")
def run():
    bad_var = '<script>alert("gotcha");</script>'
    return render_template("{{ bp_name }}/index.html", name="names demo", number=2, script=bad_var)""",
        })
    env = Environment(loader=dict_loader)
    tmpl = env.get_template("__init__.py")
    print(tmpl.render(bp_name="xxx").strip())
    tmpl = env.get_template("views.py")
    print(tmpl.render(bp_name="xxxx", uri="/xxx/xxx/<int:aa>").strip())
    print(index_html)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="help message")
    #互斥的参数
    group = parser.add_mutually_exclusive_group()
    group.add_argument("-q", "--quiet", action="store_true")
    group.add_argument("-v", "--verbosity", action="store_true", help="increase output verbosity")

    parser.add_argument("-a", "--aaa", type=int, choices=[0, 1, 2], default=1, help="increase output verbosity")
    parser.add_argument('--version', action='store_true', help="print the version number and exit")
    parser.add_argument('url', nargs='?', help='SQLAlchemy url to the database')
    args = parser.parse_args()

    if args.verbosity:
        print("verbosity turned on")
    if args.version:
        print("version")
    if not args.url:
        print('You must supply a url\n', file=sys.stderr)
        parser.print_help()
