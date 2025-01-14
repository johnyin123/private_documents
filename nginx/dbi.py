# -*- coding: utf-8 -*-
import flask_app, sqlalchemy, sqlalchemy.orm, os

DATABASE_URI=os.getenv('DATABASE', 'sqlite:///:memory:')
engine = sqlalchemy.create_engine(DATABASE_URI, echo=flask_app.is_debug())
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
def vminfo_add(name, tx):
    vminfo = VMInfo(tm=datetime.datetime.now(), name=name, data=tx)
    session.add(vminfo)

def main():
    # create tables if not exists
    Base.metadata.create_all(engine)
    vminfo_add('a', 100)
    vminfo_add('b', 200)
    session.commit()
    session.close()
    return 0

if __name__ == '__main__':
    exit(main())
'''
