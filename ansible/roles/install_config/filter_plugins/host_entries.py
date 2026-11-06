"""Filter to convert ironic nodes JSON entries into install-config host dicts."""

from __future__ import annotations

from typing import Any


def to_host_entries(nodes: list[dict[str, Any]], role: str) -> list[dict[str, Any]]:
    """Map a list of ironic node dicts to install-config host entries.

    Each node in the ironic_nodes.json has the structure:
        {
            "name": "...",
            "ports": [{"address": "mac"}],
            "driver": "ipmi|redfish|idrac",
            "driver_info": {
                "username": "...",
                "password": "...",
                "address": "...",
                "redfish_verify_ca": "True|False",
            },
            "properties": {
                "boot_mode": "uefi|bios|null",
                "cpu_arch": "x86_64|aarch64",
            },
        }
    """
    result = []
    for node in nodes:
        entry: dict[str, Any] = {
            "name": node["name"],
            "role": role,
            "mac": node["ports"][0]["address"],
            "boot_mode": _boot_mode(node),
            "bmc_address": node["driver_info"]["address"],
            "bmc_username": node["driver_info"]["username"],
            "bmc_password": node["driver_info"]["password"],
        }

        driver = node.get("driver", "redfish")
        if driver not in ("ipmi", "idrac"):
            verify_ca = node["driver_info"].get("redfish_verify_ca", "True")
            if str(verify_ca).lower() == "false":
                entry["disable_certificate_verification"] = True

        result.append(entry)
    return result


def _boot_mode(node: dict[str, Any]) -> str:
    raw = node.get("properties", {}).get("boot_mode")
    if raw and raw != "null":
        return raw.upper()
    return "UEFI"


class FilterModule:
    """Ansible filter plugin registration."""

    def filters(self) -> dict[str, Any]:
        return {
            "devscripts_to_host_entries": to_host_entries,
        }
