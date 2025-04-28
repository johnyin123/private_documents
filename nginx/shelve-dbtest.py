#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import shelve
with shelve.open('iplist') as s1:
    s1['person']={"gateway": "Zero"}
    print(list(s1.keys()))
    print(s1.get('person')['gateway'])
    del s1['person']
    print(s1.get('person'))
    s1.clear()

def search_shelve(db_path, search_string):
    results = []
    with shelve.open(db_path) as db:
        for key in db:
            value = db[key]
            if isinstance(value, str):
                if search_string in value:
                    results.append(key)
            elif isinstance(value, (list, tuple)):
                for item in value:
                  if isinstance(item, str) and search_string in item:
                    results.append(key)
                    break # Avoid adding the same key multiple times for one value
            elif isinstance(value, dict):
                for item in value.values():
                  if isinstance(item, str) and search_string in item:
                    results.append(key)
                    break # Avoid adding the same key multiple times for one value
    return results




class ShelveDB:
    def __init__(self, filename: str):
        self.filename = filename

    def _open_db(self):
        """Open the shelve database."""
        return shelve.open(self.filename, writeback=True)

    def insert(self, key: str, value: dict) -> None:
        """Insert a new entry into the shelve database."""
        with self._open_db() as db:
            if key in db:
                raise KeyError(f"Key '{key}' already exists.")
            db[key] = value

    def update(self, key: str, value: dict) -> None:
        """Update an existing entry in the shelve database."""
        with self._open_db() as db:
            if key not in db:
                raise KeyError(f"Key '{key}' not found.")
            db[key] = value

    def delete(self, key: str) -> None:
        """Delete an entry from the shelve database."""
        with self._open_db() as db:
            if key not in db:
                raise KeyError(f"Key '{key}' not found.")
            del db[key]

    def search(self, key: str) -> dict:
        """Search for an entry in the shelve database."""
        with self._open_db() as db:
            return db.get(key, None)

    def list_all(self) -> dict:
        """List all entries in the shelve database."""
        with self._open_db() as db:
            return dict(db)

    def close(self):
        """Close the shelve database."""
        # shelve automatically handles file closing, but you can force it if needed
        pass
