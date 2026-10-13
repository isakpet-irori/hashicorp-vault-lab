terraform {
  required_version = ">= 1.11.0"

  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.0"
    }
  }
}

provider "vault" {}

variable "app_password" {
  type      = string
  sensitive = true
  ephemeral = true
}

resource "vault_mount" "kv" {
  path        = "learning-kv"
  type        = "kv-v2"
  description = "KV v2 engine managed by Terraform"
}

resource "vault_kv_secret_v2" "myapp" {
  mount = vault_mount.kv.path
  name  = "myapp"

  data_json_wo = jsonencode({
    username = "alice"
    password = var.app_password
  })
  data_json_wo_version = 1
}

resource "vault_policy" "myapp_read" {
  name = "terraform-myapp-read"

  policy = <<-EOT
    path "learning-kv/data/myapp" {
      capabilities = ["read"]
    }
  EOT
}

resource "vault_mount" "pki" {
  path                  = "learning-pki"
  type                  = "pki"
  description           = "PKI engine managed by Terraform"
  max_lease_ttl_seconds = 315360000
}

resource "vault_mount" "pki_intermediate" {
  path                  = "learning-pki-int"
  type                  = "pki"
  description           = "Intermediate PKI engine managed by Terraform"
  max_lease_ttl_seconds = 157680000
}

resource "vault_pki_secret_backend_root_cert" "root" {
  backend     = vault_mount.pki.path
  type        = "internal"
  common_name = "Terraform Learning Lab Root CA"
  ttl         = "315360000"
  key_type    = "rsa"
  key_bits    = 2048
}

resource "vault_pki_secret_backend_intermediate_cert_request" "intermediate" {
  backend     = vault_mount.pki_intermediate.path
  type        = "internal"
  common_name = "Terraform Learning Lab Intermediate CA"
  key_type    = "rsa"
  key_bits    = 2048
}

resource "vault_pki_secret_backend_root_sign_intermediate" "intermediate" {
  depends_on      = [vault_pki_secret_backend_root_cert.root]
  backend         = vault_mount.pki.path
  csr             = vault_pki_secret_backend_intermediate_cert_request.intermediate.csr
  common_name     = "Terraform Learning Lab Intermediate CA"
  ttl             = "157680000"
  max_path_length = 0
}

resource "vault_pki_secret_backend_intermediate_set_signed" "intermediate" {
  backend     = vault_mount.pki_intermediate.path
  certificate = vault_pki_secret_backend_root_sign_intermediate.intermediate.certificate
}

resource "vault_pki_secret_backend_config_issuers" "intermediate" {
  backend = vault_mount.pki_intermediate.path
  default = vault_pki_secret_backend_intermediate_set_signed.intermediate.imported_issuers[0]
}

resource "vault_pki_secret_backend_role" "internal_services" {
  depends_on       = [vault_pki_secret_backend_config_issuers.intermediate]
  backend          = vault_mount.pki_intermediate.path
  name             = "internal-services"
  ttl              = 86400
  allowed_domains  = ["example.internal"]
  allow_subdomains = true
  max_ttl          = 259200
  key_type         = "rsa"
  key_bits         = 2048
  server_flag      = true
  client_flag      = false
}

resource "vault_auth_backend" "approle" {
  type = "approle"
}

resource "vault_approle_auth_backend_role" "myapp" {
  backend        = vault_auth_backend.approle.path
  role_name      = "terraform-myapp"
  token_policies = [vault_policy.myapp_read.name]
  token_ttl      = 3600
  token_max_ttl  = 14400
  bind_secret_id = true
}
