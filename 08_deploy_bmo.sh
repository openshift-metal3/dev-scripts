#!/usr/bin/bash

eval "$(go env)"

source common.sh

# Get the latest bits for baremetal-operator
export BMOPATH="$GOPATH/src/github.com/metalkube/baremetal-operator"

# Make a local copy of the baremetal-operator code to make changes
cp -r $BMOPATH/deploy ocp/.
sed -i 's/bmo-project/openshift-machine-api/g' ocp/deploy/role_binding.yaml

# Kill the full ironic container on the host since it is performing DHCP and doesn't
# allow our pod in openshift to take over.
for name in ironic ironic-inspector httpd ; do 
    sudo podman ps | grep -w "$name$" && sudo podman kill $name
    sudo podman ps --all | grep -w "$name$" && sudo podman rm $name -f
done

# Restart the ironic container but only run httpd.  For now we are serving the
# images for provisioning workers from the host.  This way we don't have to copy
# or re-download the image in the pod in openshift.
sudo podman run -d --net host --privileged --name httpd \
    -v $IRONIC_DATA_DIR/dnsmasq.conf:/etc/dnsmasq.conf \
    -v $IRONIC_DATA_DIR/html/images:/var/www/html/images \
    -v $IRONIC_DATA_DIR/html/dualboot.ipxe:/var/www/html/dualboot.ipxe \
    --entrypoint /bin/bash \
    -v $IRONIC_DATA_DIR/html/inspector.ipxe:/var/www/html/inspector.ipxe ${IRONIC_IMAGE} \
    /usr/sbin/apachectl -D FOREGROUND
exit

# Start deploying on the new cluster
oc --config ocp/auth/kubeconfig apply -f ocp/deploy/service_account.yaml -n openshift-machine-api
oc --config ocp/auth/kubeconfig apply -f ocp/deploy/role.yaml -n openshift-machine-api
oc --config ocp/auth/kubeconfig apply -f ocp/deploy/role_binding.yaml -n openshift-machine-api
oc --config ocp/auth/kubeconfig apply -f ocp/deploy/crds/metalkube_v1alpha1_baremetalhost_crd.yaml -n openshift-machine-api

oc --config ocp/auth/kubeconfig adm --as system:admin policy add-scc-to-user privileged system:serviceaccount:openshift-machine-api:baremetal-operator
oc --config ocp/auth/kubeconfig apply -f ocp/deploy/operator_ironic.yaml -n openshift-machine-api
