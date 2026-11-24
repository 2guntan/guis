#!/usr/bin/env python3
"""Read-only deployment access check. Never prints a host or private key."""

import ipaddress
import json
import os
from pathlib import Path
import sys


KEYS = {"GUIS_VPS_HOST", "GUIS_VPS_SSH_KEY", "GUIS_VPS_SSH_KEY_PATH", "GUIS_DOMAIN"}


def read_config(path: Path) -> dict[str, str]:
    if not path.is_file():
        return {}
    values = {}
    for number, line in enumerate(path.read_text().splitlines(), 1):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            raise ValueError(f"invalid config line {number}: expected NAME=value")
        name, value = line.split("=", 1)
        name = name.strip()
        if name not in KEYS:
            raise ValueError(f"invalid config line {number}: unknown name {name}")
        values[name] = value.strip().strip('"').strip("'")
    return values


def main() -> int:
    config_path = Path(os.environ.get("GUIS_DEPLOY_CONFIG", "~/.config/guis/deploy.env")).expanduser()
    try:
        if config_path.is_file() and config_path.stat().st_mode & 0o077:
            raise ValueError("deployment config permissions must be 600 or stricter")
        config = read_config(config_path)
    except (OSError, ValueError) as error:
        print(json.dumps({"config_complete": False, "config": "invalid", "error": str(error)}))
        return 2

    values = {name: os.environ.get(name) or config.get(name, "") for name in KEYS}
    host = values["GUIS_VPS_HOST"].strip()
    key = (values["GUIS_VPS_SSH_KEY_PATH"] or values["GUIS_VPS_SSH_KEY"]).strip()
    domain = values["GUIS_DOMAIN"].strip()

    key_status = "missing"
    if key.startswith("-----BEGIN "):
        key_status = "provided_in_environment"
    elif key:
        key_status = "file_found" if Path(key).expanduser().is_file() else "file_missing"

    domain_status = "explicit" if domain and domain != "localhost" else "missing"
    if domain_status == "missing" and host:
        try:
            ip = ipaddress.ip_address(host)
            if isinstance(ip, ipaddress.IPv4Address) and ip.is_global:
                domain_status = "sslip_io_fallback"
        except ValueError:
            pass

    result = {
        "config_complete": bool(host and key_status in ("file_found", "provided_in_environment") and domain_status != "missing"),
        "config": "found" if config_path.is_file() else "absent",
        "host": "configured" if host else "missing",
        "ssh_key": key_status,
        "domain": domain_status,
    }
    print(json.dumps(result, sort_keys=True))
    return 0 if result["config_complete"] else 2


if __name__ == "__main__":
    sys.exit(main())
