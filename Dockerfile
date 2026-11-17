# Stage 1: Builder to prepare Flink and dependencies
FROM flink:1.20.3-scala_2.12 AS flink-builder

# Stage 2: Final image
FROM quay.io/jupyter/datascience-notebook:python-3.12

USER root

# Install runtime dependencies, apply all available security updates,
# and drop EOL/insecure packages shipped by the base image:
#   - ffmpeg 6.1.1 (deb): 675+ grype findings, no newer version in noble -> remove
#   - nodejs 18.19.1 + 882 Debian node modules (deb): EOL, ~160 findings -> replace with conda nodejs 22 below
RUN apt-get update && \
    apt-get upgrade -y --no-install-recommends && \
    apt-get install -y --no-install-recommends \
    sssd libltdl7 libkrb5-3 libgssapi-krb5-2 gnupg2 unixodbc unixodbc-dev odbcinst tdsodbc libkrb5-dev libssl-dev ca-certificates dirmngr gpg-agent wget curl \
    openjdk-11-jdk-headless && \
    apt-get remove -y ffmpeg nodejs npm && \
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
    wget -O ${FLINK_HOME}/lib/flink-sql-client-1.20.4.jar https://repo.maven.apache.org/maven2/org/apache/flink/flink-sql-client/1.20.4/flink-sql-client-1.20.4.jar && \
    wget -O ${FLINK_HOME}/lib/flink-shaded-hadoop-2-uber-2.8.3-10.0.jar https://repo.maven.apache.org/maven2/org/apache/flink/flink-shaded-hadoop-2-uber/2.8.3-10.0/flink-shaded-hadoop-2-uber-2.8.3-10.0.jar && \
    wget -O ${FLINK_HOME}/plugins/s3-fs-hadoop/flink-s3-fs-hadoop-1.20.4.jar https://repo.maven.apache.org/maven2/org/apache/flink/flink-s3-fs-hadoop/1.20.4/flink-s3-fs-hadoop-1.20.4.jar && \
    wget -O ${FLINK_HOME}/lib/flink-parquet-1.20.4.jar https://repo.maven.apache.org/maven2/org/apache/flink/flink-parquet/1.20.4/flink-parquet-1.20.4.jar

# Replace vulnerable jars bundled with the Flink 1.20.3 distro:
#   - log4j 2.24.3 -> 2.25.5 (CVE fixes)
#   - flink-table-api-java-uber / planner-loader / runtime 1.20.3 -> 1.20.4 (patch release)
RUN cd ${FLINK_HOME}/lib && \
    wget -O log4j-api-2.25.5.jar https://repo.maven.apache.org/maven2/org/apache/logging/log4j/log4j-api/2.25.5/log4j-api-2.25.5.jar && \
    wget -O log4j-core-2.25.5.jar https://repo.maven.apache.org/maven2/org/apache/logging/log4j/log4j-core/2.25.5/log4j-core-2.25.5.jar && \
    wget -O log4j-1.2-api-2.25.5.jar https://repo.maven.apache.org/maven2/org/apache/logging/log4j/log4j-1.2-api/2.25.5/log4j-1.2-api-2.25.5.jar && \
    wget -O log4j-slf4j-impl-2.25.5.jar https://repo.maven.apache.org/maven2/org/apache/logging/log4j/log4j-slf4j-impl/2.25.5/log4j-slf4j-impl-2.25.5.jar && \
    wget -O flink-table-api-java-uber-1.20.4.jar https://repo.maven.apache.org/maven2/org/apache/flink/flink-table-api-java-uber/1.20.4/flink-table-api-java-uber-1.20.4.jar && \
    wget -O flink-table-planner-loader-1.20.4.jar https://repo.maven.apache.org/maven2/org/apache/flink/flink-table-planner-loader/1.20.4/flink-table-planner-loader-1.20.4.jar && \
    wget -O flink-table-runtime-1.20.4.jar https://repo.maven.apache.org/maven2/org/apache/flink/flink-table-runtime/1.20.4/flink-table-runtime-1.20.4.jar && \
    rm -f log4j-api-2.24.3.jar log4j-core-2.24.3.jar log4j-1.2-api-2.24.3.jar log4j-slf4j-impl-2.24.3.jar \
          flink-table-api-java-uber-1.20.3.jar flink-table-planner-loader-1.20.3.jar flink-table-runtime-1.20.3.jar \
          flink-sql-client-1.20.3.jar flink-s3-fs-hadoop-1.20.3.jar flink-parquet-1.20.3.jar && \
    chown -R ${NB_UID}:${NB_GID} ${FLINK_HOME}

# Consolidate Flink config and permissions
RUN mkdir -p /home/jovyan/.flink/logs /home/jovyan/.flink/pids && \
    chown -R ${NB_UID}:${NB_GID} ${FLINK_HOME} /home/jovyan/.flink

# Update the conda runtime to patched builds (python 3.12.14, openssl 3.5.8 -> clears ~90 binary CVEs)
# and install a maintained Node.js 22 from conda-forge (replaces EOL Debian node 18).
RUN mamba install -y -n base -c conda-forge "python=3.12.14" "openssl=3.5.8" "ca-certificates" "nodejs=22" && \
    mamba clean -ay && \
    rm -rf /usr/local/lib/node_modules /usr/local/bin/configurable-http-proxy /usr/local/bin/glob && \
    npm install -g configurable-http-proxy cross-spawn@^7.0.5 glob@^10.5.0 requirejs@^2.3.7 && \
    npm cache clean --force && \
    chown -R ${NB_UID}:${NB_GID} /opt/conda

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
