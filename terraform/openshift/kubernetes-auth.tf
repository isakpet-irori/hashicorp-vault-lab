resource "kubernetes_namespace_v1" "apps" {
  count = var.enable_kubernetes_auth ? 1 : 0

  metadata {
    name = "vault-apps"
  }

  lifecycle {
    ignore_changes = [metadata[0].annotations]
  }
}

resource "kubernetes_service_account_v1" "orders" {
  count = var.enable_kubernetes_auth ? 1 : 0

  metadata {
    name      = "orders-api"
    namespace = kubernetes_namespace_v1.apps[0].metadata[0].name
  }

  lifecycle {
    ignore_changes = [metadata[0].annotations, image_pull_secret, secret]
  }
}

resource "kubernetes_config_map_v1" "orders_app" {
  count = var.enable_kubernetes_auth ? 1 : 0

  metadata {
    name      = "orders-api-app"
    namespace = kubernetes_namespace_v1.apps[0].metadata[0].name
  }

  data = {
    "app.py" = file("${path.module}/../../apps/orders-api/app.py")
  }
}

resource "kubernetes_config_map_v1" "orders_agent_config" {
  count = var.enable_kubernetes_auth ? 1 : 0

  metadata {
    name      = "orders-api-vault-agent"
    namespace = kubernetes_namespace_v1.apps[0].metadata[0].name
  }

  data = merge({
    "agent.hcl" = local.orders_pki_active ? local.orders_agent_hcl_with_pki : local.orders_agent_hcl

    "orders-config.ctmpl" = <<-EOT
      {{- with secret "apps/data/orders/config" }}
      service={{ .Data.data.service }}
      region={{ .Data.data.region }}
      {{- end }}
    EOT

    "ca.crt" = file(pathexpand("~/.vault-openshift-lab/ca.crt"))
    }, local.orders_pki_active ? {
    "orders-tls.ctmpl" = local.orders_pki_template
  } : {})

  depends_on = [
    vault_pki_secret_backend_role.orders,
    vault_kubernetes_auth_backend_role.orders,
  ]
}

resource "kubernetes_deployment_v1" "orders" {
  count = var.enable_kubernetes_auth ? 1 : 0

  metadata {
    name      = "orders-api"
    namespace = kubernetes_namespace_v1.apps[0].metadata[0].name
    labels = {
      app = "orders-api"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "orders-api"
      }
    }

    template {
      metadata {
        labels = {
          app = "orders-api"
        }
      }

      spec {
        service_account_name            = kubernetes_service_account_v1.orders[0].metadata[0].name
        automount_service_account_token = false

        security_context {
          run_as_non_root = true

          seccomp_profile {
            type = "RuntimeDefault"
          }
        }

        container {
          name              = "orders-api"
          image             = "python:3.13-alpine"
          image_pull_policy = "IfNotPresent"
          command           = ["python3", "/app/app.py"]

          env {
            name  = "PYTHONDONTWRITEBYTECODE"
            value = "1"
          }

          env {
            name  = "TLS_BUNDLE_PATH"
            value = local.orders_pki_active ? "/vault/secrets/orders-tls.pem" : ""
          }

          env {
            name  = "TLS_CERT_PATH"
            value = "/etc/orders-api/tls.crt"
          }

          env {
            name  = "TLS_KEY_PATH"
            value = "/etc/orders-api/tls.key"
          }

          env {
            name  = "ORDERS_CONFIG_PATH"
            value = "/vault/secrets/orders-config"
          }

          port {
            name           = "https"
            container_port = 8443
            protocol       = "TCP"
          }

          startup_probe {
            http_get {
              path   = "/healthz"
              port   = 8443
              scheme = "HTTPS"
            }

            period_seconds    = 2
            failure_threshold = 150
          }

          readiness_probe {
            http_get {
              path   = "/healthz"
              port   = 8443
              scheme = "HTTPS"
            }
          }

          liveness_probe {
            http_get {
              path   = "/healthz"
              port   = 8443
              scheme = "HTTPS"
            }
          }

          resources {
            requests = {
              cpu    = "25m"
              memory = "32Mi"
            }
            limits = {
              cpu    = "250m"
              memory = "128Mi"
            }
          }

          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true

            capabilities {
              drop = ["ALL"]
            }
          }

          volume_mount {
            name       = "app-code"
            mount_path = "/app"
            read_only  = true
          }

          volume_mount {
            name       = "shared-config"
            mount_path = "/vault/secrets"
            read_only  = true
          }

          dynamic "volume_mount" {
            for_each = local.orders_pki_active ? [] : [1]

            content {
              name       = "tls"
              mount_path = "/etc/orders-api"
              read_only  = true
            }
          }
        }

        container {
          name              = "vault-agent"
          image             = "docker.io/hashicorp/vault:2.0.4"
          image_pull_policy = "IfNotPresent"
          command           = ["vault"]
          args              = ["agent", "-config=/vault/config/agent.hcl"]

          env {
            name  = "HOME"
            value = "/tmp"
          }

          resources {
            requests = {
              cpu    = "25m"
              memory = "32Mi"
            }
            limits = {
              cpu    = "250m"
              memory = "128Mi"
            }
          }

          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true

            capabilities {
              drop = ["ALL"]
            }
          }

          volume_mount {
            name       = "agent-config"
            mount_path = "/vault/config"
            read_only  = true
          }

          volume_mount {
            name       = "vault-auth-token"
            mount_path = "/var/run/secrets/vault-auth"
            read_only  = true
          }

          volume_mount {
            name       = "shared-config"
            mount_path = "/vault/secrets"
          }

          volume_mount {
            name       = "tmp"
            mount_path = "/tmp"
          }
        }

        volume {
          name = "app-code"

          config_map {
            name = kubernetes_config_map_v1.orders_app[0].metadata[0].name
          }
        }

        dynamic "volume" {
          for_each = local.orders_pki_active ? [] : [1]

          content {
            name = "tls"

            secret {
              secret_name = "orders-api-tls"
            }
          }
        }

        volume {
          name = "agent-config"

          config_map {
            name = kubernetes_config_map_v1.orders_agent_config[0].metadata[0].name
          }
        }

        volume {
          name = "vault-auth-token"

          projected {
            sources {
              service_account_token {
                path               = "token"
                expiration_seconds = 600
              }
            }
          }
        }

        volume {
          name = "shared-config"

          empty_dir {
            medium = "Memory"
          }
        }

        volume {
          name = "tmp"

          empty_dir {}
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "orders" {
  count = var.enable_kubernetes_auth ? 1 : 0

  metadata {
    name      = "orders-api"
    namespace = kubernetes_namespace_v1.apps[0].metadata[0].name
  }

  spec {
    selector = {
      app = "orders-api"
    }

    port {
      name        = "https"
      port        = 443
      target_port = 8443
      protocol    = "TCP"
    }

    type = "ClusterIP"
  }
}

resource "kubernetes_service_account_v1" "payments" {
  count = var.enable_kubernetes_auth ? 1 : 0

  metadata {
    name      = "payments-api"
    namespace = kubernetes_namespace_v1.apps[0].metadata[0].name
  }

  lifecycle {
    ignore_changes = [metadata[0].annotations, image_pull_secret, secret]
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
  token_policies = concat(
    [vault_policy.orders_read[0].name],
    local.orders_pki_active ? [vault_policy.orders_pki_issue[0].name] : []
  )
  token_ttl     = 900
  token_max_ttl = 3600

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
