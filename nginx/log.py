from functools import wraps 
import time, logging
logging.basicConfig(level=logging.DEBUG, format="%(levelname)s: %(message)s")
def debug_info(func):
    @wraps(func)
    def wrap(*args, **kwargs):
        start = time.time()
        logging.debug("start %s %s %s", func.__name__, args, kwargs)
        ret = func(*args, **kwargs)
        logging.debug("finish %s. Takes %s seconds", func.__name__, time.time() - start)
        return ret

    return wrap
