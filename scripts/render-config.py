#!/usr/bin/env python3
from __future__ import annotations

import argparse
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    print("PyYAML is required. Install with: python3 -m pip install pyyaml", file=sys.stderr)
    sys.exit(1)


def get_required(data: dict, path: list[str]) -> str:
    cursor = data
    for key in path:
        if not isinstance(cursor, dict) or key not in cursor:
            joined = ".".join(path)
            raise KeyError(f"Missing required config value: {joined}")
        cursor = cursor[key]
    if cursor in (None, ""):
        joined = ".".join(path)
        raise ValueError(f"Config value is empty: {joined}")
    if not isinstance(cursor, str):
        joined = ".".join(path)
        raise TypeError(f"Config value must be a string: {joined}")
    return cursor


def join_hostname(prefix: str, base_domain: str) -> str:
    if not prefix:
        return base_domain
    return f"{prefix}.{base_domain}"


def main() -> int:
    parser = argparse.ArgumentParser(description="Render homelab config into inventory and tfvars")
    parser.add_argument(
        "--config",
        default="config/homelab.yml",
        help="Path to homelab config YAML (default: config/homelab.yml)",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[1]
    config_path = Path(args.config)
    if not config_path.is_absolute():
        config_path = repo_root / config_path

    if not config_path.exists():
        print(f"Config file not found: {config_path}", file=sys.stderr)
        return 1

    config = yaml.safe_load(config_path.read_text()) or {}

    server_ip = get_required(config, ["cluster", "server_ip"])
    metallb_ip_range = get_required(config, ["network", "metallb_ip_range"])
    base_domain = get_required(config, ["ingress", "base_domain"])
    argocd_prefix = get_required(config, ["ingress", "prefixes", "argocd"])
    gitea_prefix = get_required(config, ["ingress", "prefixes", "gitea"])
    vault_prefix = get_required(config, ["ingress", "prefixes", "vault"])

    argocd_hostname = join_hostname(argocd_prefix, base_domain)
    gitea_hostname = join_hostname(gitea_prefix, base_domain)
    vault_hostname = join_hostname(vault_prefix, base_domain)

    inventory_path = repo_root / "bootstrap/ansible/inventory/hosts"
    inventory_path.parent.mkdir(parents=True, exist_ok=True)
    inventory_path.write_text(f"[k3s-server]\n{server_ip}\n")

    tfvars_path = repo_root / "bootstrap/terraform/terraform.tfvars"
    tfvars_path.parent.mkdir(parents=True, exist_ok=True)
    tfvars_path.write_text(
        "\n".join(
            [
                f"base_domain = \"{base_domain}\"",
                f"argocd_hostname = \"{argocd_hostname}\"",
                f"gitea_hostname = \"{gitea_hostname}\"",
                f"vault_hostname = \"{vault_hostname}\"",
                f"metallb_ip_range = \"{metallb_ip_range}\"",
                "",
            ]
        )
    )

    print("Rendered:")
    print(f"- {inventory_path}")
    print(f"- {tfvars_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
