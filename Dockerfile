# Stage 1: Builder to prepare Flink and dependencies
FROM flink:1.20.5-scala_2.12 AS flink-builder

# Stage 2: Final image
FROM quay.io/jupyter/datascience-notebook:python-3.13

USER root

# Install runtime dependencies and apply all available security updates.
#   - ffmpeg (deb) is not required by the stack -> remove to cut scanner findings
#   - nodejs is installed from conda-forge below (avoids the ~880 Debian node-* packages)
RUN apt-get update && \
    apt-get upgrade -y --no-install-recommends && \
    apt-get install -y --no-install-recommends \
    sssd libltdl7 libkrb5-3 libgssapi-krb5-2 gnupg2 unixodbc unixodbc-dev odbcinst tdsodbc libkrb5-dev libssl-dev ca-certificates dirmngr gpg-agent wget curl \
    openjdk-11-jdk-headless bsdextrautils && \
    apt-get remove -y ffmpeg && \
    apt-get autoremove -y && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

ENV JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
ENV PATH=$JAVA_HOME/bin:$PATH
ENV FLINK_HOME=/opt/flink

# Copy Flink from builder and create symlink
COPY --from=flink-builder ${FLINK_HOME} ${FLINK_HOME}
RUN ln -s ${FLINK_HOME}/bin/flink /usr/local/bin/flink && mkdir -p ${FLINK_HOME}/plugins/s3-fs-hadoop

# Download compatible Paimon, Flink SQL Client, and S3 connector JARs into /opt/flink/lib
RUN wget -O ${FLINK_HOME}/lib/paimon-flink-1.20-1.3.2.jar https://repo.maven.apache.org/maven2/org/apache/paimon/paimon-flink-1.20/1.3.2/paimon-flink-1.20-1.3.2.jar && \
    wget -O ${FLINK_HOME}/lib/paimon-s3-1.3.2.jar https://repo.maven.apache.org/maven2/org/apache/paimon/paimon-s3/1.3.2/paimon-s3-1.3.2.jar && \
    wget -O ${FLINK_HOME}/lib/flink-sql-client-1.20.5.jar https://repo.maven.apache.org/maven2/org/apache/flink/flink-sql-client/1.20.5/flink-sql-client-1.20.5.jar && \
    wget -O ${FLINK_HOME}/lib/flink-shaded-hadoop-2-uber-2.8.3-10.0.jar https://repo.maven.apache.org/maven2/org/apache/flink/flink-shaded-hadoop-2-uber/2.8.3-10.0/flink-shaded-hadoop-2-uber-2.8.3-10.0.jar && \
    wget -O ${FLINK_HOME}/plugins/s3-fs-hadoop/flink-s3-fs-hadoop-1.20.5.jar https://repo.maven.apache.org/maven2/org/apache/flink/flink-s3-fs-hadoop/1.20.5/flink-s3-fs-hadoop-1.20.5.jar && \
    wget -O ${FLINK_HOME}/lib/flink-parquet-1.20.5.jar https://repo.maven.apache.org/maven2/org/apache/flink/flink-parquet/1.20.5/flink-parquet-1.20.5.jar

# Connectors/drivers required by the reference runtime (/opt/flink/lib listing):
# JDBC + MySQL driver, MySQL/SQLServer CDC SQL connectors, unshaded Hadoop 3.4.0 client jars.
RUN wget -O ${FLINK_HOME}/lib/flink-connector-jdbc-core-3.3.0-1.20.jar https://repo.maven.apache.org/maven2/org/apache/flink/flink-connector-jdbc-core/3.3.0-1.20/flink-connector-jdbc-core-3.3.0-1.20.jar && \
    wget -O ${FLINK_HOME}/lib/mysql-connector-j-9.3.0.jar https://repo.maven.apache.org/maven2/com/mysql/mysql-connector-j/9.3.0/mysql-connector-j-9.3.0.jar && \
    wget -O ${FLINK_HOME}/lib/flink-sql-connector-mysql-cdc-3.5.0.jar https://repo.maven.apache.org/maven2/org/apache/flink/flink-sql-connector-mysql-cdc/3.5.0/flink-sql-connector-mysql-cdc-3.5.0.jar && \
    wget -O ${FLINK_HOME}/lib/flink-sql-connector-sqlserver-cdc-3.5.0.jar https://repo.maven.apache.org/maven2/org/apache/flink/flink-sql-connector-sqlserver-cdc/3.5.0/flink-sql-connector-sqlserver-cdc-3.5.0.jar && \
    wget -O ${FLINK_HOME}/lib/hadoop-common-3.4.0.jar https://repo.maven.apache.org/maven2/org/apache/hadoop/hadoop-common/3.4.0/hadoop-common-3.4.0.jar && \
    wget -O ${FLINK_HOME}/lib/hadoop-hdfs-client-3.4.0.jar https://repo.maven.apache.org/maven2/org/apache/hadoop/hadoop-hdfs-client/3.4.0/hadoop-hdfs-client-3.4.0.jar && \
    wget -O ${FLINK_HOME}/lib/hadoop-mapreduce-client-core-3.4.0.jar https://repo.maven.apache.org/maven2/org/apache/hadoop/hadoop-mapreduce-client-core/3.4.0/hadoop-mapreduce-client-core-3.4.0.jar

