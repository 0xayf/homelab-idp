#!/usr/bin/env python3
from __future__ import annotations

import argparse
import sys
from functools import reduce
from pathlib import Path

try:
    import yaml
except ImportError:
    print("PyYAML is required.", file=sys.stderr)
    sys.exit(1)

PLATFORM_CORE_PATCHES: dict[str, list[str]] = {
    "__METALLB_IP_RANGE__": ["network", "metallb_ip_range"],
    "__ARGOCD_HOSTNAME__": ["ingress", "prefixes", "argocd"],
    "__GITEA_HOSTNAME__": ["ingress", "prefixes", "gitea"],
    "__VAULT_HOSTNAME__": ["ingress", "prefixes", "vault"],
    "__MINIO_HOSTNAME__": ["ingress", "prefixes", "minio"],
    "__MINIO_API_HOSTNAME__": ["ingress", "prefixes", "minio_api"],
}


def get_required(data: dict, path: list[str]) -> str:
    dotted = ".".join(path)
    try:
        value = reduce(lambda d, k: d[k], path, data)
    except (KeyError, TypeError):
        raise KeyError(f"Missing required config value: {dotted}") from None

    if not isinstance(value, str) or not value:
        raise ValueError(f"Config value must be a non-empty string: {dotted}")
    return value


def build_hostname(prefix: str, base_domain: str) -> str:
    return f"{prefix}.{base_domain}" if prefix else base_domain


def resolve_value(placeholder: str, config: dict, base_domain: str) -> str:
    path = PLATFORM_CORE_PATCHES[placeholder]
    raw = get_required(config, path)
    if path[:2] == ["ingress", "prefixes"]:
        return build_hostname(raw, base_domain)
    return raw


def patch_files(platform_core: Path, replacements: dict[str, str]) -> list[Path]:
    patched: list[Path] = []
    for path in sorted(platform_core.rglob("values.yaml")):
        original = path.read_text()
        content = original
        for placeholder, value in replacements.items():
            content = content.replace(placeholder, value)
        if content != original:
            path.write_text(content)
            patched.append(path)
    return patched


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Render homelab config into inventory, tfvars, and platform-core values",
    )
    parser.add_argument(
        "--config",
        default="config/homelab.yml",
        help="path to homelab config YAML (default: config/homelab.yml)",
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
    base_domain = get_required(config, ["ingress", "base_domain"])

    replacements = {
        ph: resolve_value(ph, config, base_domain)
        for ph in PLATFORM_CORE_PATCHES
    }

    argocd_hostname = replacements["__ARGOCD_HOSTNAME__"]
    gitea_hostname = replacements["__GITEA_HOSTNAME__"]

    inventory_path = repo_root / "bootstrap/ansible/inventory/hosts"
    inventory_path.parent.mkdir(parents=True, exist_ok=True)
    inventory_path.write_text(f"[k3s-server]\n{server_ip}\n")

    tfvars_path = repo_root / "bootstrap/terraform/terraform.tfvars"
    tfvars_path.parent.mkdir(parents=True, exist_ok=True)
    tfvars_lines = [
        f'base_domain = "{base_domain}"',
        f'argocd_hostname = "{argocd_hostname}"',
        f'gitea_hostname = "{gitea_hostname}"',
    ]
    tfvars_path.write_text("\n".join(tfvars_lines) + "\n")

    platform_core = repo_root / "platform-core"
    patched_files = patch_files(platform_core, replacements)

    rendered = [inventory_path, tfvars_path, *patched_files]
    print("Rendered:")
    for path in rendered:
        print(f"  {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
