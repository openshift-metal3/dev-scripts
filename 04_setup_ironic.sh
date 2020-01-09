#!/bin/bash

set -euxo pipefail

source logging.sh
source common.sh
source rhcos.sh
source ocp_install_env.sh

# To replace an image entry in the openshift releae image, set
# <ENTRYNAME>_LOCAL_IMAGE - where ENTRYNAME matches an uppercase version of the name in the release image
# with "-" converted to "_" e.g. to use a custom ironic-inspector
#export IRONIC_INSPECTOR_LOCAL_IMAGE=https://github.com/metal3-io/ironic-inspector-image
#export IRONIC_MACHINE_OS_DOWNLOADER_LOCAL_IMAGE=https://github.com/openshift-metal3/ironic-rhcos-downloader
#export BAREMETAL_OPERATOR_LOCAL_IMAGE=192.168.111.1:5000/localimages/bmo:latest
rm -f assets/templates/99_local-registry.yaml $OPENSHIFT_INSTALL_PATH/data/data/bootstrap/baremetal/files/etc/containers/registries.conf

# Various commands here need the Pull Secret in a file
export REGISTRY_AUTH_FILE=$(mktemp "pullsecret--XXXXXXXXXX")
{ echo "${PULL_SECRET}" ; } 2> /dev/null > $REGISTRY_AUTH_FILE

# Combine pull-secret with registry's password
COMBINED_AUTH_FILE=$(mktemp "combined-pullsecret--XXXXXXXXXX")
jq -s '.[0] * .[1]' ${REGISTRY_AUTH_FILE} ${REGISTRY_CREDS} | tee ${COMBINED_AUTH_FILE}