# Replace the vulnerable log4j 2.24.3 jars bundled with the Flink 1.20.5 distro (CVE fixes).
# flink-table-api-java-uber / planner-loader / runtime come from the distro at 1.20.5, no override needed.
RUN cd ${FLINK_HOME}/lib && \
    wget -O log4j-api-2.25.5.jar https://repo.maven.apache.org/maven2/org/apache/logging/log4j/log4j-api/2.25.5/log4j-api-2.25.5.jar && \
    wget -O log4j-core-2.25.5.jar https://repo.maven.apache.org/maven2/org/apache/logging/log4j/log4j-core/2.25.5/log4j-core-2.25.5.jar && \
    wget -O log4j-1.2-api-2.25.5.jar https://repo.maven.apache.org/maven2/org/apache/logging/log4j/log4j-1.2-api/2.25.5/log4j-1.2-api-2.25.5.jar && \
    wget -O log4j-slf4j-impl-2.25.5.jar https://repo.maven.apache.org/maven2/org/apache/logging/log4j/log4j-slf4j-impl/2.25.5/log4j-slf4j-impl-2.25.5.jar && \
    rm -f log4j-api-2.24.3.jar log4j-core-2.24.3.jar log4j-1.2-api-2.24.3.jar log4j-slf4j-impl-2.24.3.jar && \
    chown -R ${NB_UID}:${NB_GID} ${FLINK_HOME}

# Consolidate Flink config and permissions
RUN mkdir -p /home/jovyan/.flink/logs /home/jovyan/.flink/pids && \
    chown -R ${NB_UID}:${NB_GID} ${FLINK_HOME} /home/jovyan/.flink

# The python-3.13 base already ships current builds (python 3.13.18, openssl 3.6.5).
# Install a maintained Node.js 22 from conda-forge instead of the Debian node-* packages.
# opencode-ai backs the @OpenCode ACP persona from jupyter-ai-acp-client
# (`opencode acp`, protocol v1); /etc/opencode disables self-update in the image.
RUN mamba install -y -n base -c conda-forge "nodejs=22" && \
    mamba clean -ay && \
    rm -rf /usr/local/lib/node_modules /usr/local/bin/configurable-http-proxy /usr/local/bin/glob && \
    npm install -g configurable-http-proxy cross-spawn@^7.0.5 glob@^10.5.0 requirejs@^2.3.7 npm@11 opencode-ai@1.19.6 && \
    npm cache clean --force && \
    rm -rf /opt/conda/pkgs /home/jovyan/.npm && \
    mkdir -p /etc/opencode && \
    printf '%s\n' '{"$schema":"https://opencode.ai/config.json","autoupdate":false}' > /etc/opencode/opencode.json && \
    chown -R ${NB_UID}:${NB_GID} /opt/conda /home/jovyan

# Set Flink environment variables
ENV FLINK_LOG_DIR=/home/jovyan/.flink/logs
ENV FLINK_PID_DIR=/home/jovyan/.flink/pids

USER ${NB_UID}

# Install Python dependencies
COPY --chown=${NB_UID}:${NB_GID} requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir uv && \
    uv pip install --system --no-cache-dir -r /tmp/requirements.txt && \
    rm /tmp/requirements.txt

WORKDIR ${HOME}
