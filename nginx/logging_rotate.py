import logging, os
from logging.handlers import RotatingFileHandler
logHandler = RotatingFileHandler(f'logging.log', maxBytes=100, backupCount=5)
logHandler.setFormatter(logging.Formatter('%(asctime)s %(levelname)s: %(message)s'))
logger = logging.getLogger(__name__)
logger.addHandler(logHandler)
logger.setLevel(level=os.getenv('LOG', 'INFO').upper())

import importlib
module_name = 'main'
level='INFO'
try:
    module = importlib.import_module(module_name)
    target = getattr(module, 'logger')
except Exception as e:
    print(f'{e}')
else:
    target.setLevel(level)
