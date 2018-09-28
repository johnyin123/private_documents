# To run this code:
#
# % spark-submit \
#    --py-files databricks/apps/logs/apache_access_log.py \
#    --master local[4] \
#    databricks/apps/logs/log_analyzer_sql.py \
#    ../../data/apache.accesslog
from pyspark import SparkContext, SparkConf
from pyspark.sql import SQLContext

import ngx_accesslog
import sys

conf = SparkConf().setAppName("Log Analyzer")
sc = SparkContext(conf=conf)
sqlContext = SQLContext(sc)

logFile = sys.argv[1]

# TODO: Better parsing...
access_logs = (sc.textFile(logFile).map(ngx_accesslog.parse_ngx_log_line).cache())

#schema_access_logs = sqlContext.inferSchema(access_logs)
#schema_access_logs.registerAsTable("logs")
schema_access_logs = sqlContext.createDataFrame(access_logs)
schema_access_logs.registerTempTable("logs")

# Calculate statistics based on the content size.
content_size_stats = sqlContext.sql("SELECT %s, %s, %s, %s FROM logs" % ("SUM(body_bytes_sent) as theSum", "COUNT(*) as theCount", "MIN(body_bytes_sent) as theMin", "MAX(body_bytes_sent) as theMax"))
content_size_stats.show()

# Response Code to Count
responseCodeToCount = sqlContext.sql("SELECT status, COUNT(*) AS theCount FROM logs GROUP BY status LIMIT 100")
responseCodeToCount.show()

# Any IPAddress that has accessed the server more than 2 times.
ipAddresses = (sqlContext.sql("SELECT remote_addr, COUNT(*) AS total FROM logs GROUP BY remote_addr HAVING total > 2 LIMIT 100").rdd.map(lambda row: row[0]).collect())
print "All IPAddresses > 2 times: %s" % ipAddresses

# Top Endpoints
topEndpoints = (sqlContext
                .sql("SELECT http_host, COUNT(*) AS total FROM logs GROUP BY http_host ORDER BY total DESC LIMIT 100")
                .rdd.map(lambda row: (row[0], row[1])).collect())
print "Top Endpoints: %s" % (topEndpoints)
