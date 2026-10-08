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

	if [[ -n "${ASSETS_EXTRA_FOLDER:-}" ]]; then
		if [[ ! -d "${ASSETS_EXTRA_FOLDER}" ]]; then
			echo "Extra manifests source is not a directory: ${ASSETS_EXTRA_FOLDER}" >&2
			return 1
		fi

		(
			shopt -s nullglob
			extra_assets=("${ASSETS_EXTRA_FOLDER}/"*)
			((${#extra_assets[@]} == 0)) || cp -- "${extra_assets[@]}" "${EXTRA_MANIFESTS_PATH}/"
		)
	fi
}
