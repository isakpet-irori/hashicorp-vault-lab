# HashiCorp Vault on OpenShift

A from-scratch learning lab for deploying a single-node Vault server on
OpenShift Local (CRC) or another OpenShift cluster. The final setup uses
persistent integrated Raft storage, TLS, and Kubernetes authentication for two
example workloads.

## Lab

Follow [OpenShift Vault: Raft, TLS, and Kubernetes auth](./OPENSHIFT_KUBERNETES_AUTH.md)
from the beginning. It covers cluster prerequisites, the TLS certificate,
Vault deployment and initialization, workload identities, and access tests.

For CRC start/stop, `oc`, console, and port-forward basics, see
[Local OpenShift workflow](./OPENSHIFT_LOCAL_WORKFLOW.md).

## Important

This is a disposable learning setup, not a production deployment. The Vault
server is a single node with manual unsealing. Keep the TLS private keys,
unseal key, root token, and Terraform state private. Never put real application
credentials in the demo KV values.
