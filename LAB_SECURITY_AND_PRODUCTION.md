# Lab security and production considerations

This repository is a learning lab, not a production blueprint. Its single-node
CRC cluster and simplified operations are intentional; do not copy them into
production without a separate security and reliability design.

## Main limitations

- **Availability and recovery:** Vault runs as one server with one-member Raft,
  so it is not highly available. The PVC is not a backup, and deleting the CRC
  cluster can delete Vault data. Unsealing is manual. Production needs
  redundant failure domains, protected backups, tested restores, and a
  documented unseal/recovery-key plan.
- **Root CA and private keys:** The root CA key is kept outside Vault, but a
  key stored on the same workstation is not truly offline. Protect private
  keys and passphrases; never commit them, put them in Terraform variables or
  state, or expose them in shell history and logs. Production needs controlled,
  audited root-key custody and a plan for intermediate rotation and recovery.
- **Terraform state:** State can contain sensitive Vault configuration and
  values. Do not commit or share local state, plans, or backups. Production
  needs an encrypted, access-controlled, locked backend.
- **Workload identity and secrets:** Keep each workload least-privileged.
  In this lab only Vault Agent receives the projected Kubernetes token, and
  Agent renders files into a memory-backed volume shared with the app. Any
  container mounting that volume can read its contents; memory-backed storage
  is not a security boundary. The `/config` endpoint is for fake demo values
  only—never expose real secrets through unauthenticated endpoints or logs.
- **Leaf private key:** In the PKI example, Vault Agent writes the issued leaf
  private key alongside the certificate chain to the shared volume, where the
  app can read it. This is not the intermediate CA key, but compromise of the
  app or any container mounting that volume exposes the leaf key until it is
  rotated or expires. In production, prefer TLS termination in a dedicated
  gateway or proxy with exclusive key access. If the app must terminate TLS,
  consider generating the key in the app's security boundary and having Vault
  sign its CSR; otherwise, mount the key only into the TLS-terminating
  container, restrict file permissions and pod access, and use short-lived
  certificates with tested renewal and reload procedures. A memory-backed
  volume reduces persistence but does not prevent readers from accessing the
  key.
- **Certificates and network access:** The Vault API CA and orders-app PKI
  root are separate trust chains. The app's sample PKI role and in-cluster
  issuing/CRL URLs are lab-specific; define reachable endpoints, SAN
  constraints, renewal, revocation, trust distribution, and rollover for
  production. Port-forwarding and local Firefox trust are workstation
  conveniences, not an ingress or organization-wide trust design.
- **Operations and supply chain:** CRC is a single-node development cluster.
  The lab does not provide production audit/monitoring, incident response,
  image verification, or a complete certificate-renewal SLO. Production
  requires supported and verified images, protected audit data, monitoring,
  alerting, and assigned operational ownership.

## Vault Agent sidecar and alternatives

In this lab, the Vault Agent sidecar authenticates to Vault using the pod's
projected Kubernetes token; the Python app does not authenticate to Vault.
Agent renders the permitted KV configuration and, when PKI is enabled, a
bundle containing the leaf certificate, intermediate certificate, and leaf
private key to a memory-backed volume shared with the app. The app reads the
configuration file per request and loads the TLS bundle for each new
connection, allowing Agent updates to take effect without restarting the app.
The app can read the leaf key from that volume, so the volume is not an access
boundary. If Vault is unavailable past certificate expiry, valid TLS service
cannot be maintained.

Other designs include terminating TLS at a dedicated gateway or proxy;
generating the key in the app and having Vault sign its CSR; or using
cert-manager/Vault or a CSI integration to deliver and renew certificates.
These delivery integrations do not prevent a workload that can read a
file-based key from accessing it. For stronger key isolation, use a compatible
HSM-backed or non-exportable key service and TLS terminator.

The `payments-api` identity is used for policy tests; only `orders-api` is
deployed as an application pod.

See [the main lab guide](./OPENSHIFT_KUBERNETES_AUTH.md) for implementation
details and [the prerequisites](./PREREQUISITES.md) for local setup.
