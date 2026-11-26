import os
from pathlib import Path
import shutil
import subprocess
import tarfile

import pytest


ROOT = Path(__file__).resolve().parents[3]


@pytest.fixture
def gather(tmp_path):
    (tmp_path / "agent").mkdir()
    (tmp_path / "ocp").mkdir()
    (tmp_path / "bin").mkdir()
    (tmp_path / "agent/isobuilder/ui_driven_cluster_installation").mkdir(parents=True)
    (tmp_path / "ocp/auth").mkdir()
    (tmp_path / "ocp/auth/kubeconfig").write_text("EXCLUDED_CANARY")
    (tmp_path / "id_rsa").write_text("EXCLUDED_CANARY")
    shutil.copy(ROOT / "Makefile", tmp_path)
    shutil.copy(ROOT / "agent/gather.sh", tmp_path / "agent/gather.sh")
    (tmp_path / "common.sh").write_text('export OCP_DIR="$PWD/ocp"\n')
    (tmp_path / "agent/common.sh").write_text(
        'export AGENT_E2E_TEST_BOOT_MODE=${BOOT_MODE:-ISO}\ngetRendezvousIP() { echo 192.168.111.80; }\n'
    )
    (tmp_path / "ocp/hosts").write_text(
        "192.168.111.80 master-0\n192.168.111.81 master-1\n"
    )
    scripts = {
        "ssh": r'''#!/bin/bash
set -eu
printf '%s\n' "$*" >> "$CALLS"
if [[ "$*" == *agent-gather* ]]; then
    if [[ "$SCENARIO" == hang-helper ]]; then sleep 2; fi
    if [[ "$SCENARIO" == helper || "$SCENARIO" == verify-timeout ]]; then
        tar -cJf - --files-from /dev/null
        exit
    fi
    echo 'password=SYNTHETIC_SECRET' >&2
    if [[ "$SCENARIO" == oversized ]]; then python3 -c 'print("y" * 2097152)' >&2; fi
    exit 127
fi
if [[ "$SCENARIO" == hang-host ]]; then sleep 2; fi
if [[ "$*" == *192.168.111.80* ]]; then
    case "$SCENARIO" in unreachable) exit 255 ;; timeout) exit 124 ;; esac
fi
bash -s
''',
        "sudo": r'''#!/bin/bash
set -eu
shift
printf '%s\n' "$*" >> "$CALLS"
case "$1" in
systemctl)
    case "$SCENARIO" in absent) echo not-found ;; probe-error) exit 1 ;; *) echo loaded ;; esac ;;
journalctl)
    if [[ "$SCENARIO" == hang-command && "$*" == *kubelet* ]]; then trap '' TERM; sleep 2; fi
    echo 'journal useful diagnostic'
    if [[ "$SCENARIO" == oversized ]]; then python3 -c 'print("x" * 2097152)'; fi
    echo 'Authorization: SYNTHETIC_SECRET'
    printf '%s\n' '-----BEGIN PRIVATE KEY-----' 'SYNTHETIC_PEM_BODY' '-----END PRIVATE KEY-----'
    printf '%s\n' '{"auths": {' '"registry": {' '"auth": "SYNTHETIC_REGISTRY_AUTH"' '}}}'
    if [[ "$SCENARIO" == partial && "$*" == *kubelet* ]]; then exit 7; fi ;;
tail)
    echo 'pacemaker useful diagnostic'
    echo '<nvpair name="password" value="SYNTHETIC_SECRET"/>' ;;
podman)
    if [[ "$2" == ps ]]; then
        case "$SCENARIO" in absent) exit 0 ;; probe-error) exit 125 ;; *) echo etcd ;; esac
    else
        echo 'etcd useful diagnostic'
        echo 'token=SYNTHETIC_SECRET' >&2
        if [[ "$SCENARIO" == container-partial ]]; then echo 'partial stderr' >&2; exit 9; fi
    fi ;;
crictl)
    if [[ "$2" == ps ]]; then
        if [[ "$SCENARIO" == cri ]]; then printf 'abcdef\n123abc\n456abc\n'; else exit 127; fi
    else echo 'cri useful diagnostic'; fi ;;
*) exit 99 ;;
esac
''',
        "timeout": r'''#!/bin/bash
set -eu
printf 'timeout %s\n' "$*" >> "$CALLS"
duration=$2
shift 2
if [[ "$SCENARIO" == verify-timeout && "$1" == tar ]]; then exit 124; fi
if [[ ( "$SCENARIO" == hang-command && "$duration" == 30 ) ||
      ( "$SCENARIO" == hang-helper && "$duration" == 120 ) ||
      ( "$SCENARIO" == hang-host && "$duration" == 180 ) ]]; then
    exec /usr/bin/timeout --kill-after=0.05 0.05 "$@"
fi
exec "$@"
''',
        "go": '#!/bin/bash\nexit 0\n',
    }
    for name, content in scripts.items():
        target = tmp_path / "bin" / name
        target.write_text(content)
        target.chmod(0o755)

    def run(scenario="partial", inventory=None, screenshot=None):
        if inventory is not None:
            (tmp_path / "ocp/hosts").write_text(inventory)
        if scenario == "no-inventory":
            (tmp_path / "ocp/hosts").unlink()
        if scenario == "budget":
            script = tmp_path / "agent/gather.sh"
            content = script.read_text().replace(
                "deadline=$((SECONDS + 780))", "unset SECONDS\nSECONDS=0\ndeadline=345"
            )
            content = content.replace('done\nif [[ -f "$workdir/inventory.log"',
                                      '    SECONDS=1\ndone\nif [[ -f "$workdir/inventory.log"')
            script.write_text(content)
        screenshot_bytes = b"\x89PNG\r\n\x1a\n\x00\xff" if screenshot == "png" else b"P6\n1 1\n255\n\x00\xff\x00"
        if screenshot:
            (tmp_path / f"ocp/screen.{screenshot}").write_bytes(screenshot_bytes)
        environment = dict(os.environ, PATH=f"{tmp_path}/bin:{os.environ['PATH']}",
                           CALLS=str(tmp_path / "calls"), SCENARIO=scenario,
                           BOOT_MODE="ISO_NO_REGISTRY" if screenshot == "png" else "ISO")
        result = subprocess.run(["make", "agent_gather"], cwd=tmp_path,
                                env=environment, capture_output=True, text=True, timeout=15)
        assert result.returncode == 0, result.stdout + result.stderr
        archives = {}
        for archive_path in tmp_path.glob("agent-gather*.tar.xz"):
            with tarfile.open(archive_path) as archive:
                if archive_path.name == "agent-gather-console-screenshots.tar.xz":
                    assert any(member.name.endswith(f"screen.{screenshot}")
                               for member in archive.getmembers())
                archives[archive_path.name] = "\n".join(
                    archive.extractfile(member).read().decode(errors="replace")
                    for member in archive.getmembers() if member.isfile()
                )
                assert not any("auth/" in member.name or "id_rsa" in member.name
                               for member in archive.getmembers())
                for member in archive.getmembers():
                    if scenario == "oversized" and member.name.endswith("helper.log"):
                        assert member.size <= 1048576
                    if scenario == "oversized" and member.name.endswith("guest.log"):
                        assert member.size <= 2 * 1048576 + 4096
                    if member.isfile() and member.name.endswith((".png", ".ppm")):
                        assert archive.extractfile(member).read() == screenshot_bytes
                    assert "*.ppm" not in member.name
        output = result.stdout + result.stderr + "\n".join(archives.values())
        assert "SYNTHETIC_SECRET" not in output
        assert "SYNTHETIC_REGISTRY_AUTH" not in output
        assert "SYNTHETIC_PEM_BODY" not in output
        assert "EXCLUDED_CANARY" not in output
        calls = (tmp_path / "calls").read_text() if (tmp_path / "calls").exists() else ""
        return archives, calls, output

    return run


