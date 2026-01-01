# Homelab IDP (Internal Developer Platform)

This repository contains the Infrastructure as Code to bootstrap a complete, self-hosted Internal Developer Platform on a single Kubernetes node. The platform is designed with security, idempotency, and modern GitOps principles at its core.

The bootstrap process uses a combination of Ansible and Terraform to lay the foundational infrastructure, which includes:
* **k3s** - A single-node Kubernetes cluster.
* **Cilium** - Currently only used for CNI.
* **Gitea** - A lightweight, self-hosted Git server. The source of truth of the platform.
* **ArgoCD** - The GitOps engine.


Once bootstrapped, the platform becomes self-managing via the **ArgoCD App of Apps** pattern, where ArgoCD deploys all other services (`ingress-nginx`, `cert-manager`, etc, found in `/platform`) from the configuration defined in the Gitea repository.

## Prerequisites

Before you begin, ensure you have the following installed on your local machine:

* [Terraform](https://developer.hashicorp.com/terraform/downloads)
* [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html)
* [kubectl](https://kubernetes.io/docs/tasks/tools/#kubectl)
* [Helm](https://helm.sh/docs/intro/install/)
* [jq](https://jqlang.github.io/jq/download/)

## Notes

The Ansible Galaxy Collections used to configure the machine hosting k3s were build for Ubuntu.

If you want to skip creation of the k3s server as per this repo and instead provision a cluster via your own means - be that via Kind, Minikube, or otherwise - the rest of the platform (deployed via Terraform) should be fine to use so long as:
1. Your cluster doesn't have a CNI installed that will clash with Celium, or any of the other tooling found in `/platform`. 
2. Your cluster is accessible via `kubectl`. Terraform will look for a kubectl context named `homelab`.

The Ansible Playbook provisions a minimimal k3s cluster:
```bash
kubectl get pods -A
NAMESPACE     NAME                                      READY   STATUS    RESTARTS   AGE
kube-system   coredns-6d668d687-n69dw                   1/1     Running   0          38m
kube-system   local-path-provisioner-869c44bfbd-6lfg6   1/1     Running   0          38m
kube-system   metrics-server-7bfffcd44-nws6t            1/1     Running   0          38m
```

## Bootstrap Process

Follow these steps in order to bootstrap the platform.

### Platform Configuration

Create a local config file and render generated inputs before running Ansible or Terraform.

#### 1. Copy the example config and set values
```bash
cp config/homelab.example.yml config/homelab.yml
```
Update `ingress.base_domain` and `ingress.prefixes` to control hostnames.

#### 2. Install PyYAML
```bash
python3 -m pip install pyyaml
```

#### 3. Render inventory & tfvars
```bash
python3 scripts/render-config.py
```

This generates:
- `bootstrap/ansible/inventory/hosts`
- `bootstrap/terraform/terraform.tfvars`

### Ansible Configuration

#### 1. Navigate to the Ansible directory
```bash
cd bootstrap/terraform
```

#### 3. Generate Ansible User SSH key

```bash
mkdir -p ~/.ssh/homelab
ssh-keygen -t ed25519 -f ~/.ssh/homelab/homelab_ansible -C "ansible@homelab"
```

#### 4. Ensure Target Has Python

```bash
ssh <user>@<server-ip> "sudo apt update && sudo apt install -y python3"
```

#### 4. Create Ansible Account

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

#### 5. Install k3s (and fetch kubectl config)

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

#### 6. Verify Connection

```bash
kubectl config use-context homelab
kubectl get nodes
```

### Provision Platform

This is the main automated step. It will do the following:
1. Deploy the platform core: **Cilium**, **Gitea** and **ArgoCD**.
2. Configure Gitea, creating an `argocd-bot` user, organisation and repository for your local `homelab` repository.
3. Configure ArgoCD to access Gitea via the `argocd-bot` user.
4. Clone this repository to fetch the `/platform` folder, pushing it to your Gitea server.
5. Creates an ArgoCD `ApplicationSet`, pointing to the Gitea `homelab` repository. This bootstraps ArgoCD to then provision the rest of the platform based on the state of the `homelab` repository.

#### 1. Navigate to the Terraform directory
```bash
cd bootstrap/terraform
```

#### 2. Initialise Terraform
```bash
terraform init
```

#### 3. Provision the platform resouces
```bash
terraform apply
```
Confirm with `yes` when prompted. This process will take several minutes.

### Trusting The Root CA

Trust the platform's internal Certificate Authority:

#### 1. Run the script to export the CA
```bash
./scripts/get-ca-cert.sh
```

#### 2. Import to Keychain
Double-click the generated `lab-root-ca.crt` file.

#### 3. Always Trust
Find the `lab-root-ca` certificate in Keychain Access, open it, expand the "Trust" section, and set it to **"Always Trust"**.

#### 4. Restart your browser

### Adding DNS Rules
TODO: Document this.

### Platform Applications
TODO: Finish documenting this section.

#### Gitea

Terraform will create a user named `admin` with a randonly generated password. You can access these credentials like so:
```bash
kubectl get secret -n gitea gitea-admin-credentials -o jsonpath={'.data.username'} | base64 -d
kubectl get secret -n gitea gitea-admin-credentials -o jsonpath={'.data.password'} | base64 -d
```

#### ArgoCD

Terraform will create a user named `admin` with a randonly generated password. You can access this password like so:
```bash
kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath={'.data.password'} | base64 -d
```

TODO: Document gitea-platform-repo secret.

#### Hashicorp Vault

Vault is set to auto-unseal and will create a secret named `vault-init-credentials` in the `vault` namespace containing the root token and unseal keys:
```bash
kubectl get secret -n vault vault-init-credentials -o yaml
```
```bash
apiVersion: v1
data:
  root-token: ...
  unseal-key-1: ...
  unseal-key-2: ...
  unseal-key-3: ...
kind: Secret
...
```

You should back this up, if this secret is deleted and you cannot recover the root token and/or unseal keys, you will not be able to unseal Vault and access the data stored within.

You can use the root token to log into the Vault UI:
```bash
kubectl get secret -n vault vault-init-credentials -o jsonpath={'.data.root-token'} | base64 -d
```

### Accessing The Platform

Your IDP foundation is now complete. You can access your services at (or depending on your `config/homelab.yml`):

* **ArgoCD:** `https://cd.lab`
* **Gitea:** `https://git.lab`
* **Vault:** `https://secrets.lab`

From this point forward, your platform is management via your Gitea repo.