# Spark 3.5 + conector de Snowflake. spark-snowflake 3.1.3 está compilado
# contra Spark 3.5 (Scala 2.12); por eso no se usa Spark 4.x.
FROM apache/spark:3.5.7-java17-python3

USER root
ARG SF_SPARK=3.1.3
ARG SF_JDBC=3.24.2
ADD https://repo1.maven.org/maven2/net/snowflake/spark-snowflake_2.12/${SF_SPARK}/spark-snowflake_2.12-${SF_SPARK}.jar /opt/spark/jars/
ADD https://repo1.maven.org/maven2/net/snowflake/snowflake-jdbc/${SF_JDBC}/snowflake-jdbc-${SF_JDBC}.jar /opt/spark/jars/
RUN chmod 644 /opt/spark/jars/spark-snowflake_2.12-${SF_SPARK}.jar /opt/spark/jars/snowflake-jdbc-${SF_JDBC}.jar
USER spark
