#!/bin/sh
set -eux
RELEASE_IMAGE="registry.svc.ci.openshift.org/openshift/origin-release:v4.0"
if [ ! -f /.bootstrap.complete ]; then
  yum install -y crio origin-node --no-gpgcheck
  podman pull "${RELEASE_IMAGE}"
  MCO_IMAGE=$(podman run --rm --net=host -ti ${RELEASE_IMAGE} image machine-config-daemon)
  podman pull "${MCO_IMAGE}"
  podman run --privileged --rm \
    -v /ocp:/ocp \
    -v /:/rootfs -v /var/run/dbus:/var/run/dbus -v /run/systemd:/run/systemd \
    -ti "${MCO_IMAGE}" \
    start --node-name ostest-bootstrap --once-from /ocp/bootstrap.ign
fi
