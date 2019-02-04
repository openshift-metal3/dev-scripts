FROM docker.io/centos:centos7

RUN yum install -y python-requests
RUN curl https://raw.githubusercontent.com/openstack/tripleo-repos/master/tripleo_repos/main.py | python - current-tripleo
RUN yum install -y python-ironicclient python-openstackclient jq

RUN echo "#!/usr/bin/bash" > /bin/runironic_client
RUN echo "set -ex" >> /bin/runironic_client
RUN echo "export OS_TOKEN=fake-token" >> /bin/runironic_client
RUN echo "export OS_URL=http://localhost:6385/" >> /bin/runironic_client
RUN echo "openstack baremetal create /mnt/master_nodes.json" >> /bin/runironic_client
RUN echo "mkdir -p configdrive/openstack/latest" >> /bin/runironic_client
RUN echo "cp /mnt/master.ign configdrive/openstack/latest/user_data" >> /bin/runironic_client
RUN echo "for node in \$(jq -r .nodes[].name /mnt/master_nodes.json); do" >> /bin/runironic_client
RUN echo "  openstack baremetal node set \$node  --instance-info image_source=http://172.22.0.1/images/redhat-coreos-maipo-47.284-openstack.qcow2 --instance-info image_checksum=2a38fafe0b9465937955e4d054b8db3a --instance-info root_gb=25 --property root_device='{\"name\": \"/dev/vda\"}'" >> /bin/runironic_client
RUN echo "  openstack baremetal node manage \$node --wait" >> /bin/runironic_client
RUN echo "  openstack baremetal node provide \$node --wait" >> /bin/runironic_client
RUN echo "  openstack baremetal node deploy --config-drive configdrive \$node" >> /bin/runironic_client
RUN echo "done" >> /bin/runironic_client


RUN chmod +x /bin/runironic_client

ENTRYPOINT ["/bin/runironic_client"]

