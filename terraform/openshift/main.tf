terraform {
  required_version = ">= 1.5.0"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.38"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.0"
    }
  }
}

variable "kubeconfig_path" {
  description = "Path to the kubeconfig created by oc login."
  type        = string
  default     = "~/.kube/config"
}

variable "kube_context" {
  description = "Optional kubeconfig context. Leave empty to use the current context."
  type        = string
  default     = ""
}

variable "vault_profile" {
  description = "Vault Helm values profile to deploy."
  type        = string

  validation {
    condition     = contains(["dev", "raft-tls"], var.vault_profile)
    error_message = "vault_profile must be either dev or raft-tls."
  }
}

variable "enable_kubernetes_auth" {
  description = "Whether to manage Stage 3 Kubernetes authentication resources in Vault."
  type        = bool
}

provider "helm" {
  kubernetes {
    config_path    = var.kubeconfig_path
    config_context = var.kube_context != "" ? var.kube_context : null
  }
}

provider "kubernetes" {
  config_path    = var.kubeconfig_path
  config_context = var.kube_context != "" ? var.kube_context : null
}

provider "vault" {}

resource "helm_release" "vault" {
  name             = "vault"
  repository       = "https://helm.releases.hashicorp.com"
  chart            = "vault"
  version          = "0.34.1"
  namespace        = "vault-lab"
  create_namespace = true
  atomic           = true
  cleanup_on_fail  = true
  wait             = true
  timeout          = 600

  values = [
    file("${path.module}/values-${var.vault_profile}.yaml")
  ]
}