def test_missing_helper_partial_results_and_budgets(gather):
    archives, calls, _ = gather()
    assert len(archives) == 2
    for content in archives.values():
        assert "helper_exit=127" in content
        assert "command=kubelet.service-journal exit=7" in content
        assert "pacemaker useful diagnostic" in content
        assert "etcd useful diagnostic" in content
        assert "REDACTED" in content
    assert "ConnectTimeout=5" in calls
    assert "timeout --kill-after=5 120" in calls
    assert "timeout --kill-after=5 180" in calls
    assert "192.168.111.20" not in calls


@pytest.mark.parametrize("scenario,expected", [("unreachable", 255), ("timeout", 124)])
def test_failed_host_does_not_hide_other_host(gather, scenario, expected):
    archives, _, _ = gather(scenario)
    assert f"guest_exit={expected}" in archives["agent-gather-fallback-master-0.tar.xz"]
    assert "etcd useful diagnostic" in archives["agent-gather-fallback-master-1.tar.xz"]


def test_absence_is_distinct_from_probe_error(gather):
    archives, _, _ = gather("probe-error")
    for content in archives.values():
        assert "state=unknown probe_exit=1" in content
        assert "runtime=podman state=unknown probe_exit=125" in content
        assert "state=absent" not in content


def test_confirmed_absence(gather):
    archives, _, _ = gather("absent")
    for content in archives.values():
        assert "unit=kubelet.service state=absent" in content
        assert "runtime=podman container=etcd state=absent" in content


