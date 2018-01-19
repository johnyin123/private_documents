# -*- coding: utf-8 -*-

from __future__ import print_function
from sqlalchemy import Column, Date, ForeignKey, Integer, String, UniqueConstraint, TIMESTAMP
from sqlalchemy.orm import relationship
from flask_sqlalchemy import SQLAlchemy
from app.globals import db
from flask_login import UserMixin
from sqlalchemy.sql import func
from app.utils import gen_uuid

t_TRBAC_CONST = db.Table('TRBAC_CONST',
                         db.Column('CODE_TYPE', db.String(50)),
                         db.Column('CODE_KEY', db.String(10)),
                         db.Column('CODE_VALUE', db.Text))


class TRBACOBJECT(db.Model):
    __tablename__ = 'TRBAC_OBJECT'

    OBJ_ID = db.Column(db.String(32), primary_key=True)
    OBJ_NAME = db.Column(db.Text, nullable=False, unique=True)
    MEMO = db.Column(db.Text)


class TRBACOPERATION(db.Model):
    __tablename__ = 'TRBAC_OPERATION'
    __table_args__ = (db.UniqueConstraint('OPERATION', 'TENANT_ID'), )

    OPER_ID = db.Column(db.String(32), primary_key=True, nullable=False)
    TENANT_ID = db.Column(
        db.ForeignKey(u'TRBAC_TENANT.TENANT_ID'),
        primary_key=True,
        nullable=False)
    OPERATION = db.Column(db.Text, nullable=False)
    MEMO = db.Column(db.Text)

    TRBAC_TENANT = db.relationship(
        u'TRBACTENANT',
        primaryjoin='TRBACOPERATION.TENANT_ID == TRBACTENANT.TENANT_ID',
        backref=u'trbacoperations')


class TRBACORG(db.Model):
    __tablename__ = 'TRBAC_ORG'
    __table_args__ = (db.UniqueConstraint('TENANT_ID', 'PID', 'NAME'), )

    ORG_ID = db.Column(db.String(32), primary_key=True)
    PID = db.Column(db.ForeignKey(u'TRBAC_ORG.ORG_ID'), nullable=False)
    TENANT_ID = db.Column(
        db.ForeignKey(u'TRBAC_TENANT.TENANT_ID'), nullable=False)
    NAME = db.Column(db.Text, nullable=False)
    MEMO = db.Column(db.Text)

    parent = db.relationship(
        u'TRBACORG',
        remote_side=[ORG_ID],
        primaryjoin='TRBACORG.PID == TRBACORG.ORG_ID',
        backref=u'trbacorgs')
    TRBAC_TENANT = db.relationship(
        u'TRBACTENANT',
        primaryjoin='TRBACORG.TENANT_ID == TRBACTENANT.TENANT_ID',
        backref=u'trbacorgs')


class TRBACPERMISSION(db.Model):
    __tablename__ = 'TRBAC_PERMISSION'

    ROLE_ID = db.Column(
        db.ForeignKey(u'TRBAC_ROLE.ROLE_ID'), primary_key=True, nullable=False)
    OPER_ID = db.Column(
        db.ForeignKey(u'TRBAC_OPERATION.OPER_ID'),
        primary_key=True,
        nullable=False)
    OBJ_ID = db.Column(
        db.ForeignKey(u'TRBAC_OBJECT.OBJ_ID'),
        primary_key=True,
        nullable=False)

    TRBAC_OBJECT = db.relationship(
        u'TRBACOBJECT',
        primaryjoin='TRBACPERMISSION.OBJ_ID == TRBACOBJECT.OBJ_ID',
        backref=u'trbacpermissions')
    TRBAC_OPERATION = db.relationship(
        u'TRBACOPERATION',
        primaryjoin='TRBACPERMISSION.OPER_ID == TRBACOPERATION.OPER_ID',
        backref=u'trbacpermissions')
    TRBAC_ROLE = db.relationship(
        u'TRBACROLE',
        primaryjoin='TRBACPERMISSION.ROLE_ID == TRBACROLE.ROLE_ID',
        backref=u'trbacpermissions')


class TRBACROLE(db.Model):
    __tablename__ = 'TRBAC_ROLE'

    ROLE_ID = db.Column(db.String(32), primary_key=True, nullable=False)
    TENANT_ID = db.Column(
        db.ForeignKey(u'TRBAC_TENANT.TENANT_ID'),
        primary_key=True,
        nullable=False)
    ROLE_NAME = db.Column(db.Text, nullable=False)
    MEMO = db.Column(db.Text)

    TRBAC_TENANT = db.relationship(
        u'TRBACTENANT',
        primaryjoin='TRBACROLE.TENANT_ID == TRBACTENANT.TENANT_ID',
        backref=u'trbacroles')


