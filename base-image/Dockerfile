ARG TestRepo

FROM ubi8

RUN rm -f /etc/yum.repos.d/*
COPY ${TestRepo:-"custom.repo"} /etc/yum.repos.d/

RUN dnf upgrade -y
