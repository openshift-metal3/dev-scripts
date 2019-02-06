FROM docker.io/centos:centos7

RUN yum install -y python-requests
RUN curl https://raw.githubusercontent.com/openstack/tripleo-repos/master/tripleo_repos/main.py | python - current-tripleo
RUN yum install -y openstack-ironic-api openstack-ironic-conductor rabbitmq-server crudini iproute dnsmasq httpd qemu-img iscsi-initiator-utils parted gdisk
RUN mkdir -p /var/www/html/images
RUN curl http://tarballs.openstack.org/ironic-python-agent/tinyipa/tinyipa-stable-rocky.tar.gz | tar -C /var/www/html/images/ -xzf -

ARG RHCOS_IMAGE_FILENAME_OPENSTACK
ARG RHCOS_IMAGE_URL
ARG RHCOS_IMAGE_VERSION
RUN curl --insecure --compressed -L -o /var/www/html/images/${RHCOS_IMAGE_FILENAME_OPENSTACK} ${RHCOS_IMAGE_URL}/${RHCOS_IMAGE_VERSION}/${RHCOS_IMAGE_FILENAME_OPENSTACK}.gz

RUN cp /etc/ironic/ironic.conf /etc/ironic/ironic.conf_orig
RUN crudini --set /etc/ironic/ironic.conf DEFAULT auth_strategy noauth
RUN crudini --set /etc/ironic/ironic.conf DEFAULT my_ip 172.22.0.1
RUN crudini --set /etc/ironic/ironic.conf DEFAULT debug true
RUN crudini --set /etc/ironic/ironic.conf DEFAULT default_network_interface noop
RUN crudini --set /etc/ironic/ironic.conf DEFAULT enabled_boot_interfaces pxe,ipxe
RUN crudini --set /etc/ironic/ironic.conf DEFAULT default_boot_interface ipxe
RUN crudini --set /etc/ironic/ironic.conf DEFAULT default_deploy_interface direct
RUN crudini --set /etc/ironic/ironic.conf database connection sqlite:///ironic.db
RUN crudini --set /etc/ironic/ironic.conf dhcp dhcp_provider none
RUN crudini --set /etc/ironic/ironic.conf conductor automated_clean false
RUN crudini --set /etc/ironic/ironic.conf conductor api_url http://172.22.0.1:6385
RUN crudini --set /etc/ironic/ironic.conf deploy http_url http://172.22.0.1
RUN crudini --set /etc/ironic/ironic.conf deploy http_root /var/www/html/
RUN crudini --set /etc/ironic/ironic.conf deploy default_boot_option local
RUN crudini --set /etc/ironic/ironic.conf pxe ipxe_enabled true
RUN crudini --set /etc/ironic/ironic.conf pxe pxe_config_template \$pybasedir/drivers/modules/ipxe_config.template

RUN mkdir /tftpboot

RUN ironic-dbsync --config-file /etc/ironic/ironic.conf create_schema

COPY ./runironic.sh /bin/runironic
COPY ./dnsmasq.conf /etc/dnsmasq.conf
RUN chmod +x /bin/runironic

ENTRYPOINT ["/bin/runironic"]
