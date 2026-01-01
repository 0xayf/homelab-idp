# Homelab Internal Developer Platform (IDP)

This repository contains the Infrastructure as Code (IaC) to bootstrap a complete, self-hosted Internal Developer Platform on a single Kubernetes node. The platform is designed with security, idempotency, and modern GitOps principles at its core.

The bootstrap process uses a combination of Ansible and Terraform to lay the foundational infrastructure, which includes:
* A **k3s** Kubernetes cluster.
* **Cilium** for CNI (networking and security).
* **Gitea** as a lightweight, self-hosted Git server.
* **ArgoCD** as the GitOps engine.

Once bootstrapped, the platform becomes self-managing via the **App of Apps** pattern, where ArgoCD deploys all other services (Ingress, Cert-Manager, etc.) from the configuration defined in the Gitea repository.

## Prerequisites

Before you begin, ensure you have the following installed on your local machine (e.g., your MBP):

* [Terraform](https://developer.hashicorp.com/terraform/downloads)
* [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html)
* [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl-macos/)
* [Helm](https://helm.sh/docs/intro/install/)
* [jq](https://jqlang.github.io/jq/download/) (for parsing JSON)
* An SSH key pair dedicated to Ansible (e.g., `~/.ssh/homelab/homelab_ansible`).

Your target server should be a fresh installation of Ubuntu with SSH access.

## Configuration

Create a local config file and render generated inputs before running Ansible or Terraform.

1.  **Copy the example config and set values:**
    ```bash
    cp config/homelab.example.yml config/homelab.yml
    ```
    Update `ingress.base_domain` and `ingress.prefixes` to control hostnames.

2.  **Install PyYAML:**
    ```bash
    python3 -m pip install pyyaml
    ```

3.  **Render inventory and tfvars:**
    ```bash
    python3 scripts/render-config.py
    ```

This generates:
- `bootstrap/ansible/inventory/hosts`
- `bootstrap/terraform/terraform.tfvars`

## Bootstrap Process

Follow these steps in order to deploy the platform from scratch.

### Step 1: Initial Server & Ansible Setup

These steps prepare the server and create the `ansible` user that Terraform will use to connect.

1.  **Generate an SSH key** for Ansible if you haven't already:
    ```bash
    ssh-keygen -t rsa -b 4096 -f ~/.ssh/homelab/homelab_ansible
    ```

2.  **SSH into your server** and prepare it for Ansible:
    ```bash
    # Replace <server-ip> with your server's IP address
    ssh user@<server-ip>
    
    # On the server:
    sudo apt update
    sudo apt install -y python3-pip
    exit
    ```

3.  **Run the `create_account` playbook** to create the `ansible` user. You will be prompted for the SSH password of your initial user and then the sudo password.
    ```bash
    # From the homelab/bootstrap/ansible/ directory
    ansible-playbook -i inventory/hosts playbooks/create_account.yml --ask-pass --ask-become-pass
    ```

### Step 2: Terraform Bootstrap

This is the main automated step. It will deploy k3s, Cilium, Gitea, and ArgoCD.

1.  **Navigate to the Terraform directory:**
    ```bash
    cd homelab/bootstrap/terraform
    ```

2.  **Initialize Terraform:** This downloads the necessary providers.
    ```bash
    terraform init
    ```

3.  **Apply the configuration:** This will run the full bootstrap process.
    ```bash
    terraform apply
    ```
    Confirm with `yes` when prompted. This process will take several minutes.

### Step 3: Configure Local `kubectl`

After Terraform completes, configure your local `kubectl` to connect to the new cluster.

1.  **Run this one-liner** on your local machine to securely copy and modify the kubeconfig file:
    ```bash
    # Use cluster.server_ip from config/homelab.yml
    ssh -i ~/.ssh/homelab/homelab_ansible ansible@<server-ip> "sudo cat /etc/rancher/k3s/k3s.yaml" | sed 's/127.0.0.1/<server-ip>/' > ~/.kube/config
    ```

2.  **Test the connection:**
    ```bash
    kubectl get nodes
    ```
    You should see your `k3s-1` node in the `Ready` state.

### Step 4: The "First Push" (Manual Git Setup)

This is the one-time manual process to seed your Gitea server with the platform configuration.

1.  **Access Gitea:** Start a port-forward to the Gitea service.
    ```bash
    kubectl port-forward svc/gitea-http -n gitea 3000:3000
    ```

2.  **Log into Gitea:**
    * Navigate to `http://localhost:3000` in your browser.
    * The username is `gitea-admin`.
    * Retrieve the password with:
        ```bash
        kubectl get secret gitea -n gitea -o jsonpath='{.data.password}' | base64 -d; echo
        ```

3.  **Create the `platform` repository:** In the Gitea UI, create a new **private** repository named `platform`.

4.  **Clone, Copy, and Push:**
    * Clone your new, empty Gitea repository to a separate directory on your machine.
        ```bash
        # Replace <password> with your Gitea admin password
        git clone http://gitea-admin:<password>@localhost:3000/gitea-admin/platform.git
        ```
    * Copy the `platform/` directory from this `homelab` repository into your newly cloned `platform` repository.
    * Commit and push the files:
        ```bash
        cd platform # Navigate into the cloned repo
        git add .
        git commit -m "feat: Initial platform configuration"
        git push
        ```

### Step 5: Seed ArgoCD (Final Manual Step)

This final step tells ArgoCD to start managing your platform.

1.  **Create a Gitea Access Token:**
    * In the Gitea UI, go to **Settings -> Applications**.
    * Generate a new token named `argocd-token`.
    * Grant it **Read** access to **repository**.
    * **Copy the generated token.**

2.  **Register the Gitea Repo in ArgoCD:**
    * Start a port-forward to the ArgoCD server:
        ```bash
        kubectl port-forward svc/argocd-server -n argocd 8080:443
        ```
    * In a new terminal, run the following command, replacing the placeholders with your Gitea admin username and the token you just created:
        ```bash
        kubectl exec -it $(kubectl get po -n argocd -l app.kubernetes.io/name=argo-cd-argocd-server -o jsonpath='{.items[0].metadata.name}') -n argocd -- \
        argocd repo add [http://gitea-http.gitea.svc.cluster.local:3000/admin/platform.git](http://gitea-http.gitea.svc.cluster.local:3000/admin/platform.git) \
        --username admin \
        --password YOUR_GITEA_TOKEN_HERE \
        --insecure-skip-server-verification
        ```

3.  **Apply the `ApplicationSet`:**
    * Apply the bootstrap manifest to your cluster. This file tells ArgoCD to start managing the applications defined in your Gitea repository.
        ```bash
        # From the homelab/platform/apps directory
        kubectl apply -f platform-appset.yaml
        ```

### Step 6: Trust the Root CA

To get the secure padlock in your browser, you must trust the platform's internal Certificate Authority.

1.  **Run the export script:**
    ```bash
    # From the homelab/scripts directory (or wherever you save it)
    ./scripts/get-ca-cert.sh
    ```
2.  **Import to Keychain:** Double-click the generated `homelab-root-ca.crt` file.
3.  **Always Trust:** Find the `homelab-root-ca` certificate in Keychain Access, open it, expand the "Trust" section, and set it to **"Always Trust"**.
4.  **Restart your browser.**

## Accessing the Platform

Your IDP foundation is now complete. You can access your services at:

* **ArgoCD:** `https://cd.homelab`
* **Gitea:** `https://git.homelab`

From this point forward, all new applications and configurations are managed by adding or editing files in your `platform` Git repository.

### Step 7: Initialise Vault

Run the vault operator init command inside the vault pod. This creates the master key and the initial root token.
```
kubectl exec -it vault-0 -n vault -- vault operator init
```
The output of the init command is extremely important. It will look something like this:
```
Unseal Key 1: j4H...
Unseal Key 2: a8f...
Unseal Key 3: 7rM...
Unseal Key 4: z9P...
Unseal Key 5: b2K...

Initial Root Token: s.ABC...
```
You must copy this entire block of text and save it somewhere safe. This is the only time these unseal keys and the initial root token will ever be displayed. If you lose them, you will lose all data in Vault.

## Step 8: Unseal Vault

To unlock Vault, you need to provide 3 of the 5 unseal keys. Run the following command three times, pasting a different unseal key each time when prompted.
```
kubectl exec -it vault-0 -n vault -- vault operator unseal <key_1>
kubectl exec -it vault-0 -n vault -- vault operator unseal <key_2>
kubectl exec -it vault-0 -n vault -- vault operator unseal <key_3>
```
After the third key, you will see the sealed status change to false; vault is now unseal:
```
Key             Value
---             -----
Seal Type       shamir
Initialized     true
*Sealed*          *false*
...
```