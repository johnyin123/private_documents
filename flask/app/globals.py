# -*- coding: utf-8 -*-

from __future__ import print_function
from flask_sqlalchemy import SQLAlchemy as OriginalSQLAlchemy, _EngineConnector

from sqlalchemy import event


#以下解决sqlite3,事务处理bug
class SQLAlchemy(OriginalSQLAlchemy):
    """Override to fix issues when doing a rollback with sqlite driver
    See http://docs.sqlalchemy.org/en/rel_1_0/dialects/sqlite.html#serializable-isolation-savepoints-transactional-ddl
    and https://bitbucket.org/zzzeek/sqlalchemy/issues/3561/sqlite-nested-transactions-fail-with
    for furhter information"""

    # TODO: only do this on sqlite, not on postgres nor other RDBMS!
    def make_connector(self, app=None, bind=None):
        """Creates the connector for a given state and bind."""
        return CustomEngineConnector(self, self.get_app(app), bind)


class CustomEngineConnector(_EngineConnector):
    """Used by overrideb SQLAlchemy class to fix rollback issues"""

    def get_engine(self):
        # Use an existent engine and don't register events if possible
        uri = self.get_uri()
        echo = self._app.config['SQLALCHEMY_ECHO']
        if (uri, echo) == self._connected_for:
            return self._engine

        # Call original metohd and register events
        rv = super(CustomEngineConnector, self).get_engine()
        with self._lock:
            @event.listens_for(rv, "connect")
            def do_connect(dbapi_connection, connection_record):
                # disable pysqlite's emitting of the BEGIN statement entirely.
                # also stops it from emitting COMMIT before any DDL.
                dbapi_connection.isolation_level = None

            @event.listens_for(rv, "begin")
            def do_begin(conn):
                # emit our own BEGIN
                conn.execute("BEGIN")

        return rv


db = SQLAlchemy()

from flask_login import LoginManager

login_manager = LoginManager()
login_manager.session_protection = "strong"
login_manager.login_view = "flask_login.login"
