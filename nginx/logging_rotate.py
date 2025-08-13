import logging, os
from logging.handlers import RotatingFileHandler
logHandler = RotatingFileHandler(f'logging.log', maxBytes=100, backupCount=5)
logHandler.setFormatter(logging.Formatter('%(asctime)s %(levelname)s: %(message)s'))
logger = logging.getLogger(__name__)
logger.addHandler(logHandler)
logger.setLevel(level=os.getenv('LOG', 'INFO').upper())
