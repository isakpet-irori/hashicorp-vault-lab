# HashiCorp Vault Learning Lab

A guided, local introduction to HashiCorp Vault. Work through the chapters in
order: start with KV and policies, learn PKI, then recreate Vault configuration
with Terraform.

The OpenShift stages can also be run entirely on your own computer with
OpenShift Local (CRC); a hosted cluster is optional. The tools and lab
software are available without a software license fee for local learning,
though CRC requires suitable hardware and a free Red Hat account, and initial
downloads require an internet connection.

## Course chapters

1. [Prerequisites and local setup](./PREREQUISITES.md) — install Docker and the
   Vault CLI, start the Compose-managed development server, and connect to it.
2. [Vault fundamentals](./VAULT_FUNDAMENTALS.md) — explore the Vault UI and
   CLI, store KV secrets, apply policies, test tokens, and configure AppRole.
3. [Vault PKI](./VAULT_PKI.md) — configure a root and intermediate CA, issue
   certificates, inspect them with OpenSSL, and explore certificate lifecycle.
4. [Terraform with Vault](./VAULT_TERRAFORM.md) — manage KV, policies, PKI,
   and AppRole configuration as code.
5. [OpenShift Stage 1 — Deploy Vault with Helm](./OPENSHIFT_VAULT.md) — deploy
   the official Vault chart to an OpenShift lab cluster.
6. [OpenShift Stage 2 — Raft and TLS](./OPENSHIFT_VAULT_RAFT_TLS.md) — replace
   dev mode with persistent integrated Raft storage and TLS.
7. [OpenShift Stage 3 — Kubernetes authentication](./OPENSHIFT_KUBERNETES_AUTH.md)
   — authenticate workloads with ServiceAccounts and narrow Vault policies.
8. [Local OpenShift workflow](./OPENSHIFT_LOCAL_WORKFLOW.md) — manage CRC,
   use the OpenShift console and `oc`, and connect to Vault with port-forwarding.

```mermaid
flowchart LR
    Setup["Local setup"] --> Fundamentals --> PKI --> Terraform
    Terraform --> OCP1["OpenShift: Helm"]
    OCP1 --> OCP2["OpenShift: Raft + TLS"]
    OCP2 --> OCP3["OpenShift: Kubernetes auth"]
```

## Suggested workflow

Complete the fundamentals and PKI chapters manually first. Then start with a
fresh local Vault development server and follow the Terraform chapter to
recreate a small lab declaratively.

> **Local learning only:** the development server uses temporary storage and a
> well-known root token. Never use the example token, generated test secrets,
> or local Terraform state for real systems or credentials.

The `policies/` folder contains policy examples used in the fundamentals
chapter.
