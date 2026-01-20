# Ansible Galaxy Collections (ubuntu + k3s)

This guide documents the Ansible playbooks and local collections used to provision
a single-node k3s cluster.

Implementation files live in `bootstrap/ansible/`. Inventory is generated from
`config/homelab.yml` via `scripts/render-config.py`.

## Install Ansible
```bash
# Install Ansible locally
pip install --upgrade pip ansible
```

Collections are vendored in `ansible_collections/` and `ansible.cfg` already points
there - **no installation required**.

> **Warning:** Do not install the collections to `~/.ansible/collections`. Ansible
> searches user collections first, so an installed copy will shadow the vendored
> version and you won't see local changes.

## Account Types (homelab.ubuntu.create_account)

The `homelab.ubuntu.create_account` role supports creating two types of accounts:

| Type | `system_account` | Shell | SSH Key | Sudo Method | Use Case |
|------|------------------|-------|---------|-------------|----------|
| **Interactive** | `false` | `/bin/bash` | Installed to `~/.ssh/authorized_keys` | Added to `sudo` group | Human users, Ansible automation |
| **Non-interactive** | `true` | `/usr/sbin/nologin` | Not installed | Passwordless via `/etc/sudoers.d/` | Service accounts, daemons |

### Example: Interactive Account

```yaml
- name: Create Interactive Account
  hosts: k3s-server
  become: true
  vars:
    system_account: false
    account_name: deploy
    account_password: "{{ lookup('env', 'ACCOUNT_PASSWORD') }}"
    ssh_public_key: "{{ lookup('file', '~/.ssh/id_rsa.pub') }}"
    give_sudo: true
  roles:
    - role: homelab.ubuntu.create_account
```

### Example: Non-Interactive Account

```yaml
- name: Create Service Account
  hosts: k3s-server
  become: true
  vars:
    system_account: true
    account_name: myservice
    give_sudo: true
  roles:
    - role: homelab.ubuntu.create_account
```

## Modify Files

- `bootstrap/ansible/inventory/hosts` - generated from `config/homelab.yml`.
- `bootstrap/ansible/ansible.cfg` - uncomment `remote_user` and `private_key_file` if you want defaults,
  or pass them via CLI flags (`-u <user>`, `--private-key <path>`).
- `bootstrap/ansible/playbooks/create_account.yml` - account name, SSH key path, and password env var.
- `bootstrap/ansible/playbooks/delete_account.yml` - account name to remove.
- `bootstrap/ansible/playbooks/install_k3s.yml` - feature toggles (`disable_flannel`, `disable_traefik`,
  `disable_servicelb`, `disable_embedded_registry`), k3s binary version `k3s_install_version`.

## Playbook Commands

**All commands must be run from `bootstrap/ansible/`** (paths in `ansible.cfg` are relative).

Common flags:
- `-u <user>` - SSH user (required unless set in ansible.cfg)
- `--private-key <path>` - SSH private key (optional, uses ssh-agent if omitted)
- `--ask-pass` - prompt for SSH password (if not using key auth)
- `--ask-become-pass` - prompt for sudo password (if user requires it)

```bash
# Create the ansible account (set ANSIBLE_PASSWORD first)
ANSIBLE_PASSWORD='your-password' \
ansible-playbook -u <user> playbooks/create_account.yml --ask-pass --ask-become-pass

# Delete an account
ansible-playbook -u <user> playbooks/delete_account.yml --ask-pass --ask-become-pass

# Install k3s
ansible-playbook -u <user> playbooks/install_k3s.yml --ask-pass --ask-become-pass

# Fetch and merge kubeconfig (automatic during install, but can be run standalone)
ansible-playbook -u ansible playbooks/fetch_kubeconfig.yml \
  --private-key ~/.ssh/homelab/homelab_ansible \
  --ask-become-pass

# Uninstall k3s
ansible-playbook -u <user> playbooks/uninstall_k3s.yml --ask-pass --ask-become-pass
```

## From Scratch Workflow (Recommended)

### 1. Generate Ansible User SSH key

```bash
mkdir -p ~/.ssh/homelab
ssh-keygen -t ed25519 -f ~/.ssh/homelab/homelab_ansible -C "ansible@homelab"
```

### 2. Render Inventory

From the repo root, generate `inventory/hosts` using your local config:

```bash
python3 scripts/render-config.py
```

### 3. Ensure Target Has Python

```bash
ssh <user>@<server-ip> "sudo apt update && sudo apt install -y python3"
```

### 4. Create Ansible Account

Set the `ANSIBLE_PASSWORD` environment variable and run the playbook using a
bootstrap user (e.g., `ubuntu`, `root`, or your initial user):

```bash
ANSIBLE_PASSWORD='your-secure-password' \
ansible-playbook -u ubuntu playbooks/create_account.yml --ask-pass --ask-become-pass
```

This creates an `ansible` user with:
- Your SSH public key from `~/.ssh/homelab/homelab_ansible.pub`
- The password you set in `ANSIBLE_PASSWORD`
- sudo privileges

### 5. Install K3s (and fetch kubectl config)

```bash
ansible-playbook -u ansible playbooks/install_k3s.yml \
  --private-key ~/.ssh/homelab/homelab_ansible \
  --ask-become-pass
```

This installs k3s and **automatically merges the kubeconfig to your local machine** (renaming the context to `homelab`).

It also disables the following components (since we either want to use different tools, and/or manage them via ArgoCD):
- flannel (CNI)
- traefik (ingress)
- servicelb (load balancer)
- embedded-registry

### 6. Verify Connection

```bash
kubectl config use-context homelab
kubectl get nodes
```

## Role variables reference

### homelab.ubuntu.create_account

| Variable | Type | Required | Description |
|----------|------|----------|-------------|
| `account_name` | string | yes | Username to create |
| `system_account` | boolean | no | If `true`, creates a system account with `/usr/sbin/nologin` shell |
| `account_password` | string | no | Password hash (only used for interactive accounts) |
| `ssh_public_key` | string | no | SSH public key content (only used for interactive accounts) |
| `give_sudo` | boolean | no | If `true`, grants sudo. Interactive accounts join `sudo` group; system accounts get a passwordless sudoers.d file |

### homelab.ubuntu.delete_account

| Variable | Type | Required | Description |
|----------|------|----------|-------------|
| `account_name` | string | yes | Username to delete |

The role automatically removes `/etc/sudoers.d/<account_name>` if it exists.

### homelab.k3s.base

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `k3s_install_version` | string | `""` | k3s version to install (defaults to stable) |
| `disable_flannel` | boolean | `false` | Disable flannel CNI |
| `disable_traefik` | boolean | `false` | Disable traefik ingress |
| `disable_servicelb` | boolean | `false` | Disable servicelb |
| `disable_embedded_registry` | boolean | `false` | Disable embedded registry |

### homelab.k3s.fetch_config

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `local_kubeconfig` | string | `~/.kube/config` | Local path to your kubeconfig |
| `cluster_name` | string | `homelab` | Name for the cluster/context |
