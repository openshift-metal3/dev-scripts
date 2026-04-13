#!/usr/bin/env bash
# shellcheck source=/dev/null
set -euxo pipefail

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

source "$SCRIPTDIR"/common.sh
source "$SCRIPTDIR"/agent/common.sh

while read -r line
do
    ip=$( echo "$line" | cut -d " " -f 1)
    host=$( echo "$line" | cut -d " " -f 2)
    echo "Trying to gather agent logs on host ${host}"
    if ssh -n -o 'ConnectTimeout=30' -o 'StrictHostKeyChecking=no' -o 'UserKnownHostsFile=/dev/null' core@"${ip}" agent-gather -O >agent-gather-"${host}".tar.xz; then
        echo "Agent logs saved to agent-gather-${host}.tar.xz" >&2
    else
        if [ $? == 127 ]; then
            echo "Skipping gathering agent logs, agent-gather script not present on host ${host}." >&2
        fi
        rm agent-gather-"${host}".tar.xz
    fi
done < "${OCP_DIR}"/hosts

num_tui_screenshots=$(find "${OCP_DIR}" -type f -name "*.ppm" | wc -l)
num_ui_screenshots=$(find "${OCP_DIR}" -type f -name "*.png" | wc -l)
num_screenshots=$((num_tui_screenshots + num_ui_screenshots))
if [[ "$num_screenshots" -gt 0 ]]; then
    archive_name="agent-gather-console-screenshots.tar.xz"
    echo "Gathering screenshots to $archive_name"

    # Attempt to download installation logs from the UI
    if [[ "${AGENT_E2E_TEST_BOOT_MODE}" == "ISO_NO_REGISTRY" ]]; then
        echo "Attempting to download installation logs from Assisted Installer UI"
        rendezvousIP=$(getRendezvousIP)
        ocp_dir_abs_path="$(realpath "${OCP_DIR}")"

        pushd agent/isobuilder/ui_driven_cluster_installation
        RENDEZVOUS_IP="$rendezvousIP" OCP_DIR="$ocp_dir_abs_path" go run main.go --download-logs || true
        popd
    fi

    # Build list of files to archive
    files_to_archive=()

    # Always include TUI screenshots
    files_to_archive+=("${OCP_DIR}"/*.ppm)

    # Include UI screenshots if in ISO_NO_REGISTRY mode
    if [[ "${AGENT_E2E_TEST_BOOT_MODE}" == "ISO_NO_REGISTRY" ]] && compgen -G "${OCP_DIR}/*.png" > /dev/null; then
        files_to_archive+=("${OCP_DIR}"/*.png)
    fi

    # Include installation logs if available
    if [[ -f "${OCP_DIR}/installation-logs.tar" ]]; then
        files_to_archive+=("${OCP_DIR}/installation-logs.tar")
    fi

    # Create archive with all collected files
    tar -cJf $archive_name "${files_to_archive[@]}"
else
    echo "No screenshots found. Skipping screenshot gather."
fi
