# -*- coding: utf-8 -*-
import sqlalchemy, sqlalchemy.orm, sqlalchemy.pool, os, logging
logger = logging.getLogger(__name__)
# logger.setLevel('DEBUG')
echo = (logger.getEffectiveLevel() == logging.DEBUG)
try:
    import config
    DATABASE_URI=config.DATABASE
except ImportError:
    DATABASE_URI=os.environ.get('DATABASE', 'sqlite:///demo.db?check_same_thread=False')
# # 'sqlite:///:memory:'
# # https://github.com/sqlalchemy/sqlalchemy/discussions/8858
args = dict(echo=echo, poolclass=sqlalchemy.pool.StaticPool)
engine = sqlalchemy.create_engine(DATABASE_URI, **args)
Session = sqlalchemy.orm.sessionmaker(bind=engine)
session = Session() 
# Base = sqlalchemy.orm.declarative_base()
from sqlalchemy.ext.declarative import as_declarative
@as_declarative()
class Base:
    def _asdict(self):
        return {c.name: getattr(self, c.name) for c in self.__table__.columns}
    def __repr__(self):
        d={c.name: getattr(self, c.name) for c in self.__table__.columns}
        return f'{d}'

    @staticmethod
    def exesql(sql, **kwargs):
        try:
            with session.begin():
                return session.execute(sqlalchemy.text(sql), kwargs)  # Parameterized query
        except Exception:
            session.rollback()
'''
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
from dbi import engine, Session, session, Base

from sqlalchemy import func,text,Column,String,Integer,Float,Date,DateTime,Enum,ForeignKey
class VMInfo(Base):
    __tablename__ = "vminfo"
    tm = Column(DateTime, nullable=False, index=True, primary_key=True, server_default=func.current_timestamp(),comment='key desc')
    name = Column(String(50), nullable=False, index=True, primary_key=True)
    data = Column(String, nullable=False) #unique=True
    # timestamp = Column(DateTime(timezone=True))
    def __repr__(self):
        return f'{self.tm} {self.name} {self.data}'

def vminfo_insert_or_update(name, data):
    instance = session.query(VMInfo).filter_by(name=name).first()
    if instance:
        # Update the record
        instance.data = data
    else:
        # Insert the record
        vminfo = VMInfo(name=name, data=data)
        session.add(vminfo)

def rawsql():
    # Using f-strings (Python 3.6+)
    v={'name':'myname', 'data':'mydata' }
    with session.begin_nested():
        session.execute(text(f"""INSERT INTO vminfo (name,data) VALUES ('{v["name"]}','{v["data"]}')"""))
    # sql="INSERT INTO vminfo (tm,name,data) VALUES ('{tm}','{name}','{data}')"
    # session.execute(text(sql.format(**v)))
    session.commit()
    result=session.execute(text("select * from vminfo"))
    for row in result:
        print(row)

def main():
    # create tables if not exists
    Base.metadata.create_all(engine)
    vminfo_insert_or_update('a', 100)
    session.commit()
    results = session.query(VMInfo).all()
    dic = [result._asdict() for result in results]
    results = session.query(VMInfo.name).all()
    dic = [result._asdict() for result in results]
    session.close()
    return 0

if __name__ == '__main__':
    exit(main())
'''
