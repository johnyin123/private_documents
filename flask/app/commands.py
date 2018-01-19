# -*- coding: utf-8 -*-

from __future__ import print_function
import click
from .globals import db


@click.option('--num_users', default=5, help='Number of users.')
def populate_db(num_users):
    """Populates the database with seed data."""
    print("here {}".format(num_users))

def create_db():
    """Creates the database."""
    db.create_all()

def drop_db():
    """Drops the database."""
    if click.confirm('Are you sure?', abort=True):
        db.drop_all()

def recreate_db():
    """Same as running drop_db() and create_db()."""
    drop_db()
    create_db()
