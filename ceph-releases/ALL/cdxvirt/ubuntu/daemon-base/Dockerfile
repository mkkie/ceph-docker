# CEPH DAEMON BASE IMAGE

FROM ubuntu:16.04
MAINTAINER Seb

# What is the actual release ? If not defined, this equals the git branch name
LABEL RELEASE="cdx-next-3.0.7"

# What was the url of the git repository
LABEL GIT_REPO="https://github.com/mkkie/ceph-docker.git"

# What was the git branch used to build this container
LABEL GIT_BRANCH="cdx-next-3.0.7"

# What was the commit ID of the current HEAD
LABEL GIT_COMMIT="41844913c5c8b27ae37f8547ccd8cb87487f8f2f"

# Was the repository clean when building ?
LABEL GIT_CLEAN="False"

# What CEPH_POINT_RELEASE has been used ?
LABEL CEPH_POINT_RELEASE=""

ENV CEPH_VERSION luminous
ENV CEPH_POINT_RELEASE ""

#======================================================
# Install ceph and dependencies, and clean up
#======================================================

ADD 'https://download.ceph.com/keys/release.asc' /tmp/ceph-release.asc

# Escape char after immediately after RUN allows comment in first line
RUN \
    # Install all components for the image, whether from packages or web downloads.
    # Typical workflow: add new repos; refresh repos; install packages; package-manager clean;
    #   download and install packages from web, cleaning any files as you go.
    # Installs should support install of ganesha for luminous without installing for jewel/kraken.
    # Add ganesha repo only if ganesha packages are defined
    # TODO: Not sure if deb-V2.5-stable is the right repo for ganesha in mimic. Revisit for mimic.
    bash -c ' \
      if [ -n "nfs-ganesha nfs-ganesha-ceph nfs-ganesha-rgw" ]; then \
        echo "deb http://download.ceph.com/nfs-ganesha/deb-V2.6-stable/$CEPH_VERSION/ xenial main" \
          | tee /etc/apt/sources.list.d/nfs-ganesha.list ; \
      fi' && \
    apt-key add /tmp/ceph-release.asc && \
    echo "deb http://download.ceph.com/debian-$CEPH_VERSION/ xenial main" | \
      tee /etc/apt/sources.list.d/ceph-$CEPH_VERSION.list && \
    DEBIAN_FRONTEND=noninteractive apt-get update && \
    # TODO: What are 'ca-certificates', 'kmod' needed for?
    DEBIAN_FRONTEND=noninteractive apt-get install -yy --force-yes --no-install-recommends \
        \
        ca-certificates \
        e2fsprogs \
        ceph-common  \
        ceph-mon  \
        ceph-osd \
        ceph-mds \
        rbd-mirror  \
        ceph-mgr\
        kmod \
        lvm2 \
        radosgw \
        nfs-ganesha nfs-ganesha-ceph nfs-ganesha-rgw \
         && \
    # Clean container, starting with record of current size (strip / from end)
    INITIAL_SIZE="$(bash -c 'sz="$(du -sm --exclude=/proc /)" ; echo "${sz%*/}"')" && \
    #
    #
    # Perform any final cleanup actions like package manager cleaning, etc.
    echo 'Postinstall cleanup' && \
     ( echo "apt clean" && DEBIAN_FRONTEND=noninteractive apt-get clean && \
      echo "apt autoclean" && DEBIAN_FRONTEND=noninteractive apt-get autoclean ) || \
      ( retval=$? && cat /var/log/apt/history.log && exit $retval ) && \
    echo 'remove unneeded apt, deb, dpkg data' && \
      rm -rf /var/lib/apt/lists/* \
             /var/cache/debconf/* \
             /var/log/apt/ \
             /var/log/dpkg.log && \
    /bin/true && \
    # Tweak some configuration files on the container system
    # disable sync with udev since the container can not contact udev
sed -i -e 's/udev_rules = 1/udev_rules = 0/' -e 's/udev_sync = 1/udev_sync = 0/' /etc/lvm/lvm.conf && \
# validate the sed command worked as expected
grep -sqo "udev_sync = 0" /etc/lvm/lvm.conf && \
grep -sqo "udev_rules = 0" /etc/lvm/lvm.conf && \
    # Clean common files like /tmp, /var/lib, etc.
    rm -rf \
        /etc/{selinux,systemd,udev} \
        /lib/{lsb,udev} \
        /tmp/* \
        /usr/lib{,64}/{locale,systemd,udev,dracut} \
        /usr/share/{doc,info,locale,man} \
        /usr/share/{bash-completion,pkgconfig/bash-completion.pc} \
        /var/log/* \
        /var/tmp/* && \
    find  / -xdev -name "*.pyc" -o -name "*.pyo" -exec rm -f {} \; && \
    # ceph-dencoder is only used for debugging, compressing it saves 10MB
    # If needed it will be decompressed
    # TODO: Is ceph-dencoder safe to remove as rook was trying to do?
    # rm -f /usr/bin/ceph-dencoder && \
    if [ -f /usr/bin/ceph-dencoder ]; then gzip -9 /usr/bin/ceph-dencoder; fi && \
    # TODO: What other ceph stuff needs removed/stripped/zipped here?
    # TODO: There was some overlap between this and the ceph clean? Where does it belong?
    #       If it's idempotent, it can *always* live here, even if it doesn't always apply
    # TODO: Should we even strip ceph libs at all?
    bash -c ' \
      function ifstrip () { if compgen -g "$1"; then strip -s "$1"; fi } && \
      ifstrip /usr/lib{,64}/ceph/erasure-code/* && \
      ifstrip /usr/lib{,64}/rados-classes/* && \
      ifstrip /usr/lib{,64}/python*/{dist,site}-packages/{rados,rbd,rgw}.*.so && \
      ifstrip /usr/bin/{crushtool,monmaptool,osdmaptool}' && \
    # Photoshop files inside a container ?
    rm -f /usr/lib/ceph/mgr/dashboard/static/AdminLTE-*/plugins/datatables/extensions/TableTools/images/psd/* && \
    # Some logfiles are not empty, there is no need to keep them
    find /var/log/ -type f -exec truncate -s 0 {} \; && \
    #
    #
    # Report size savings (strip / from end)
    FINAL_SIZE="$(bash -c 'sz="$(du -sm --exclude=/proc /)" ; echo "${sz%*/}"')" && \
    REMOVED_SIZE=$((INITIAL_SIZE - FINAL_SIZE)) && \
    echo "Cleaning process removed ${REMOVED_SIZE}MB" && \
    echo "Dropped container size from ${INITIAL_SIZE}MB to ${FINAL_SIZE}MB" && \
    #
    # Verify that the packages installed haven't been accidentally cleaned
    apt-cache show \
        ca-certificates \
        e2fsprogs \
        ceph-common  \
        ceph-mon  \
        ceph-osd \
        ceph-mds \
        rbd-mirror  \
        ceph-mgr\
        kmod \
        lvm2 \
        radosgw \
        nfs-ganesha nfs-ganesha-ceph nfs-ganesha-rgw \
        
