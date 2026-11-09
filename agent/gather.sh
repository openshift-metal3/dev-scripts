#!/usr/bin/env bash
# shellcheck source=/dev/null
set +x
set -euo pipefail
umask 077

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

source "$SCRIPTDIR"/common.sh
source "$SCRIPTDIR"/agent/common.sh

set +x

redact() {
    awk 'BEGIN { drop=0; private=0 }
        /-----BEGIN .*PRIVATE KEY-----/ { private=1; print "REDACTED" }
        private { if ($0 ~ /-----END .*PRIVATE KEY-----/) private=0; next }
        { lower=tolower($0) }
        lower ~ /auths|"auth"[[:space:]]*:/ { drop=1 }
        drop { next }
        lower ~ /password|passwd|token|authorization|userdata|name="username"/ { print "REDACTED"; next }
        { print }'
}

limit_output() {
    awk 'BEGIN { remaining=1048576 } remaining>0 { output=substr($0 "\n",1,remaining); printf "%s",output; remaining-=length(output) }'
}

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
ssh_options=(-o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ServerAliveInterval=5 -o ServerAliveCountMax=2)
deadline=$((SECONDS + 780))
declare -A addresses=() conflicts=()
if [[ -r "${OCP_DIR}/hosts" ]]; then
    while read -r address hostname extra; do
        [[ -n "${address}" && "${address:0:1}" != '#' ]] || continue
        if [[ ! "$hostname" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ || ! "$address" =~ ^[0-9a-fA-F:.]+$ || -n "$extra" ]] ||
            ! python3 -c 'import ipaddress, sys; ipaddress.ip_address(sys.argv[1])' "$address" 2>/dev/null; then
            echo 'inventory=unknown invalid_entry' >> "$workdir/inventory.log"
            continue
        fi
        if [[ -n "${addresses[$hostname]:-}" && "${addresses[$hostname]}" != "$address" ]]; then
            conflicts[$hostname]=true
        fi
        addresses[$hostname]=$address
    done < "${OCP_DIR}/hosts"
else
    echo 'inventory=unknown unavailable' >> "$workdir/inventory.log"
