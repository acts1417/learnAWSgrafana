# Security Review

Performed: 2026-06-06  
Scope: All Terraform, Docker Compose, shell scripts, and Grafana provisioning files  
Standard: FedRAMP alignment + least-privilege

---

## Status Legend

| Symbol | Meaning |
|--------|---------|
| ✅ | Fixed and pushed |
| 🔲 | Open — not yet addressed |
| ℹ️ | Accepted risk / AWS limitation |

---

## HIGH Severity

| ID | Status | File | Issue | Fix Applied |
|----|--------|------|-------|-------------|
| H1 | ✅ | `docker-compose.yml:58` | `WEBUI_SECRET_KEY` hardcoded in repo | Moved to `.env`; generated with `openssl rand -hex 32` in userdata.sh |
| H2 | ✅ | `docker-compose.yml:12,135` | `:-changeme` fallbacks silently use weak password if `.env` absent | Removed defaults — Docker Compose now hard-fails if `.env` missing |
| H3 | ✅ | `spot-termination-monitor.service` | Systemd unit missing `EnvironmentFile=` — BOINC password fell back to `changeme` at shutdown | Fixed in script; service no longer installed — switched permanently to on-demand (org weekend shutdown policy made spot unreliable) |
| H4 | ✅ | `terraform/userdata.sh:6` | `/var/log/userdata.log` created world-readable; `set -x` would expose secrets | Added `chmod 600 /var/log/userdata.log` immediately after `exec >>` |

---

## MEDIUM Severity

| ID | Status | File | Issue |
|----|--------|------|-------|
| M1 | 🔲 | `docker-compose.yml:66` | Open WebUI exposed on plaintext HTTP (`0.0.0.0:8080`). FedRAMP SC-8 requires encryption in transit. Mitigation: add nginx/Caddy TLS termination in front of both Open WebUI and Grafana. |
| M2 | 🔲 | `docker-compose.yml:137,146` | Grafana plaintext HTTP + `GF_SERVER_ROOT_URL=http://localhost:3000` while exposed on public IP. Fix: update ROOT_URL to use public IP or DNS name; add TLS. |
| M3 | 🔲 | `docker-compose.yml:121` | Prometheus `--web.enable-lifecycle` enables unauthenticated `/-/reload` and `/-/quit` endpoints reachable by any container on the Docker bridge. Remove flag or add `--web.config.file` with basic auth. |
| M4 | 🔲 | `terraform/variables.tf:17` | `your_ip_cidr` validation only rejects `0.0.0.0/0`; broad subnets like `/8` or `/16` pass silently. Tighten to reject prefixes shorter than `/24` (or require `/32` for FedRAMP SC-7 strict). |
| M5 | 🔲 | `terraform/main.tf` | No remote Terraform state backend. Local `terraform.tfstate` stores sensitive values (passwords) in plaintext JSON. For FedRAMP: use S3 backend with SSE and DynamoDB locking. Deferred until new group workspace migration. |
| M6 | 🔲 | `terraform/main.tf:69-73` | VPC flow logs CloudWatch log group not KMS-encrypted. EBS is CMK-encrypted but audit logs are not. Fix: add `kms_key_id` to `aws_cloudwatch_log_group` and grant `logs.amazonaws.com` the required KMS actions. |
| M7 | 🔲 | `terraform/userdata.sh:34` | `curl \| sh` for Docker install has no hash verification — supply chain risk at boot. Fix: use Docker's APT repository with pinned version and apt signature verification. |
| M8 | 🔲 | `terraform/userdata.sh:64` | Branch name `claude/setup-aws-boinc-grafana-digQH` hardcoded in bootstrap script. When branch is merged/deleted, new instances will fail to boot. Fix: parameterize as a Terraform variable defaulting to `main` after merge. |

---

## LOW Severity

| ID | Status | File | Issue |
|----|--------|------|-------|
| L1 | 🔲 | `docker-compose.yml` | Multiple unpinned `latest`/`main` Docker image tags (ollama, open-webui, node-exporter, prometheus, grafana). Supply chain integrity risk — pin to digest (`@sha256:...`) or semver tags for reproducible deployments. `open-webui:main` is especially aggressive. |
| L2 | 🔲 | `terraform/kms.tf:12` | KMS deletion window at minimum 7 days. If `terraform destroy` is run accidentally, only 7 days to cancel before encrypted EBS volume is permanently unreadable. Consider 14–30 days. |
| L3 | ℹ️ | `terraform/iam.tf:41,48` | SSM actions (`ssm:UpdateInstanceInformation`, `ssmmessages:*`) require `Resource = "*"` — AWS does not support resource-level restrictions for these APIs. Accepted AWS limitation, not fixable. |
| L4 | ℹ️ | `docker-compose.yml:75-78` | node-exporter mounts entire host filesystem (`/:/rootfs:ro`). Standard for node-exporter disk metrics. Document as accepted risk in system security plan. |
| L5 | 🔲 | `terraform/ec2.tf:85` | `delete_on_termination = false` leaves orphaned encrypted EBS volumes after instance replacements. Add lifecycle tag for cost tracking and manual cleanup. |
| L6 | 🔲 | `docker/grafana/provisioning/datasources/prometheus.yml:9` | `editable: true` allows any authenticated Grafana user to modify the Prometheus datasource URL. For FedRAMP CM-7: set `editable: false`. |

---

## What Is Done Well

- IMDSv2 enforced (`http_tokens = "required"`, hop limit = 1 blocks container SSRF)
- EBS encrypted with CMK + annual key rotation; IAM policy scoped to specific key ARN
- VPC flow logs with 90-day CloudWatch retention
- Sensitive Terraform variables declared `sensitive = true`
- BOINC, Ollama, Prometheus bound to `127.0.0.1` on host (not exposed to internet)
- No AWS managed policies used — all inline with least-privilege actions
- Flow logs IAM policy scoped to specific log group ARN
- `.gitignore` excludes `terraform.tfvars`, `terraform.tfstate`, `docker/.env`

---

## CI / Pre-PR Checklist

### Automated (GitHub Actions — runs on every push and PR)
- ShellCheck on `scripts/*.sh`
- ShellCheck on `terraform/userdata.sh` (SC2154 excluded for Terraform template vars)
- JSON validation on all `docker/grafana/provisioning/dashboards/*.json`

### Manual (run before opening a PR — requires AWS credentials)
```powershell
# Terraform
terraform fmt -check -recursive
terraform validate

# Checkov (pip install checkov)
checkov -d . --framework terraform
checkov -d ../docker --framework dockerfile
```

---

## Recommended Next Steps (Priority Order)

1. **M8** — Parameterize branch name before this branch is merged to `main`
2. **M4** — Tighten IP CIDR validation (quick Terraform change)
3. **L6** — Set Grafana datasource `editable: false` (one-line change)
4. **M6** — Encrypt CloudWatch log group with KMS (small Terraform change)
5. **M3** — Remove or auth-protect Prometheus `--web.enable-lifecycle`
6. **M5** — Remote Terraform state backend (after new workspace migration)
7. **M1/M2** — TLS termination for Grafana and Open WebUI (larger effort)
8. **M7** — Replace `curl \| sh` Docker install with pinned APT packages
9. **L1** — Pin Docker image tags to digests
10. **L2** — Increase KMS deletion window to 14–30 days
