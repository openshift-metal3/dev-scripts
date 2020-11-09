ARG TEST_REPO

FROM ubi8

RUN rm -f /etc/yum.repos.d/*
COPY $TEST_REPO /etc/yum.repos.d/

RUN dnf upgrade -y