class TRBACTENANT(db.Model):
    __tablename__ = 'TRBAC_TENANT'

    TENANT_ID = db.Column(db.String(32), primary_key=True)
    TENANT_NAME = db.Column(db.Text, nullable=False, unique=True)
    MEMO = db.Column(db.Text)


class TRBACTENANTUSER(db.Model):
    __tablename__ = 'TRBAC_TENANT_USER'

    TENANT_ID = db.Column(
        db.ForeignKey(u'TRBAC_TENANT.TENANT_ID'),
        primary_key=True,
        nullable=False)
    USER_ID = db.Column(
        db.ForeignKey(u'TRBAC_USER.USER_ID'), primary_key=True, nullable=False)
    USER_STATUS = db.Column(db.String(1))
    MEMO = db.Column(db.Text)

    TRBAC_TENANT = db.relationship(
        u'TRBACTENANT',
        primaryjoin='TRBACTENANTUSER.TENANT_ID == TRBACTENANT.TENANT_ID',
        backref=u'trbactenantusers')
    TRBAC_USER = db.relationship(
        u'TRBACUSER',
        primaryjoin='TRBACTENANTUSER.USER_ID == TRBACUSER.USER_ID',
        backref=u'trbactenantusers')


class TRBACURIOBJECT(db.Model):
    __tablename__ = 'TRBAC_URI_OBJECT'

    URI_ID = db.Column(db.String(32), primary_key=True)
    OBJ_ID = db.Column(db.ForeignKey(u'TRBAC_OBJECT.OBJ_ID'), nullable=False)
    URI = db.Column(db.Text, nullable=False, unique=True)
    URI_PATTERN = db.Column(db.Text, nullable=False)
    MEMO = db.Column(db.Text)

    TRBAC_OBJECT = db.relationship(
        u'TRBACOBJECT',
        primaryjoin='TRBACURIOBJECT.OBJ_ID == TRBACOBJECT.OBJ_ID',
        backref=u'trbacuriobjects')


class TRBACUSER(db.Model, UserMixin):
    __tablename__ = 'TRBAC_USER'

    USER_ID = db.Column(db.String(32), default=gen_uuid, primary_key=True)
    CREATER_ID = db.Column(
        db.ForeignKey(u'TRBAC_USER.USER_ID'), nullable=False)
    ORG_ID = db.Column(db.ForeignKey(u'TRBAC_ORG.ORG_ID'))
    LOGIN = db.Column(db.Text, nullable=False, unique=True)
    PASSWORD = db.Column(db.Text, nullable=False)
    NAME = db.Column(db.Text, nullable=False)
    SEX = db.Column(db.String(1))
    EMAIL = db.Column(db.Text)
    CREATE_DATE = db.Column(
        db.TIMESTAMP, server_default=func.now())  #注意这里是server_default

    parent = db.relationship(
        u'TRBACUSER',
        remote_side=[USER_ID],
        primaryjoin='TRBACUSER.CREATER_ID == TRBACUSER.USER_ID',
        backref=u'trbacusers')
    TRBAC_ORG = db.relationship(
        u'TRBACORG',
        primaryjoin='TRBACUSER.ORG_ID == TRBACORG.ORG_ID',
        backref=u'trbacusers')

    def get_id(self):
        return self.LOGIN

    def __init__(self, uid=None, name=None, passwd=None):
        self.LOGIN = uid
        self.NAME = name
        self.PASSWORD = passwd

    def __repr__(self):
        return u"User {} {} {}".format(self.LOGIN, self.NAME, self.EMAIL)


class TRBACUSERROLE(db.Model):
    __tablename__ = 'TRBAC_USER_ROLE'

    ROLE_ID = db.Column(
        db.ForeignKey(u'TRBAC_ROLE.ROLE_ID'), primary_key=True, nullable=False)
    USER_ID = db.Column(
        db.ForeignKey(u'TRBAC_USER.USER_ID'), primary_key=True, nullable=False)
    MEMO = db.Column(db.Text)

    TRBAC_ROLE = db.relationship(
        u'TRBACROLE',
        primaryjoin='TRBACUSERROLE.ROLE_ID == TRBACROLE.ROLE_ID',
        backref=u'trbacuserroles')
    TRBAC_USER = db.relationship(
        u'TRBACUSER',
        primaryjoin='TRBACUSERROLE.USER_ID == TRBACUSER.USER_ID',
        backref=u'trbacuserroles')