fi
if ((${#addresses[@]} == 0)); then
    echo 'inventory=unknown no_usable_hosts' >> "$workdir/inventory.log"
fi
for host in "${!addresses[@]}"; do
    if [[ -n "${conflicts[$host]:-}" ]]; then
        echo "host=$host address=unknown conflicting_entries" >> "$workdir/inventory.log"
        continue
    fi
    if ((SECONDS + 345 > deadline)); then
        echo "host=$host collection=unknown budget_exhausted" >> "$workdir/inventory.log"
        continue
    fi
    ip=${addresses[$host]}
    mkdir "$workdir/$host"
    result=0
    timeout --kill-after=5 120 ssh -n "${ssh_options[@]}" "core@${ip}" agent-gather -O \
        > "agent-gather-${host}.tar.xz.partial" 2> >(redact | limit_output > "$workdir/$host/helper.log") || result=$?
    echo "helper_exit=$result" > "$workdir/$host/status.log"
    verify_result=not_run
    if ((result == 0)); then
        verify_result=0
        timeout --kill-after=5 30 tar -tJf "agent-gather-${host}.tar.xz.partial" >/dev/null 2>&1 || verify_result=$?
    fi
    echo "archive_verification_exit=$verify_result" >> "$workdir/$host/status.log"
    if ((result == 0 && verify_result == 0)); then
        mv "agent-gather-${host}.tar.xz.partial" "agent-gather-${host}.tar.xz"
        echo "Agent logs saved to agent-gather-${host}.tar.xz" >&2
        continue
    fi
    rm -f "agent-gather-${host}.tar.xz.partial"
    echo "Attempting direct guest diagnostics for $host (helper exit $result)"
    result=0
    timeout --kill-after=5 180 ssh "${ssh_options[@]}" "core@${ip}" bash -s <<'GUEST' 2>&1 | redact > "$workdir/$host/guest.log" || result=$?
set +x
set -uo pipefail
redact() {
    awk 'BEGIN { drop=0; private=0 }
        /-----BEGIN .*PRIVATE KEY-----/ { private=1; print "REDACTED" }
        private { if ($0 ~ /-----END .*PRIVATE KEY-----/) private=0; next }
        { lower=tolower($0) }
        lower ~ /auths|"auth"[[:space:]]*:/ { drop=1 }
        drop { next }
        lower ~ /password|passwd|token|authorization|userdata|name="username"/ { print "REDACTED"; next }
        { print }'
}
collect() {
    local label=$1 result
    shift
    printf '\ncommand=%s\n' "$label"
    timeout --kill-after=5 30 "$@" 2>&1 | redact | awk 'BEGIN { remaining=1048576 } remaining>0 { output=substr($0 "\n",1,remaining); printf "%s",output; remaining-=length(output) }'
    result=${PIPESTATUS[0]}
    printf '\ncommand=%s exit=%s\n' "$label" "$result"
}
unit_logs() {
    local unit=$1 state result=0
    state=$(timeout --kill-after=5 30 sudo -n systemctl show "$unit" --property=LoadState --value 2>/dev/null) || result=$?
    if ((result != 0)); then
        echo "unit=$unit state=unknown probe_exit=$result"
    elif [[ "$state" == not-found ]]; then
        echo "unit=$unit state=absent"
    elif [[ "$state" == loaded ]]; then
        echo "unit=$unit state=present"
    else
        echo "unit=$unit state=unknown"
    fi
    collect "$unit-journal" sudo -n journalctl -u "$unit" --since '2 hours ago' -n 2000 --no-pager
}
unit_logs kubelet.service
unit_logs pacemaker.service
collect pacemaker-file sudo -n tail -n 2000 /var/log/pacemaker/pacemaker.log
runtime_result=0
containers=$(timeout --kill-after=5 30 sudo -n podman ps -a --format '{{.Names}}' 2>/dev/null) || runtime_result=$?
if ((runtime_result != 0)); then
    echo "runtime=podman state=unknown probe_exit=$runtime_result"
elif grep -qx etcd <<< "$containers"; then
    collect podman-etcd sudo -n podman logs --since 2h --tail 2000 etcd
else
    echo 'runtime=podman container=etcd state=absent'
fi
runtime_result=0
containers=$(timeout --kill-after=5 30 sudo -n crictl ps -a --name etcd -q 2>/dev/null) || runtime_result=$?
if ((runtime_result != 0)); then
    echo "runtime=cri state=unknown probe_exit=$runtime_result"
elif [[ -z "$containers" ]]; then
    echo 'runtime=cri container=etcd state=absent'
else
    count=0
    while read -r container; do
        if [[ "$container" =~ ^[0-9a-f]+$ ]]; then
            collect "cri-etcd-$count" sudo -n crictl logs --tail=2000 "$container"
            count=$((count + 1))
            ((count < 2)) || break
        else
            echo 'runtime=cri state=unknown invalid_container_id'
        fi
    done <<< "$containers"
fi
GUEST
    echo "guest_exit=$result (nonzero means incomplete or unreachable, not absent)" >> "$workdir/$host/status.log"
    tar -cJf "agent-gather-fallback-${host}.tar.xz" -C "$workdir" "$host" || echo "Failed to archive diagnostics for $host" >&2
done
if [[ -f "$workdir/inventory.log" ]]; then
    tar -cJf agent-gather-fallback-inventory.tar.xz -C "$workdir" inventory.log
fi

num_tui_screenshots=$(find "${OCP_DIR}" -type f -name "*.ppm" | wc -l) || num_tui_screenshots=0
num_ui_screenshots=$(find "${OCP_DIR}" -type f -name "*.png" | wc -l) || num_ui_screenshots=0
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
    if compgen -G "${OCP_DIR}/*.ppm" > /dev/null; then
        files_to_archive+=("${OCP_DIR}"/*.ppm)
    fi

    # Include UI screenshots if in ISO_NO_REGISTRY mode
    if [[ "${AGENT_E2E_TEST_BOOT_MODE}" == "ISO_NO_REGISTRY" ]] && compgen -G "${OCP_DIR}/*.png" > /dev/null; then
        files_to_archive+=("${OCP_DIR}"/*.png)
    fi

    # Create archive with all collected files
    tar -cJf $archive_name "${files_to_archive[@]}"
else
    echo "No screenshots found. Skipping screenshot gather."
fi
