#!/usr/bin/env bash

function generate_extra_cluster_manifests() {

	mkdir -p "${EXTRA_MANIFESTS_PATH}"

	cat >"${EXTRA_MANIFESTS_PATH}/agent-test.yaml" <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: agent-test
  namespace: openshift-config
data:
  value: agent-test
EOF

	if [[ -n "${AGENT_DEPLOY_MCE}" ]]; then
		cp "${SCRIPTDIR}"/agent/mce/agent_mce_0_*.yaml "${EXTRA_MANIFESTS_PATH}"
	fi

	copy_extra_manifests "${EXTRA_MANIFESTS_PATH}"
}
