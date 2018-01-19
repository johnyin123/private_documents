# -*- coding: utf-8 -*-

from __future__ import print_function
import sys
PY2 = sys.version_info[0] == 2

if PY2:
    unicode = unicode  # pylint: disable = invalid-name
    bytes = bytes  # pylint: disable = invalid-name
    cmp = cmp
    xrange = xrange
else:  # pragma: no cover
    unicode = str
    bytes = str
    cmp = lambda a, b: (a > b) - (a < b)  # pylint: disable = redefined-builtin
    xrange = range


import hashlib, uuid


def hash_sha1(passwd):
    return hashlib.sha1("john-SalT.12-{}".format(passwd).encode("utf-8")).hexdigest().lower()

def gen_uuid():
    return "{}".format(uuid.uuid4())


import json, decimal, datetime


def result2json(result, indent=None):
    def alchemyencoder(obj):
        """JSON encoder function for SQLAlchemy special classes."""
        if isinstance(obj, datetime.date) \
            or isinstance(obj, datetime.time) \
            or isinstance(obj, datetime.datetime):
            return obj.isoformat()
        elif isinstance(obj, decimal.Decimal):
            return float(obj)
        elif type(obj) is unicode:
            return obj.encode("utf-8")

    return json.dumps(
        [dict(r) for r in result],
        default=alchemyencoder,
        indent=indent,
        ensure_ascii=False)


from sqlalchemy.orm import class_mapper, ColumnProperty


def attribute_names(cls):
    return [
        prop.key for prop in class_mapper(cls).iterate_properties
        if isinstance(prop, ColumnProperty)
    ]


from .globals import db

def db_query(cls, criterion):
    return db.session.query(cls).filter(criterion)

def db_query_by(cls, **kwargs):
    return db.session.query(cls).filter_by(**kwargs)

def db_query_all(cls):
    return db.session.query(cls).all()

def db_query_count(cls):
    return db.session.query(cls).count()

def db_save(cls):
    db.session.add(cls)
    db.session.commit()
    return cls

def db_tables():
    from sqlalchemy import MetaData
    m = MetaData()
    m.reflect(db.engine)
    for table in m.tables.values():
        print(table.name)
        for column in table.c:
            print("    {}".format(column.name))

import math
class Page(object):
    def __init__(self, items, page, per_page, total):
        self.items = items
        self.prev_num = None
        self.next_num = None
        self.has_prev = page > 1
        if self.has_prev:
            self.prev_num = page - 1
        previous_items = (page - 1) * per_page
        self.has_next = previous_items + len(items) < total
        if self.has_next:
            self.next_num = page + 1
        self.total = total
        self.pages = int(math.ceil(total / float(per_page)))
        self.page = page
    def iter_pages(self, left_edge=2, left_current=2, right_current=5, right_edge=2):
        """
        sourcecode:: html+jinja
                {% macro render_pagination(pagination, endpoint) %}
                  <div class=pagination>
                  {%- for page in pagination.iter_pages() %}
                    {% if page %}
                      {% if page != pagination.page %}
                        <a href="{{ url_for(endpoint, page=page) }}">{{ page }}</a>
                      {% else %}
                        <strong>{{ page }}</strong>
                      {% endif %}
                    {% else %}
                      <span class=ellipsis>…</span>
                    {% endif %}
                  {%- endfor %}
                  </div>
                {% endmacro %}
        """
        last = 0
        for num in xrange(1, self.pages + 1):
            if num <= left_edge or \
               (num > self.page - left_current - 1 and \
                num < self.page + right_current) or \
               num > self.pages - right_edge:
                if last + 1 != num:
                    yield None
                yield num
                last = num

def paginate(query, page, per_page):
    if page <= 0:
        raise AttributeError('page needs to be >= 1')
    if per_page <= 0:
        raise AttributeError('per_page needs to be >= 1')
    items = query.limit(per_page).offset((page - 1) * per_page).all()
    # We remove the ordering of the query since it doesn't matter for getting a count and
    # might have performance implications as discussed on this Flask-SqlAlchemy issue
    # https://github.com/mitsuhiko/flask-sqlalchemy/issues/100
    total = query.order_by(None).count()
    return Page(items, page, per_page, total)

# Set up bindings
#app['SQLALCHEMY_BINDS'] = {
#   "first": "...",
#   "second": "..."
#}
#db = SQLAlchemy(app)
#session_first = db.get_session(bind = "first")
#session_second = db.get_session(bind = "second")
def get_dbsession(bind = None):
    return db.get_session(bind = bind)

"""
取得Model类中所有Column,attribute_names实现相同功能
init通用init函数
"""
class DBBase(object):
    def __init_(self, **kwargs):
        for key, val in kwargs.items(): 
            self.__dict__[key] = val

    def columns(self):
        return [col for col in dir(self) if isinstance(col, db.Column)]
