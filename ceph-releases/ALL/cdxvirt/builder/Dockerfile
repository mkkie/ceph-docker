FROM ubuntu:16.04

RUN apt-get update && \
    apt-get install make python3 git -y && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN echo '#!/bin/bash' >> /usr/local/sbin/docker && \
    echo 'LD_LIBRARY_PATH=/lib:/host/lib /bin/docker $@' >> /usr/local/sbin/docker && \
    chmod +x /usr/local/sbin/docker

RUN mkdir -p /ceph-container

WORKDIR /ceph-container
