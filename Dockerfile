# syntax=docker/dockerfile:1.7
ARG MATLAB_RUNTIME_TAG=r2025b-full
FROM containers.mathworks.com/matlab-runtime:${MATLAB_RUNTIME_TAG}

ARG MATLAB_RELEASE=R2025b
ARG DEBIAN_FRONTEND=noninteractive

USER root

RUN apt-get update \
    && apt-get install --no-install-recommends -y \
        ca-certificates \
        libmagic1 \
        libzbar0 \
        python3 \
        python3-dev \
        python3-pip \
        python3-venv \
        tini \
    && rm -rf /var/lib/apt/lists/*

COPY docker/requirements.txt /tmp/acram-requirements.txt
RUN python3 -m venv /opt/acram/venv \
    && /opt/acram/venv/bin/pip install --no-cache-dir \
        -r /tmp/acram-requirements.txt \
    && rm /tmp/acram-requirements.txt

RUN groupadd --gid 10001 acram \
    && useradd --uid 10001 --gid 10001 --no-create-home \
        --home-dir /var/lib/acram --shell /usr/sbin/nologin acram \
    && install -d -o 10001 -g 10001 \
        /opt/acram/bin \
        /opt/acram/python \
        /opt/acram/resources \
        /var/lib/acram \
        /var/cache/mcr \
        /tmp/acram

# dist/bin must be produced on Linux by build_kubernetes.m.
COPY --chown=10001:10001 dist/bin/ /opt/acram/bin/

# Explicit non-secret runtime resources. Keep this list scenario-aware instead
# of copying arbitrary local CSV/JSON files from the repository root.
COPY --chown=10001:10001 \
    config_Telco3PC.json \
    config_Nokia_robot_CVE_2025.json \
    config_antonov_2025.json \
    network_telco3PC.xml \
    network_nokia_2025.xml \
    network_antonov_2025.xml \
    telco_3PC_OAF.csv \
    telco_3PC_SAB.csv \
    nokia_OAF_2025.csv \
    nokia_SAB.csv \
    antonov_OAF_2025.csv \
    influence_nokia.csv \
    fiz_OAB.fis \
    /opt/acram/resources/

COPY --chown=10001:10001 \
    fiz_AL_AS_new.mat \
    fiz_AML_AC_new.mat \
    fiz_AML_AR_new.mat \
    fiz_AML_new.mat \
    fiz_ISL_VC_new.mat \
    fiz_NT_AV_new.mat \
    fiz_OAB_AC_new.mat \
    fiz_OAB_AR_AC_AL_new.mat \
    fiz_OAB_AR_AC_new.mat \
    fiz_OAB_AR_new.mat \
    fiz_OAF_VA_new.mat \
    fiz_PRM_PR_new.mat \
    fiz_SAB_UI_AL_new.mat \
    fiz_UI_SAB_new.mat \
    /opt/acram/resources/

COPY --chown=10001:10001 smartqc/ /opt/acram/python/smartqc/
COPY --chown=10001:10001 contextchain/ /opt/acram/python/contextchain/
COPY --chown=10001:10001 docker/entrypoint.sh docker/healthcheck.sh /opt/acram/

RUN test -x /opt/acram/bin/ACRAM || chmod 0555 /opt/acram/bin/ACRAM \
    && chmod 0555 /opt/acram/entrypoint.sh /opt/acram/healthcheck.sh

ENV AGREE_TO_MATLAB_RUNTIME_LICENSE=yes \
    ACRAM_CONFIG=/etc/acram/config.json \
    ACRAM_CREDENTIALS_FILE=/etc/acram/credentials.json \
    ACRAM_CREDENTIALS_FILENAME=ws_credentials_nokia.json \
    ACRAM_HEALTH_MODE=websocket \
    ACRAM_READY_FILE=/tmp/acram/ready \
    ACRAM_STOP_FILE=/tmp/acram/stop \
    ACRAM_WORKDIR=/var/lib/acram \
    HOME=/var/lib/acram/home \
    LIBGL_ALWAYS_SOFTWARE=1 \
    MATLAB_RUNTIME_ROOT=/opt/matlabruntime/${MATLAB_RELEASE} \
    MCR_CACHE_ROOT=/var/cache/mcr \
    PATH=/opt/acram/venv/bin:${PATH} \
    PYTHONPATH=/opt/acram/python \
    PYTHONUNBUFFERED=1 \
    LD_LIBRARY_PATH=/opt/matlabruntime/${MATLAB_RELEASE}/runtime/glnxa64:/opt/matlabruntime/${MATLAB_RELEASE}/bin/glnxa64:/opt/matlabruntime/${MATLAB_RELEASE}/sys/os/glnxa64:/opt/matlabruntime/${MATLAB_RELEASE}/sys/opengl/lib/glnxa64:/opt/matlabruntime/${MATLAB_RELEASE}/extern/bin/glnxa64

WORKDIR /var/lib/acram
USER 10001:10001

ENTRYPOINT ["/usr/bin/tini", "--", "/opt/acram/entrypoint.sh"]
CMD ["/opt/acram/bin/ACRAM"]
