ARG BASE_IMAGE_FROM=ubi8

FROM $BASE_IMAGE_FROM

ARG REMOVE_OLD_REPOS=yes
ARG TEST_REPO

COPY prepare-image.sh /bin/

RUN /bin/prepare-image.sh && \
    rm /bin/prepare-image.sh

COPY $TEST_REPO /etc/yum.repos.d/

RUN dnf upgrade -y
