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

resource "kubernetes_config_map_v1" "orders_nginx" {
  count = var.enable_kubernetes_auth ? 1 : 0

  metadata {
    name      = "orders-api-nginx"
    namespace = kubernetes_namespace_v1.apps[0].metadata[0].name
  }

  data = {
    "default.conf" = <<-EOT
      server {
        listen 8443 ssl;
        server_name orders-api.vault-apps.svc;

        ssl_certificate /etc/nginx/tls/tls.crt;
        ssl_certificate_key /etc/nginx/tls/tls.key;

        location / {
          default_type text/plain;
          return 200 "orders-api HTTPS demo is running\n";
        }
      }
    EOT
  }
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
          name              = "nginx"
          image             = "nginxinc/nginx-unprivileged:1.28-alpine"
          image_pull_policy = "IfNotPresent"

          port {
            name           = "https"
            container_port = 8443
            protocol       = "TCP"
          }

          readiness_probe {
            http_get {
              path   = "/"
              port   = 8443
              scheme = "HTTPS"
            }
          }

          liveness_probe {
            http_get {
              path   = "/"
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
            name       = "nginx-config"
            mount_path = "/etc/nginx/conf.d"
            read_only  = true
          }

          volume_mount {
            name       = "tls"
            mount_path = "/etc/nginx/tls"
            read_only  = true
          }

          volume_mount {
            name       = "tmp"
            mount_path = "/tmp"
          }
        }

        volume {
          name = "nginx-config"

          config_map {
            name = kubernetes_config_map_v1.orders_nginx[0].metadata[0].name
          }
        }

        volume {
          name = "tls"

          secret {
            secret_name = "orders-api-tls"
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
