#!/usr/bin/env python3
# -*- coding: utf-8 -*-
from __future__ import print_function
import logging, sys, os

import re
REGEX_SPECIAL_CHARS = r'([\.\*\+\?\|\(\)\{\}\[\]])'
REGEX_LOG_FORMAT_VARIABLE = r'\$([a-zA-Z0-9\_]+)'
def build_pattern(log_format):
    """
    Build regular expression to parse given format.
    :param log_format: format string to parse
    :return: regular expression to parse given format
    """
    pattern = re.sub(REGEX_SPECIAL_CHARS, r'\\\1', log_format)
    pattern = re.sub(REGEX_LOG_FORMAT_VARIABLE, '(?P<\\1>.*)', pattern)
    return re.compile(pattern)

def extract_variables(log_format):
    """
    Extract all variables from a log format string.
    :param log_format: format string to extract
    :return: iterator over all variables in given format string
    """
    for match in re.findall(REGEX_LOG_FORMAT_VARIABLE, log_format):
        yield match

def map_field(field, func, dict_sequence):
    """
    Apply given function to value of given key in every dictionary in sequence and
    set the result as new value for that key.
    """
    try:
        for item in dict_sequence:
            if field in item.keys():
                item[field] = func(item.get(field, None))
            yield item
    except ValueError:
        pass

def add_field(field, func, dict_sequence):
    """
    Apply given function to the record and store result in given field of current record.
    Do nothing if record already contains given field.
    """
    for item in dict_sequence:
        if field not in item.keys():
            item[field] = func(item)
        yield item

try:
    import urlparse
except ImportError:
    import urllib.parse as urlparse

def parse_request_path(record):
    if 'request_uri' in record:
        uri = record['request_uri']
    elif 'request' in record:
        uri = ' '.join(record['request'].split(' ')[1:-1])
    else:
        uri = None
    return urlparse.urlparse(uri).path if uri else None

def to_int(value):
    return int(value) if value and value.isdigit() else 0

def to_float(value):
    try:
        return float(value) if value and value != '-' else 0.0
    except ValueError:
        return 0.0

import dateutil.parser
def iso8601_to_datetime(value):
    return dateutil.parser.parse(value) if value and value != '-' else dateutil.parser.parse("1970-01-01T00:00:00+00:00")

from datetime import datetime
def time_local_to_datetime(value):
    return datetime.strptime(value, '%d/%b/%Y:%H:%M:%S %z') if value and value != '-' else dateutil.parser.parse("1970-01-01T00:00:00+00:00")

def parse_log(lines, pattern):
    matches = (pattern.match(l) for l in lines)
    records = (m.groupdict() for m in matches if m is not None)
    records = map_field('status', to_int, records)
    records = map_field('request_length', to_int, records)
    records = map_field('bytes_sent', to_int, records)
    records = map_field('request_time', to_float, records)
    records = map_field('gzip_ratio', to_float, records)
    # 0.881, 1.463, 0.454
    # records = map_field('upstream_response_time', to_float, records)
    records = map_field('time_iso8601', iso8601_to_datetime, records)
    records = map_field('time_local', time_local_to_datetime, records)
    records = add_field('request_path', parse_request_path, records)
    return records

from sqlalchemy.orm import sessionmaker, scoped_session
from sqlalchemy import create_engine,MetaData,Table,Column,String,Integer,DateTime,Float
from sqlalchemy.dialects.mysql import LONGTEXT

def insert_db(records):
    # DATABASE_URI="sqlite:///./access.sqlite"
    DATABASE_URI="mysql+pymysql://admin:password@192.168.168.124:3306/ngxlog?charset=utf8"
    engine = create_engine(DATABASE_URI)
    Session = scoped_session(sessionmaker(bind=engine, autoflush=False, expire_on_commit=False))
    conn = Session()

    metadata_obj = MetaData()
    Access = Table(
        'access', metadata_obj,
        Column('scheme', String(10)),
        Column('http_host', String(64)),
        Column('server_port', String(10)),
        Column('upstream_addr', String(64)),
        Column('request_time', Float),
        Column('upstream_response_time', String(64)),
        Column('upstream_status', String(64)),
        Column('remote_addr', String(64)),
        Column('remote_user', String(64)),
        Column('time_local', DateTime),
        Column('request', LONGTEXT),
        Column('status', Integer),
        Column('request_length', Integer),
        Column('bytes_sent', Integer),
        Column('http_referer', LONGTEXT),
        Column('http_user_agent', String(1024)),
        Column('http_x_forwarded_for', String(64)),
        Column('gzip_ratio', Float),
        Column('request_path', String(1024)),
    )
    metadata_obj.create_all(engine, checkfirst=True)
    for r in records:
        ins = Access.insert().values(r)
        conn.execute(ins)
    conn.commit()

def main():
    args = {
            "log-format": '$scheme $http_host $server_port "$upstream_addr" [$request_time|"$upstream_response_time"|"$upstream_status"] $remote_addr - $remote_user [$time_local] "$request" $status $request_length $bytes_sent "$http_referer" "$http_user_agent" "$http_x_forwarded_for" $gzip_ratio',
            "debug":False
           }
    log_level = logging.WARNING
    if args["debug"]:
        log_level = logging.DEBUG
    logging.basicConfig(level=log_level, format="%(levelname)s: %(message)s")
    logging.debug("arguments:\n%s", args)
    if sys.stdin.isatty():
        logging.error("no input, cat access.log | parallel --pipe ./ngx_accesslog.py")
        sys.exit(1)
    access_log = sys.stdin
    pattern = build_pattern(args["log-format"])
    try:
        insert_db(parse_log(access_log, pattern))
    except KeyboardInterrupt:
        logging.info("interrupt signal received")
        sys.exit(0)

if __name__ == '__main__':
    main()
# select sum(request_length) as recv ,sum(bytes_sent) as send from access;
# select http_host, upstream_addr, sum(request_length) as recv ,sum(bytes_sent) as send, sum(request_length + bytes_sent) as total from access group by upstream_addr order by total desc;
# select remote_addr, sum(request_length) as recv, sum(bytes_sent) as send, sum(request_length+bytes_sent) as total  from access group by remote_addr order by total desc;
# select count(CASE WHEN status >= 200 AND status < 300 THEN 1 END) AS '2xx' from access;
# select count(CASE WHEN status >= 300 AND status < 400 THEN 1 END) AS '3xx' from access;
# select count(CASE WHEN status >= 400 AND status < 500 THEN 1 END) AS '4xx' from access;
# select count(CASE WHEN status >= 500 AND status < 600 THEN 1 END) AS '5xx' from access;
# select avg(request_time) as avg_request_time from access;
# select sum(bytes_sent) as sum_bytes_sent from access;
# select round(avg(bytes_sent)) as avg_bytes_sent from access;
# select request_path, count(*) as n, bytes_sent from access group by request_path order by n desc;
# select count(*) as n, remote_addr, sum(bytes_sent) as total_bytes_sent, sum(request_length) as total_upload from access group by remote_addr order by n desc;
# select count(*) as n, http_referer from access group by http_referer order by n desc;
