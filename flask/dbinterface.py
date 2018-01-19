from sqlalchemy import *
from sqlalchemy.orm import *
import sys, traceback

class dbinterface:

    #initialize db
    def __init__(self, db_url, echo=False):
        db = create_engine(db_url)
        db.echo = echo
        self.table_map = {}
        self.Session = None
        
        #Initialize DB and create a hashmap of table name and associated ORM mapper class
        metadata = MetaData(db)
        #retrieve database table information dynamically
        metadata.reflect()
        for table_name in metadata.tables:
            #create a class that inherits basetable class and maps the class to table
            table_class = type(str(table_name),(basetable,),{})
            try :
                mapper(table_class, Table(table_name, metadata, autoload=True))
                self.table_map[table_name] = table_class
            except:
                print "could not map table ", table_name
        #create a Session template that requires commit to be called explicit
        self.Session = sessionmaker(bind=db, autoflush=True, transactional=True)

    #create a record
    def create(self, table_name, record):
        session = None
        status = False
        try:
            #lookup the corresponding table class and create an instance
            table_instance = self.table_map[table_name]()
            table_instance.pack(record)
            session = self.Session()
            session.save(table_instance)
            session.commit()
            status = True
        except:
            print traceback.format_exc()
        finally:
            if session:
                session.close()
        return status

    #fetch all the records from table that have conditions specified
    def read(self, table_name, **keywords):
        session = None
        records = []
        try:
            table_class = self.table_map[table_name]
            session = self.Session()
            query = session.query(table_class)
            resultset = query.filter_by(**keywords).all()
            for record in resultset:
                records.append(record.unpack())
        except:
            print traceback.format_exc()
        finally:
            if session:
                session.close()
        return records
    
    
class basetable(object):
    #map the record dictionary to table instance variables
    def pack(self, record):
        for column in record:
            self.__dict__[column] = record[column]
    
    #return the dictionary representation of the table instance
    def unpack(self):
        record = {}
        for name in self.__dict__:
            if name[0] == "_": continue #exclude non column keys
            value = self.__dict__[name]
            #if value is None: continue #exclude null values
            try:
                record[name] = unicode(value)
            except:
                record[name] = repr(value)
        return record

    #string representation of the record
    def __str__(self):
        return self.unpack()


#test code
#genre_table = Table('genre',metadata,
# Column('id',Integer,primary_key=True),
# Column('name', String(256)),
# Column('active',Boolean)
 
def main():
    import config
    dbi = dbinterface(config.db_url)

    print "create a genre with name Comedy and active set to True"
    record = { 'name' : 'Comedy', 'active' : True}
    dbi.create('genre' , record)
    
    print "create a genre with name Music and active set to False"
    record = { 'name' : 'Music', 'active' : False}
    dbi.create('genre' , record)
    
    print "get all the records that are active"
    for result in dbi.read('genre', active = False):
        print result

    print "get all the records from genre table"
    for result in dbi.read('genre'):
        print result


if __name__ == "__main__":
    main()
