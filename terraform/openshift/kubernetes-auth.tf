resource "kubernetes_namespace_v1" "apps" {
  count = var.enable_kubernetes_auth ? 1 : 0

  metadata {
    name = "vault-apps"
  }
}

resource "kubernetes_service_account_v1" "orders" {
  count = var.enable_kubernetes_auth ? 1 : 0

  metadata {
    name      = "orders-api"
    namespace = kubernetes_namespace_v1.apps[0].metadata[0].name
  }
}

resource "kubernetes_service_account_v1" "payments" {
  count = var.enable_kubernetes_auth ? 1 : 0

  metadata {
    name      = "payments-api"
    namespace = kubernetes_namespace_v1.apps[0].metadata[0].name
  }
}

resource "vault_mount" "apps" {
  count = var.enable_kubernetes_auth ? 1 : 0

  path        = "apps"
  type        = "kv-v2"
  description = "Application demo secrets"
}

resource "vault_kv_secret_v2" "orders" {
  count = var.enable_kubernetes_auth ? 1 : 0

  mount = vault_mount.apps[0].path
  name  = "orders/config"

  data_json = jsonencode({
    service = "orders-api"
    region  = "lab"
  })
}

resource "vault_kv_secret_v2" "payments" {
  count = var.enable_kubernetes_auth ? 1 : 0

  mount = vault_mount.apps[0].path
  name  = "payments/config"

  data_json = jsonencode({
    service = "payments-api"
    region  = "lab"
  })
}

resource "vault_policy" "orders_read" {
  count = var.enable_kubernetes_auth ? 1 : 0

  name = "orders-api-read"

  policy = <<-EOT
    path "apps/data/orders/*" {
      capabilities = ["read"]
    }
  EOT
}

resource "vault_policy" "payments_read" {
  count = var.enable_kubernetes_auth ? 1 : 0

  name = "payments-api-read"

  policy = <<-EOT
    path "apps/data/payments/*" {
      capabilities = ["read"]
    }
  EOT
}

resource "vault_auth_backend" "kubernetes" {
  count = var.enable_kubernetes_auth ? 1 : 0

  type = "kubernetes"
}

resource "vault_kubernetes_auth_backend_config" "openshift" {
  count = var.enable_kubernetes_auth ? 1 : 0

  backend                = vault_auth_backend.kubernetes[0].path
  kubernetes_host        = "https://kubernetes.default.svc"
  disable_iss_validation = true
}

resource "vault_kubernetes_auth_backend_role" "orders" {
  count = var.enable_kubernetes_auth ? 1 : 0

  backend                          = vault_auth_backend.kubernetes[0].path
  role_name                        = "orders-api"
  bound_service_account_names      = [kubernetes_service_account_v1.orders[0].metadata[0].name]
  bound_service_account_namespaces = [kubernetes_namespace_v1.apps[0].metadata[0].name]
  token_policies                   = [vault_policy.orders_read[0].name]
  token_ttl                        = 900
  token_max_ttl                    = 3600

  depends_on = [vault_kubernetes_auth_backend_config.openshift]
}

resource "vault_kubernetes_auth_backend_role" "payments" {
  count = var.enable_kubernetes_auth ? 1 : 0

  backend                          = vault_auth_backend.kubernetes[0].path
  role_name                        = "payments-api"
  bound_service_account_names      = [kubernetes_service_account_v1.payments[0].metadata[0].name]
  bound_service_account_namespaces = [kubernetes_namespace_v1.apps[0].metadata[0].name]
  token_policies                   = [vault_policy.payments_read[0].name]
  token_ttl                        = 900
  token_max_ttl                    = 3600

  depends_on = [vault_kubernetes_auth_backend_config.openshift]
}
