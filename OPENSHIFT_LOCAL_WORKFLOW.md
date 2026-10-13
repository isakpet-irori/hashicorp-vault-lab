# Local OpenShift workflow

This guide covers the local OpenShift Local (CRC) cluster and the `oc`
commands used throughout the OpenShift Vault lab. CRC runs an OpenShift
cluster inside a virtual machine on your computer; `crc` manages that local
environment, while `oc` manages resources in the cluster.

## Start, pause, and reset CRC

Start the local cluster when you want to work:

```sh
crc start
```

CRC starts its virtual machine and OpenShift services. Wait for startup to
finish, then check that `oc` is connected to the local cluster:

```sh
oc whoami
oc whoami --show-server
oc get nodes
```

When taking a break, stop the VM without deleting the cluster:

```sh
crc stop
```

Resume later with `crc start`. Cluster resources and persistent data remain
in the CRC cluster while it is stopped.

To discard the entire local cluster and create a new one:

```sh
crc delete
crc start
```

**This deletes the cluster and its resources**, including namespaces, Vault,
and persistent volumes stored in that cluster. It is not the normal way to
pause the lab. CRC may reuse locally cached installation files when creating
the cluster again.

`crc cleanup` removes CRC's host-level configuration. Use it when you are
removing CRC from the computer, not for a normal lab reset. If you also want
to remove CRC's local files, inspect `~/.crc` and remove it only after
confirming you no longer need its cached downloads or configuration.

## Use the OpenShift console and `oc`

The CRC web console is available at:

<https://console-openshift-console.apps-crc.testing>

Use `oc` to inspect the same cluster from a terminal. `oc` is OpenShift's
command-line client and provides Kubernetes-style commands such as `get`,
`describe`, and `logs`:

```sh
oc get pods -A
oc get pods -n vault-lab
oc describe pod vault-0 -n vault-lab
oc logs -n vault-lab vault-0
```

The console and `oc` are two ways to inspect and manage the same cluster.
Before running commands that modify resources, confirm the active cluster:

```sh
oc whoami --show-server
oc project
```

## Port-forwarding to Vault

Vault runs inside the OpenShift cluster. Its Kubernetes Service is normally
reachable by cluster workloads, but your Mac's browser and CLI are outside
the cluster. `oc port-forward` creates a temporary local tunnel:

```sh
oc port-forward -n vault-lab service/vault 8200:8200
```

- `service/vault` selects the Vault Service in the `vault-lab` namespace.
- The first `8200` is the port on your Mac; the second is Vault's port in the
  cluster.
- While the command runs, requests to `127.0.0.1:8200` on your Mac are
  forwarded to the Vault Service.

This lets your browser and Vault CLI reach Vault without exposing it through
a public route. Keep the port-forward terminal open while using Vault. Press
**Ctrl+C** there to close the tunnel. Start it again after stopping CRC or
restarting the Vault pod.

## Open the Vault UI in Firefox

First deploy, initialize, and unseal Vault by following the
[Vault lab guide](./OPENSHIFT_KUBERNETES_AUTH.md). Keep this port-forward
running in a terminal while using the UI:

```sh
oc port-forward -n vault-lab service/vault 8200:8200
```

The lab certificate is for `vault.vault-lab.svc`, a hostname that normally
only resolves inside the cluster. Add a temporary host mapping on your Mac so
Firefox reaches the local port-forward using the certificate's hostname. Open
`/etc/hosts` as an administrator, for example:

```sh
sudo vi /etc/hosts
```

Add this line, unless it is already present, then save and exit:

```text
# Added for Vault lab 
127.0.0.1 vault.vault-lab.svc
# End added for Vault lab
```

For minimal browser-wide changes, use a dedicated Firefox profile for this
lab. In Firefox, open `about:profiles`, choose **Create a New Profile**, name
it (for example, `Vault lab`), and launch Firefox with that profile. In that
profile, open **Settings > Privacy & Security > Certificates > View
Certificates... > Authorities > Import...**. Select
`~/.vault-openshift-lab/ca.crt` and allow it to identify websites when asked.
This trusts the lab CA in that Firefox profile only; do not import the private
key `ca.key`.

Open <https://vault.vault-lab.svc:8200/ui> in that Firefox profile. Choose
the **Token** sign-in method and enter the initial root token printed during
Vault initialization. Treat that token as a secret.

### Undo the browser setup

When finished, stop the port-forward with **Ctrl+C**. To remove the host
mapping, edit `/etc/hosts` again with `sudo nano /etc/hosts` and delete only
the `127.0.0.1 vault.vault-lab.svc` line you added.

## Vault lab certificates

The TLS setup in the
[Vault lab guide](./OPENSHIFT_KUBERNETES_AUTH.md) creates a private, local
root CA in `~/.vault-openshift-lab`. Its key (`ca.key`) signs Vault's server
certificate; Vault uses `tls.crt` and `tls.key`, while clients trust `ca.crt`.
This CA is only for the lab, not a certificate service for CRC or your system.
Keep `ca.key` and `tls.key` private.
