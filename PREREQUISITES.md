# Prerequisites

Prepare your workstation and a running OpenShift cluster before following the
[Vault lab](./OPENSHIFT_KUBERNETES_AUTH.md).

## Workstation

You need:

- A Mac supported by the version of OpenShift Local (CRC) you install, with
  hardware virtualization enabled and enough free memory and disk space for
  the CRC VM. Check the current
  [OpenShift Local requirements](https://developers.redhat.com/products/openshift-local/overview)
  before installing; requirements vary by platform and release.
- A free Red Hat account to download and use CRC.
- Internet access to download CRC and to fetch Helm charts and Terraform
  providers.
- These command-line tools installed and available on your `PATH`:
  - OpenShift CLI (`oc`), compatible with the cluster version.
  - Terraform 1.5 or later.
  - Helm 3.
  - OpenSSL 3.
  - Vault CLI.

Check the OpenSSL version with `openssl version`. macOS's system binary may
be LibreSSL rather than OpenSSL 3; if so, use an OpenSSL 3 binary such as the
Homebrew installation at `$(brew --prefix openssl@3)/bin/openssl`.

CRC includes a local OpenShift cluster, so you do not need a separate remote
cluster. If you are using another OpenShift cluster instead, you need its API
endpoint, login credentials, and permission to create the lab resources
described below.

## Start CRC and verify `oc`

For a local cluster, install CRC and complete its one-time setup as described
in the [OpenShift Local documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_local/).
Then start the VM and cluster before running any `oc` commands:

```sh
crc start
```

Wait until startup completes. On first start, CRC may ask you to choose
resources for its VM and may print login instructions. Then check that `oc`
has a working login and is targeting the CRC cluster:

```sh
crc status
oc whoami
oc whoami --show-server
oc get nodes
```

`crc status` should report the VM and OpenShift as running, and `oc get nodes`
should list a node. A stopped CRC VM is normal if you have not started it yet;
in that state `oc whoami` may report missing configuration. Run `crc start`
first, then retry the checks.

Keep CRC running while following the lab. When resuming later, run `crc start`
and verify the `oc` context again. For the everyday start/stop workflow, see
[Local OpenShift workflow](./OPENSHIFT_LOCAL_WORKFLOW.md).

## Cluster access and storage

The identity shown by `oc whoami` must be allowed to create namespaces,
deploy a Helm release, create persistent volume claims, and create Kubernetes
ServiceAccounts. The lab deploys a single Vault pod using persistent Raft
storage, so the cluster must be able to provision a persistent volume for its
claim. CRC provides a local cluster for this learning setup; on another
cluster, ask its administrator to confirm that suitable storage is available.

The Vault ServiceAccount also needs permission to call Kubernetes TokenReview.
The Helm chart configuration in the lab grants this permission. To run the
final workload-token tests, your identity must be able to request short-lived
ServiceAccount tokens with `oc create token`; ask the cluster administrator
for that permission if needed.

The lab is intended for learning, not production. Keep the generated TLS
private keys, Vault unseal key, root token, and Terraform state private.
