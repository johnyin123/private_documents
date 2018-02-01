# -*- coding: utf-8 -*-
from app import create_app
import os

app = create_app(os.path.join(os.path.dirname(os.path.abspath(__file__)), "config.json"))

if __name__ == "__main__":
    app.run(host='127.0.0.1', port=5000, use_reloader=False)
# "postgresql://{DB_USER}:{DB_PASS}@{DB_ADDR}/{DB_NAME}"
# "mysql+pymysql://{DB_USER}:{DB_PASS}@{DB_ADDR}/{DB_NAME}?charset=utf8"

del os
