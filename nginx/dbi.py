# -*- coding: utf-8 -*-
import flask_app, sqlalchemy, sqlalchemy.orm, sqlalchemy.pool, os

DATABASE_URI=os.getenv('DATABASE', 'sqlite:///:memory:')
# # https://github.com/sqlalchemy/sqlalchemy/discussions/8858
args = dict(echo=flask_app.is_debug(), connect_args={'check_same_thread':False}, poolclass=sqlalchemy.pool.StaticPool)
engine = sqlalchemy.create_engine(DATABASE_URI, **args)
Session = sqlalchemy.orm.sessionmaker(bind=engine)
session = Session() 
Base = sqlalchemy.orm.declarative_base()
'''
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
from dbi import engine, Session, session, Base

from sqlalchemy import Column,String,Integer,DateTime
class VMInfo(Base):
    __tablename__ = "vminfo"
    tm = Column(DateTime, nullable=False, index=True, primary_key=True)
    name = Column(String(50), nullable=False, index=True, primary_key=True)
    data = Column(Integer, nullable=False)

    def __repr__(self):
        return f'{self.tm} {self.name} {self.data}'

import datetime
def vminfo_insert_or_update(name, data):
    instance = session.query(VMInfo).filter_by(name=name).first()
    if instance:
        # Update the record
        instance.tm=datetime.datetime.now()
        instance.data = data
    else:
        # Insert the record
        vminfo = VMInfo(tm=datetime.datetime.now(), name=name, data=data)
        session.add(vminfo)

def main():
    # create tables if not exists
    Base.metadata.create_all(engine)
    vminfo_insert_or_update('a', 100)
    session.commit()
    session.close()
    return 0

if __name__ == '__main__':
    exit(main())
'''
