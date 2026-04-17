variable "aws_region" {
  description = "AWS region. g4dn.xlarge available in us-east-1, us-west-2, eu-west-1. GovCloud: us-gov-east-1, us-gov-west-1."
  type        = string
  default     = "us-east-1"
}

variable "key_pair_name" {
  description = "Name of an existing EC2 key pair. Create one: AWS Console → EC2 → Key Pairs → Create key pair (ED25519, .pem). Download and chmod 400 the file."
  type        = string
}

variable "your_ip_cidr" {
  description = "YOUR IP address in CIDR notation, e.g. 203.0.113.5/32. Find it at: https://checkip.amazonaws.com — append /32. FedRAMP SC-7 requires restricting inbound to known sources. No default — must be set explicitly."
  type        = string

  validation {
    condition     = var.your_ip_cidr != "0.0.0.0/0"
    error_message = "Setting your_ip_cidr to 0.0.0.0/0 opens SSH/Grafana/WebUI to the entire internet. Set it to your IP (e.g. 203.0.113.5/32). Find your IP at https://checkip.amazonaws.com"
  }
}

variable "spot_max_price" {
  description = "Max spot bid per hour (USD). On-demand g4dn.xlarge = ~$0.526/hr. Average spot = ~$0.18/hr. Set above recent spot to stay up, below on-demand to cap cost."
  type        = string
  default     = "0.35"
}

variable "boinc_rpc_password" {
  description = "Password for BOINC GUI RPC (used by boinccmd). Change from default."
  type        = string
  sensitive   = true

  validation {
    condition     = var.boinc_rpc_password != "changeme"
    error_message = "Set a real boinc_rpc_password — do not leave it as 'changeme'."
  }
}

variable "grafana_admin_password" {
  description = "Grafana admin password. Login: http://<ip>:3000 with user 'admin'."
  type        = string
  sensitive   = true

  validation {
    condition     = var.grafana_admin_password != "changeme"
    error_message = "Set a real grafana_admin_password — do not leave it as 'changeme'."
  }
}

variable "use_spot" {
  description = "true = spot instance (~$0.18/hr), false = on-demand (~$0.53/hr). Set to false while waiting for spot quota approval."
  type        = bool
  default     = true
}

variable "repo_url" {
  description = "Git URL of this repo — cloned to the instance at first boot."
  type        = string
  default     = "https://github.com/acts1417/learnawsgrafana.git"
}
