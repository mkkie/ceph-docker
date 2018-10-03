# CEPH DAEMON BASE IMAGE

FROM __ENV_[BASE_IMAGE]__
MAINTAINER __DOCKERFILE_MAINTAINER__

__DOCKERFILE_TRACEABILITY_LABELS__

ENV CEPH_VERSION __ENV_[CEPH_VERSION]__
ENV CEPH_POINT_RELEASE "__ENV_[CEPH_POINT_RELEASE]__"

#======================================================
# Install ceph and dependencies, and clean up
#======================================================


# Escape char after immediately after RUN allows comment in first line
RUN \
    # Clean container, starting with record of current size (strip / from end)
    INITIAL_SIZE="$(bash -c 'sz="$(du -sm --exclude=/proc /)" ; echo "${sz%*/}"')" && \
    # Report size savings (strip / from end)
    FINAL_SIZE="$(bash -c 'sz="$(du -sm --exclude=/proc /)" ; echo "${sz%*/}"')" && \
    REMOVED_SIZE=$((INITIAL_SIZE - FINAL_SIZE)) && \
    echo "Cleaning process removed ${REMOVED_SIZE}MB" && \
    echo "Dropped container size from ${INITIAL_SIZE}MB to ${FINAL_SIZE}MB"
