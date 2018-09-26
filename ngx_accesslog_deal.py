#!/usr/bin/env python
# -*- coding: utf-8 -*-

from __future__ import print_function

import logging, sys

# ======================
# log_format parsing
# ======================
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

# =================================
# Simple Records processor
# =================================
class SimpleProcessor(object):
    def __init__(self, fields):
        self.fields = fields if fields is not None else []
        print(fields)
        pass

    def process(self, records):
        for r in records:
            for key, val in r.items():
                print(key, "=", val)

    def report(self):
        return "OK"

# =================================
# SQL Records processor
# =================================
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, scoped_session
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy import  String,Column,Integer,DateTime
import time

DATABASE_URI="sqlite:///./access.sqlite"
#DATABASE_URI="sqlite:///:memory:"
#DATABASE_URI="mysql+pymysql://admin:password@10.0.2.10:3306/log?charset=utf8"
engine = create_engine(DATABASE_URI)#, pool_size=1, max_overflow=0)
#Session = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)
Base = declarative_base()
Session = scoped_session(sessionmaker(bind=engine, autoflush=False, expire_on_commit=False))

DEFAULT_QUERIES = [
    ('Summary:',
     '''SELECT count(1) AS count FROM {}''')
]

class SQLProcessor(object):
    def __init__(self, tabname, fields):
        self.begin = False
        self.fields = fields if fields is not None else []
        self.tabname = tabname if tabname is not None else "log"
        #ret=session.execute('desc user')
        #print ret print ret.fetchall() print ret.first()
        self.conn = Session()
        if not engine.dialect.has_table(engine, self.tabname, schema = None):  # If table don't exist, Create.
            logging.debug('create table :%s\n', self.tabname)
            create_table = 'create table {} ({})'.format(self.tabname, ','.join(self.fields))
            self.conn.execute(create_table)

    def process(self, records):
        self.begin = time.time()
        sql = "insert into {} ({}) values ({}) ".format(self.tabname, ','.join(self.fields), ','.join(':%s' % var for var in self.fields))
        for r in records:
            self.conn.execute(sql, r)
        self.conn.commit()

    def report(self):
        if not self.begin:
            return ''
        duration = time.time() - self.begin
        output = [ 'running for {} seconds'.format(duration) ]
        for query in DEFAULT_QUERIES:
            if isinstance(query, tuple):
                label, query = query
            else:
                label = ''
            ret = self.conn.execute(query.format(self.tabname))
            output.append('{}\n{}'.format(label, ret.fetchall()))
        return '\n\n'.join(output)

    def count(self):
        ret = self.conn.execute('select count(1) from {}'.format(self.tabname))
        return ret.first()


def error_exit(msg, status=1):
    sys.stderr.write('Error: {}\n'.format(msg))
    sys.exit(status)

def map_field(field, func, dict_sequence):
    """
    Apply given function to value of given key in every dictionary in sequence and
    set the result as new value for that key.
    """
    for item in dict_sequence:
        try:
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
        if field not in item:
            item[field] = func(item)
        yield item

from httpagentparser import detect, simple_detect
def parse_useragent(records):
    for record in records:
        if 'http_user_agent' in record:
            ua = record['http_user_agent']
        else:
            ua = None
        dua = detect(ua)
        record['platform_version'] = dua.get('platform', {}).get('version', None) 
        record['platform_name']    = dua.get('platform', {}).get('name', None)
        record['os_version']       = dua.get('os', {}).get('version', None)
        record['os_name']          = dua.get('os', {}).get('name', None)
        record['browser_version']  = dua.get('browser', {}).get('version', None)
        record['browser_name']     = dua.get('browser', {}).get('name', None)
        record['robot']            = dua.get('bot', False)
        yield record

# ======================
# Access log parsing
# ======================
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
    return int(value) if value and value != '-' else 0

def to_float(value):
    return float(value) if value and value != '-' else 0.0

import dateutil.parser
def iso8601_to_datetime(value):
    return dateutil.parser.parse(value) if value and value != '-' else dateutil.parser.parse("1970-01-01T00:00:00+00:00")

def parse_log(lines, pattern):
    matches = (pattern.match(l) for l in lines)
    records = (m.groupdict() for m in matches if m is not None)
    records = map_field('status', to_int, records)
    records = map_field('body_bytes_sent', to_int, records)
    records = map_field('request_time', to_float, records)
    records = map_field('gzip_ratio', to_float, records)
    records = map_field('upstream_response_time', to_float, records)
    records = map_field('time_iso8601', iso8601_to_datetime, records)
    records = add_field('request_path', parse_request_path, records)
    records = parse_useragent(records)
    return records

# ===============
# Log processing
# ===============
def process_log(lines, pattern, processor, arguments):
    records = parse_log(lines, pattern)
    processor.process(records)
    print(processor.report())

def process(arguments):
    log_format = arguments["log-format"]
    if sys.stdin.isatty():
        error_exit("need access.log stream", 1)
    logging.debug("log_format: %s", log_format)
    access_log = sys.stdin
    pattern = build_pattern(log_format)
    fields = [r for r in extract_variables(log_format)]
    fields.append("request_path")
    fields.append("platform_version")
    fields.append("platform_name")
    fields.append("os_version")
    fields.append("os_name")
    fields.append("browser_version")
    fields.append("browser_name")
    fields.append("robot")

    processor = SimpleProcessor(fields)
    sqlprocessor = SQLProcessor("logtable", fields)
    process_log(access_log, pattern, sqlprocessor, arguments)

def main():
    args = {
            "debug":True,
            "log-format": '"$time_iso8601" $scheme $http_host [$request_time|$upstream_response_time] $remote_addr - $remote_user [$time_local] "$request" $status $body_bytes_sent "$http_referer" "$http_user_agent" "$http_x_forwarded_for" $gzip_ratio',
           }
    log_level = logging.WARNING
    if args["debug"]:
        log_level = logging.DEBUG
    logging.basicConfig(level=log_level, format="%(levelname)s: %(message)s")
    logging.debug("arguments:\n%s", args)

    try:
        process(args)
    except KeyboardInterrupt:
        logging.info("interrupt signal received")
        sys.exit(0)

def test():
    value = "2018-08-29T03:39:57+08:00"
    yourdate = dateutil.parser.parse(value)
    print(yourdate.strftime("%Y-%m-%d %H:%M:%S")) 

if __name__ == '__main__':
    main()
