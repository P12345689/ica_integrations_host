# Stage 1: Base image with necessary tools
FROM registry.access.redhat.com/ubi9-minimal:9.4-1227.1726694542 as builder
LABEL name="destiny/ica_container_host" \
      version="0.8.0" \
      maintainer="Mihai Criveti <crmihai1@ie.ibm.com>" \
      description="ica_integrations_host" \
      com.redhat.license_terms="https://www.redhat.com/en/about/red-hat-end-user-license-agreements#UBI" \
      help="For more information visit https://pages.github.ibm.com/destiny/consulting_assistants_api/"

## Settings
ARG PYTHON_VERSION=3.11
ENV PYTHON_VERSION=$PYTHON_VERSION
ARG APP_LIST="all"
ENV APP_LIST=$APP_LIST

## Install dependencies
RUN microdnf -y upgrade --refresh --best --nodocs --noplugins --setopt=install_weak_deps=0 \
    && microdnf -y install --nodocs --setopt=install_weak_deps=0 git wget tar gzip python$PYTHON_VERSION gcc-c++ python$PYTHON_VERSION-devel \
    && wget https://github.com/jgm/pandoc/releases/download/3.3/pandoc-3.3-linux-amd64.tar.gz \
    && wget https://github.com/boyter/scc/releases/download/v3.4.0/scc_Linux_x86_64.tar.gz \
    && tar zxf pandoc-3.3-linux-amd64.tar.gz \
    && tar zxf scc_Linux_x86_64.tar.gz \
    && mv ./pandoc-3.3/bin/pandoc /usr/local/bin/pandoc \
    && mv ./scc /usr/local/bin/scc \
    && rm -rf pandoc-3.3-linux-amd64.tar.gz pandoc-3.3 scc_Linux_x86_64.tar.gz LICENSE README.md \
    && microdnf clean all \
    && rm -rf /var/cache/* /var/log/dnf* /var/log/yum.*

## Install Python
RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python$PYTHON_VERSION 1 \
    && useradd -u 1001 -g 0 -m -d /app -s /bin/bash default

# Stage 2: Build the application
FROM builder as application

## Copy application code
COPY --chown=1001:0 . /app

WORKDIR /app

## Update the apps
RUN chmod +x /app/build-scripts/update_apps.sh \
    && /app/build-scripts/update_apps.sh

## Prepare Python environment
RUN /bin/bash -c "\
    python3 -m venv /app/.venv \
    && . /app/.venv/bin/activate \
    && python3 -m pip install --no-cache-dir --upgrade setuptools pip pdm uv pysqlite3-binary \
    && python3 -m pip install --no-cache-dir torch==2.4.0+cpu --index-url https://download.pytorch.org/whl/cpu \
    && python3 -m uv pip install --no-cache-dir .[libica_local,routes_code_splitter,routes_sdv,routes_crew_ai,routes_python_executor,routes_autogen]"

## Change ownership
RUN mkdir -p /app/.config/icacli/ \
    && mkdir -p /.local /.cache \
    && mkdir -p /app/public/code_splitter \
    && chown -R 1001:0 /app /.local /.cache \
    && chmod -R g=u /app /.local /.cache

# Stage 3: Runtime image
FROM builder as runtime

## Change ownership
RUN mkdir -p /.local /.cache \
    && chown -R 1001:0 /.local /.cache \
    && chmod -R g=u /.local /.cache

RUN mkdir -p /.mem0 \
    && chown -R 1001:0 /.mem0 \
    && chmod -R g=u /.mem0

COPY --from=application /usr/local/bin/pandoc /usr/local/bin/pandoc
COPY --from=application /usr/local/bin/scc /usr/local/bin/scc
COPY --from=application /app /app
COPY --from=application /etc/passwd /etc/passwd

## Setup user/path
USER 1001
WORKDIR /app
ENV PATH=/app/.venv/bin:/app/bin:$PATH

# Expose port 8080
EXPOSE 8080

# Start up command for the application
CMD exec /app/run-gunicorn.sh
