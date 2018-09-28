#!/bin/bash

SPARK_HOME=/home/johnyin/ansible/spark/spark-2.3.1-bin-hadoop2.7
${SPARK_HOME}/bin/spark-submit \
    --py-files ngx_accesslog.py --master local[4] \
    log_analyzer_sql.py /home/johnyin/ansible/ngxtop/spark/access.log