_local_images=
DOCKERFILE=$(mktemp "release-update--XXXXXXXXXX")
echo "FROM $OPENSHIFT_RELEASE_IMAGE" > $DOCKERFILE
for IMAGE_VAR in $(env | grep "_LOCAL_IMAGE=" | grep -o "^[^=]*") ; do
    _local_images=1
    IMAGE=${!IMAGE_VAR}

    sudo -E podman pull --authfile $COMBINED_AUTH_FILE $OPENSHIFT_RELEASE_IMAGE

    # Is it a git repo?
    if [[ "$IMAGE" =~ "://" ]] ; then
        REPOPATH=~/${IMAGE##*/}
        # Clone to ~ if not there already
        [ -e "$REPOPATH" ] || git clone $IMAGE $REPOPATH
        cd $REPOPATH
        export $IMAGE_VAR=${IMAGE##*/}:latest
        export $IMAGE_VAR=$LOCAL_REGISTRY_DNS_NAME:$LOCAL_REGISTRY_PORT/localimages/${!IMAGE_VAR}
        sudo podman build --authfile $COMBINED_AUTH_FILE -t ${!IMAGE_VAR} .
        cd -
        sudo podman push --tls-verify=false --authfile $COMBINED_AUTH_FILE ${!IMAGE_VAR} ${!IMAGE_VAR}
    fi

    IMAGE_NAME=$(echo ${IMAGE_VAR/_LOCAL_IMAGE} | tr '[:upper:]_' '[:lower:]-')
    OLDIMAGE=$(sudo podman run --rm $OPENSHIFT_RELEASE_IMAGE image $IMAGE_NAME)
    echo "RUN sed -i 's%$OLDIMAGE%${!IMAGE_VAR}%g' /release-manifests/*" >> $DOCKERFILE
done

if [ ! -z "${MIRROR_IMAGES}" ]; then

    # combine global and local secrets
    # pull from one registry and push to local one
    # hence credentials are different

    EXTRACT_DIR=$(mktemp -d "mirror-installer--XXXXXXXXXX")

    TAG=$( echo $OPENSHIFT_RELEASE_IMAGE | sed -e 's/[[:alnum:]/.]*release://' )
    MIRROR_LOG_FILE=/tmp/tmp_image_mirror-${TAG}.log

    oc adm release mirror \
       --insecure=true \
        -a ${COMBINED_AUTH_FILE}  \
        --from ${OPENSHIFT_RELEASE_IMAGE} \
        --to-release-image ${LOCAL_REGISTRY_DNS_NAME}:${LOCAL_REGISTRY_PORT}/localimages/local-release-image:latest \
        --to ${LOCAL_REGISTRY_DNS_NAME}:${LOCAL_REGISTRY_PORT}/localimages/local-release-image 2>&1 | tee ${MIRROR_LOG_FILE}

    #To ensure that you use the correct images for the version of OpenShift Container Platform that you selected,
    #you must extract the installation program from the mirrored content:
    if [ -z "$KNI_INSTALL_FROM_GIT" ]; then
      oc adm release extract --registry-config "${COMBINED_AUTH_FILE}" \
        --command=openshift-baremetal-install --to "${EXTRACT_DIR}" \
        "${LOCAL_REGISTRY_DNS_NAME}:${LOCAL_REGISTRY_PORT}/localimages/local-release-image:latest"

      mv -f "${EXTRACT_DIR}/openshift-baremetal-install" ocp/
    fi

    rm -rf "${EXTRACT_DIR}"
fi

if [ "${_local_images}" == "1" ]; then
    sudo podman image build --authfile $COMBINED_AUTH_FILE -t $OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE -f $DOCKERFILE
    sudo podman push --tls-verify=false --authfile $COMBINED_AUTH_FILE $OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE $OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE
fi
rm -f $DOCKERFILE

for name in ironic ironic-api ironic-conductor ironic-inspector dnsmasq httpd mariadb ipa-downloader vbmc sushy-tools; do
    sudo podman ps | grep -w "$name$" && sudo podman kill $name
    sudo podman ps --all | grep -w "$name$" && sudo podman rm $name -f
done

# Remove existing pod
if  sudo podman pod exists ironic-pod ; then
    sudo podman pod rm ironic-pod -f
fi

# Create pod
sudo podman pod create -n ironic-pod

IRONIC_IMAGE=${IRONIC_LOCAL_IMAGE:-$IRONIC_IMAGE}
IRONIC_IPA_DOWNLOADER_IMAGE=${IRONIC_IPA_DOWNLOADER_LOCAL_IMAGE:-$IRONIC_IPA_DOWNLOADER_IMAGE}

for IMAGE in ${IRONIC_IMAGE} ${IRONIC_IPA_DOWNLOADER_IMAGE} ${VBMC_IMAGE} ${SUSHY_TOOLS_IMAGE} ; do
    sudo -E podman pull --authfile $COMBINED_AUTH_FILE $IMAGE
done

rm -rf ${REGISTRY_AUTH_FILE}
rm -rf ${COMBINED_AUTH_FILE}

CACHED_MACHINE_OS_IMAGE="${IRONIC_DATA_DIR}/html/images/${MACHINE_OS_IMAGE_NAME}"
if [ ! -f "${CACHED_MACHINE_OS_IMAGE}" ]; then
  curl -g --insecure -L -o "${CACHED_MACHINE_OS_IMAGE}" "${MACHINE_OS_IMAGE_URL}"
  echo "${MACHINE_OS_IMAGE_SHA256} ${CACHED_MACHINE_OS_IMAGE}" | tee ${CACHED_MACHINE_OS_IMAGE}.sha256sum
  sha256sum --strict --check ${CACHED_MACHINE_OS_IMAGE}.sha256sum
fi
CACHED_MACHINE_OS_BOOTSTRAP_IMAGE="${IRONIC_DATA_DIR}/html/images/${MACHINE_OS_BOOTSTRAP_IMAGE_NAME}"
if [ ! -f "${CACHED_MACHINE_OS_BOOTSTRAP_IMAGE}" ]; then
  curl -g --insecure -L -o "${CACHED_MACHINE_OS_BOOTSTRAP_IMAGE}" "${MACHINE_OS_BOOTSTRAP_IMAGE_URL}"
  echo "${MACHINE_OS_BOOTSTRAP_IMAGE_SHA256} ${CACHED_MACHINE_OS_BOOTSTRAP_IMAGE}" | tee ${CACHED_MACHINE_OS_BOOTSTRAP_IMAGE}.sha256sum
  sha256sum --strict --check ${CACHED_MACHINE_OS_BOOTSTRAP_IMAGE}.sha256sum
fi

# cached images to the bootstrap VM
sudo podman run -d --net host --privileged --name httpd --pod ironic-pod \
     -v $IRONIC_DATA_DIR:/shared --entrypoint /bin/runhttpd ${IRONIC_IMAGE}

sudo podman run -d --net host --privileged --name ipa-downloader --pod ironic-pod \
     -v $IRONIC_DATA_DIR:/shared ${IRONIC_IPA_DOWNLOADER_IMAGE} /usr/local/bin/get-resource.sh

if [ "$NODES_PLATFORM" = "libvirt" ]; then
    sudo podman run -d --net host --privileged --name vbmc --pod ironic-pod \
         -v "$WORKING_DIR/virtualbmc/vbmc":/root/.vbmc -v "/root/.ssh":/root/ssh \
         "${VBMC_IMAGE}"

    sudo podman run -d --net host --privileged --name sushy-tools --pod ironic-pod \
         -v "$WORKING_DIR/virtualbmc/sushy-tools":/root/sushy -v "/root/.ssh":/root/ssh \
         "${SUSHY_TOOLS_IMAGE}"
fi


# Wait for the downloader containers to finish, if they are updating an existing cache
# the checks below will pass because old data exists
sudo podman wait -i 1000 ipa-downloader

# Wait for images to be downloaded/ready
while ! curl --fail http://localhost/images/${MACHINE_OS_IMAGE_NAME}.sha256sum ; do sleep 1 ; done
while ! curl --fail http://localhost/images/${MACHINE_OS_BOOTSTRAP_IMAGE_NAME}.sha256sum ; do sleep 1 ; done
while ! curl --fail --head http://localhost/images/ironic-python-agent.initramfs ; do sleep 1; done
while ! curl --fail --head http://localhost/images/ironic-python-agent.tar.headers ; do sleep 1; done
while ! curl --fail --head http://localhost/images/ironic-python-agent.kernel ; do sleep 1; done