def test_cri_container_logs_are_bounded(gather):
    archives, calls, _ = gather("cri")
    assert all("cri useful diagnostic" in content for content in archives.values())
    assert "crictl logs --tail=2000 abcdef" in calls
    assert "crictl logs --tail=2000 456abc" not in calls


def test_successful_helper_remains_compatible(gather):
    archives, calls, _ = gather("helper")
    assert set(archives) == {"agent-gather-master-0.tar.xz", "agent-gather-master-1.tar.xz"}
    assert "journalctl" not in calls


@pytest.mark.parametrize("inventory", ["", "bad;address master-0\n", "192.168.111.80 ../unsafe\n"])
def test_invalid_inventory_is_archived_without_ssh(gather, inventory):
    archives, calls, _ = gather(inventory=inventory)
    assert "inventory=unknown" in archives["agent-gather-fallback-inventory.tar.xz"]
    assert not calls


def test_conflicting_inventory_does_not_fall_back_to_dhcp(gather):
    archives, calls, _ = gather(inventory="192.168.111.80 master-0\n192.168.111.20 master-0\n")
    assert "conflicting_entries" in archives["agent-gather-fallback-inventory.tar.xz"]
    assert not calls


def test_ipv6_and_repeated_inventory(gather):
    archives, calls, _ = gather(inventory="fd00::80 master-0\nfd00::80 master-0\n")
    assert len(archives) == 1
    assert "core@fd00::80" in calls
    assert sum("agent-gather -O" in line and not line.startswith("timeout ")
               for line in calls.splitlines()) == 1


def test_nonzero_container_logs_preserve_partial_output(gather):
    archives, _, _ = gather("container-partial")
    for content in archives.values():
        assert "etcd useful diagnostic" in content
        assert "partial stderr" in content
        assert "command=podman-etcd exit=9" in content
        assert "runtime=cri state=unknown" in content


@pytest.mark.parametrize("scenario", ["hang-command", "hang-helper", "hang-host"])
def test_real_timeout_enforcement(gather, scenario):
    archives, _, _ = gather(scenario)
    assert len(archives) == 2
    for content in archives.values():
        if scenario == "hang-command":
            assert "command=kubelet.service-journal exit=137" in content
            assert "etcd useful diagnostic" in content
        elif scenario == "hang-helper":
            assert "helper_exit=124" in content
            assert "etcd useful diagnostic" in content
        else:
            assert "guest_exit=124" in content


def test_verification_timeout_falls_back(gather):
    archives, _, _ = gather("verify-timeout")
    assert all("archive_verification_exit=124" in content for content in archives.values())


def test_remaining_budget_preserves_first_host_and_screenshots(gather):
    archives, _, _ = gather("budget", screenshot="ppm")
    assert sum("fallback-master" in name for name in archives) == 1
    assert "budget_exhausted" in archives["agent-gather-fallback-inventory.tar.xz"]
    assert "agent-gather-console-screenshots.tar.xz" in archives


@pytest.mark.parametrize("scenario,screenshot", [("unreachable", "ppm"), ("no-inventory", "png")])
def test_screenshots_survive_failed_collection(gather, scenario, screenshot):
    archives, _, _ = gather(scenario, screenshot=screenshot)
    assert "agent-gather-console-screenshots.tar.xz" in archives


def test_output_cap(gather):
    archives, _, _ = gather("oversized")
    for content in archives.values():
        for unit in ("kubelet.service", "pacemaker.service"):
            payload = content.split(f"command={unit}-journal\n", 1)[1]
            payload = payload.split(f"\ncommand={unit}-journal exit=", 1)[0]
            assert len(payload.encode()) == 1048576
            assert "x" * 1048000 in payload
        assert "y" * 1048576 not in content
