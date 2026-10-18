terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5"
    }
  }
}

provider "cloudflare" {
  # read token from $CLOUDFLARE_API_TOKEN
}

variable "CLOUDFLARE_ACCOUNT_ID" {
  # read account id from $TF_VAR_CLOUDFLARE_ACCOUNT_ID
  type = string
}

variable "APP_HOST" {
  type = string
}

variable "DOMAIN" {
  type = string
}

variable "SLACK_WEBHOOK_URL" {
  type      = string
  sensitive = true
}

variable "STATUS_PROBE_INGEST_URL" {
  type    = string
  default = ""
}

variable "STATUS_PROBE_INGEST_TOKEN" {
  type      = string
  sensitive = true
  default   = ""
}

variable "enable_do_migration" {
  type    = bool
  default = false
}

variable "resource_suffix" {
  type = string
}

locals {
  # infra/main publishes https://example.com/ until the Function URL exists.
  status_probe_ingest_configured = (
    var.STATUS_PROBE_INGEST_TOKEN != "" &&
    var.STATUS_PROBE_INGEST_URL != "" &&
    var.STATUS_PROBE_INGEST_URL != "https://example.com" &&
    var.STATUS_PROBE_INGEST_URL != "https://example.com/"
  )
}

resource "cloudflare_d1_database" "uptimeflare_d1" {
  account_id            = var.CLOUDFLARE_ACCOUNT_ID
  name                  = "uptimeflare_d1${var.resource_suffix}"
  read_replication = {
    mode = "auto"
  }
}

resource "cloudflare_workers_script" "uptimeflare_worker" {
  account_id          = var.CLOUDFLARE_ACCOUNT_ID
  script_name         = "uptimeflare_worker${var.resource_suffix}"
  main_module         = "worker/dist/index.js"
  content_file        = "worker/dist/index.js"
  content_sha256      = filesha256("worker/dist/index.js")
  compatibility_date  = "2025-04-02"
  compatibility_flags = ["nodejs_compat"]

  observability = {
    enabled = true
    logs = {
      enabled         = true
      invocation_logs = true
    }
  }

  migrations = var.enable_do_migration ? {
    new_tag            = "v1"
    new_sqlite_classes = ["RemoteChecker"]
  } : null

  bindings = concat([
    {
      name       = "REMOTE_CHECKER_DO"
      class_name = "RemoteChecker"
      type       = "durable_object_namespace"
      id         = null
      text       = null
    },
    {
      name       = "UPTIMEFLARE_D1"
      type       = "d1"
      id         = cloudflare_d1_database.uptimeflare_d1.id
      class_name = null
      text       = null
    },
    {
      name       = "APP_HOST"
      type       = "plain_text"
      text       = var.APP_HOST
      class_name = null
      id         = null
    },
    {
      name       = "DOMAIN"
      type       = "plain_text"
      text       = var.DOMAIN
      class_name = null
      id         = null
    },
    {
      name       = "SLACK_WEBHOOK_URL"
      type       = "secret_text"
      text       = var.SLACK_WEBHOOK_URL
      class_name = null
      id         = null
    },
    ], local.status_probe_ingest_configured ? [
    {
      name       = "STATUS_PROBE_INGEST_URL"
      type       = "plain_text"
      text       = var.STATUS_PROBE_INGEST_URL
      class_name = null
      id         = null
    },
    {
      name       = "STATUS_PROBE_INGEST_TOKEN"
      type       = "secret_text"
      text       = var.STATUS_PROBE_INGEST_TOKEN
      class_name = null
      id         = null
    },
  ] : [])
}

resource "cloudflare_workers_cron_trigger" "uptimeflare_worker_cron" {
  account_id  = var.CLOUDFLARE_ACCOUNT_ID
  script_name = cloudflare_workers_script.uptimeflare_worker.script_name
  schedules = [{
    cron = "* * * * *" # every 1 minute, you can reduce the write counts by increase the worker settings of `kvWriteCooldownMinutes`
  }]
}

resource "cloudflare_pages_project" "uptimeflare" {
  account_id        = var.CLOUDFLARE_ACCOUNT_ID
  # Pages allows lowercase + dashes only (no underscores)
  name              = "uptimeflare${replace(var.resource_suffix, "_", "-")}"
  production_branch = "main"

  deployment_configs = {
    # SMH Cloudflare provider will throw an error without preview config
    preview = {
      fail_open = false
    }
    production = {
      d1_databases = {
        UPTIMEFLARE_D1 = {
          id = cloudflare_d1_database.uptimeflare_d1.id
        }
      }
      env_vars = {
        APP_HOST = {
          type  = "plain_text"
          value = var.APP_HOST
        }
        DOMAIN = {
          type  = "plain_text"
          value = var.DOMAIN
        }
        SLACK_WEBHOOK_URL = {
          type  = "secret_text"
          value = var.SLACK_WEBHOOK_URL
        }
      }
      compatibility_date  = "2025-04-02"
      compatibility_flags = ["nodejs_compat"]
      fail_open           = false
    }
  }

  # SMH it will error without this build_config
  build_config = {
    root_dir = "/"
  }
}
