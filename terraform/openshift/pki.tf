variable "enable_pki" {
  description = "Create the orders-api Vault PKI intermediate and issuance role."
  type        = bool
  default     = false
}

variable "pki_intermediate_chain_path" {
  description = "Path to the offline-root-signed Vault intermediate certificate bundle."
  type        = string
  default     = ""
}

locals {
  orders_pki_active = var.enable_pki && var.pki_intermediate_chain_path != ""

  orders_pki_template = <<-EOT
    {{- with pkiCert "pki_int/issue/orders-api" "common_name=orders-api.vault-apps.svc" "alt_names=orders-api.vault-apps.svc" "ttl=1h" -}}
    {{ .Cert }}{{ .CA }}{{ .Key }}
    {{- end }}
  EOT

  orders_agent_hcl = <<-EOT
    vault {
      address = "https://vault.vault-lab.svc:8200"
      ca_cert = "/vault/config/ca.crt"
    }

    auto_auth {
      method "kubernetes" {
        mount_path = "auth/kubernetes"

        config = {
          role       = "orders-api"
          token_path = "/var/run/secrets/vault-auth/token"
        }
      }
    }

    template {
      source      = "/vault/config/orders-config.ctmpl"
      destination = "/vault/secrets/orders-config"
      perms       = "0444"
    }
  EOT

  orders_agent_hcl_with_pki = <<-EOT
    ${trimspace(local.orders_agent_hcl)}

    template {
      source      = "/vault/config/orders-tls.ctmpl"
      destination = "/vault/secrets/orders-tls.pem"
      perms       = "0440"
    }
  EOT
}

resource "vault_mount" "orders_pki" {
  count = var.enable_pki ? 1 : 0

  path                  = "pki_int"
  type                  = "pki"
  description           = "Intermediate CA for orders-api lab certificates"
  max_lease_ttl_seconds = 31536000
}

resource "vault_pki_secret_backend_intermediate_cert_request" "orders" {
  count = var.enable_pki ? 1 : 0

  backend               = vault_mount.orders_pki[0].path
  type                  = "internal"
  common_name           = "OpenShift Vault Lab Orders Intermediate"
  key_type              = "rsa"
  key_bits              = 3072
  add_basic_constraints = true
}

output "orders_pki_intermediate_csr" {
  description = "Public CSR for signing by the offline lab root CA."
  value       = var.enable_pki ? vault_pki_secret_backend_intermediate_cert_request.orders[0].csr : null
}

resource "vault_pki_secret_backend_intermediate_set_signed" "orders" {
  count = local.orders_pki_active ? 1 : 0

  backend     = vault_mount.orders_pki[0].path
  certificate = file(pathexpand(var.pki_intermediate_chain_path))

  depends_on = [vault_pki_secret_backend_intermediate_cert_request.orders]
}

resource "vault_pki_secret_backend_config_urls" "orders" {
  count = local.orders_pki_active ? 1 : 0

  backend = vault_mount.orders_pki[0].path
  issuing_certificates = [
    "https://vault.vault-lab.svc:8200/v1/pki_int/ca",
  ]
  crl_distribution_points = [
    "https://vault.vault-lab.svc:8200/v1/pki_int/crl",
  ]

  depends_on = [vault_pki_secret_backend_intermediate_set_signed.orders]
}

resource "vault_pki_secret_backend_role" "orders" {
  count = local.orders_pki_active ? 1 : 0

  backend                     = vault_mount.orders_pki[0].path
  name                        = "orders-api"
  allowed_domains             = ["orders-api.vault-apps.svc"]
  allow_bare_domains          = true
  allow_subdomains            = false
  allow_glob_domains          = false
  allow_wildcard_certificates = false
  allow_ip_sans               = false
  allow_localhost             = false
  enforce_hostnames           = true
  server_flag                 = true
  client_flag                 = false
  key_type                    = "rsa"
  key_bits                    = 2048
  ttl                         = "1h"
  max_ttl                     = "24h"

  depends_on = [vault_pki_secret_backend_intermediate_set_signed.orders]
}

resource "vault_policy" "orders_pki_issue" {
  count = local.orders_pki_active ? 1 : 0

  name = "orders-api-pki-issue"

  policy = <<-EOT
    path "pki_int/issue/orders-api" {
      capabilities = ["update"]
    }
  EOT
}
