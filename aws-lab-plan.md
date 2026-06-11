# AWS Personal Lab Plan
*Exported from Claude conversation — April 13, 2026*

## Goals
- Learn AWS, OCP4 (later), virtual networking, LLM performance, Grafana
- Contribute to science via BOINC
- Run a personal LLM (sparse personal use)
- Stay under **$200/month** AWS credit budget
- Cloud-only (no home hardware)
- Background: sysadmin, novice with cloud-native stack
- Primary goal: sharpen skills for current job

---

## Architecture

```
g4dn.xlarge (spot instance) — running 24/7
├── BOINC client (24/7, uses GPU/CPU when Ollama is idle)
├── Ollama (started on demand for LLM sessions)
├── Open WebUI (browser-based chat frontend)
├── Prometheus + nvidia_gpu_exporter + node_exporter
└── Grafana (dashboards for GPU, BOINC, Ollama metrics)
```

### Storage Layout

```
root EBS (80GB gp3)        →  /          OS + NVIDIA driver only
data EBS (150GB gp3)       →  /data      Docker data-root (images, containers,
                                          named volumes = models/BOINC/Grafana/Prom)
instance-store NVMe        →  unused     ephemeral — DO NOT use for Docker
```

**This is now fully automated.** `terraform/userdata.sh` on first boot:
1. Detects the data EBS volume by its Amazon EBS model string (skips the root
   disk and the ephemeral instance-store NVMe — device names are not stable)
2. Formats it ext4 only if blank (preserves data on a snapshot restore)
3. Mounts at `/data`, persists in `/etc/fstab` by UUID
4. Sets Docker `data-root` to `/data/docker` **before** any image pull

Because the stack uses Docker **named volumes**, putting the data-root on `/data`
automatically persists Ollama models, BOINC checkpoints, Grafana, and Prometheus
on the data volume — no bind-mount juggling.

**Lesson learned (the hard way):** LLM models are 4–8GB each and the full image
set is ~20GB. With everything on the 80GB root volume it fills within days. The
data-root relocation above is the fix; never put Docker on the instance-store
NVMe (it's wiped on stop).

### Access Pattern
```
Your laptop
└── SSH / Open WebUI in browser
        ↓
    EC2 g4dn.xlarge (spot)
```

---

## Cost Estimate

| Item | $/month |
|---|---|
| g4dn.xlarge spot 24/7 (~$0.18/hr) | ~$130 |
| EBS root 30GB gp3 | ~$2.40 |
| EBS data 150GB gp3 | ~$12 |
| Data transfer | ~$5 |
| **Total** | **~$149** |

~$51 under $200 budget. The larger data volume eliminates the disk-full issues
that occur when pulling LLM models onto the root volume.

**Monthly rebuild:** AWS credits reset on the 1st. Terminate the instance and
re-provision. The data EBS volume can be snapshotted before termination to
preserve downloaded models and BOINC checkpoints, saving re-download time.

---

## Instance Details

**g4dn.xlarge**
- 1x NVIDIA T4 GPU, 16GB VRAM
- 4 vCPU, 16GB RAM
- Runs 7B models comfortably in Ollama, 13B squeezed
- Good starting models: Llama 3.2 8B, Mistral 7B

---

## Key Design Decisions

- **Spot instance** — ~60-70% cheaper than on-demand; acceptable for a personal lab
- **BOINC + Ollama GPU time-sharing** — BOINC yields GPU when Ollama needs it, reclaims when idle. Configurable in BOINC resource settings.
- **No OCP4 yet** — Plain EC2 + Docker is leaner for getting started. Add OCP4 or ROSA later once comfortable.
- **On-demand LLM** — Start/stop Ollama as needed rather than running 24/7

---

## Spot Instance Risk Mitigation

AWS reclaims spot instances with 2-minute warning. Plan:
1. Poll instance metadata endpoint for termination notice:
   `http://169.254.169.254/latest/meta-data/spot/termination-time`
2. On notice: trigger BOINC checkpoint + graceful suspend
3. Store BOINC data on EBS (persists across instance terminations)
4. Use a startup script to resume BOINC automatically on re-provision

*This is a good early automation project — teaches AWS instance metadata.*

---

## Start/Stop Options for Ollama Sessions

From simple to advanced (good learning progression):

| Method | Teaches |
|---|---|
| AWS Console | Basic EC2 management |
| AWS CLI (`aws ec2 start-instances`) | CLI fluency |
| Lambda + API Gateway | Serverless, good portfolio project |
| Systems Manager (SSM) | Security best practices, no open SSH ports |

---

## Month-by-Month Learning Plan

### Month 1 — Foundation
- Design and provision VPC (public/private subnets, security groups, IAM role)
- Launch g4dn.xlarge spot instance
- Install Docker + Docker Compose
- Deploy Ollama + Open WebUI
- Pull first model (Llama 3.2 8B recommended)
- **Learn:** VPC networking, IAM, EC2, spot lifecycle

### Month 2 — Observability
- Add BOINC client container
- Add Prometheus + nvidia_gpu_exporter + node_exporter
- Build Grafana dashboards: GPU utilization, VRAM, BOINC job throughput, Ollama tokens/sec
- **Learn:** PromQL, container networking, GPU metrics

### Month 3 — Automation
- Script spot termination detection + BOINC graceful shutdown
- Build Lambda + API Gateway trigger for on-demand instance start/stop
- **Learn:** Lambda, API Gateway, instance metadata, bash automation

### Month 4+ — Stretch Goals
- Introduce OCP4 SNO (Single Node OpenShift) or ROSA (managed)
- GitOps with ArgoCD
- Network policies, namespace isolation
- Multi-model Ollama routing

---

## Docker Compose

See `docker-compose.yml` and `prometheus/prometheus.yml` in this repo.

Services: `ollama`, `open-webui`, `boinc`, `node-exporter`,
`nvidia-gpu-exporter`, `prometheus`, `grafana`.

All persistent volumes are bind-mounted under `/data` (the dedicated EBS volume).

**First-time setup on a new instance:**
```bash
sudo ./scripts/bootstrap.sh /dev/nvme2n1   # pass your data EBS device
```

**Subsequent starts after bootstrap:**
```bash
cd /opt/lab/docker && docker compose up -d
```

---

## Key Resources

| Topic | URL |
|---|---|
| Ollama | https://github.com/ollama/ollama |
| Ollama on Kubernetes | https://github.com/ollama/ollama/blob/main/docs/kubernetes.md |
| Open WebUI | https://github.com/open-webui/open-webui |
| BOINC Docker image | https://hub.docker.com/r/boinc/client |
| OCP4 SNO install | https://docs.openshift.com/container-platform/latest/installing/installing_sno/install-sno-installing-sno.html |
| Red Hat Assisted Installer | https://console.redhat.com/openshift/assisted-installer/clusters |
| OCP monitoring stack | https://docs.openshift.com/container-platform/latest/monitoring/monitoring-overview.html |
| Tor relay setup | https://community.torproject.org/relay/setup/ |

---

## Skills This Lab Covers

| Skill | How |
|---|---|
| VPC / security groups | Instance networking setup |
| Spot instance lifecycle | BOINC + termination handling |
| GPU management | CUDA, nvidia-smi, resource sharing |
| Container networking | Docker Compose, service discovery |
| Observability | Grafana + Prometheus dashboards |
| Automation | Lambda or CLI start/stop |
| Linux sysadmin | All of the above, in the cloud |

---

## Ideas Ruled Out (and Why)

| Idea | Reason |
|---|---|
| Torrents | Violates AWS ToS |
| Tor exit node | Legal/ToS risk on AWS |
| Always-on GPU instance | Too expensive 24/7 on-demand |
| OCP4 from day one | Adds complexity; better after EC2 basics |
| BOINC on separate instance | Wasteful — time-shares fine on same GPU instance |

---

## Lessons Learned (Month 1)

| Problem | Root Cause | Fix |
|---|---|---|
| No CPU/GPU in Grafana | WCG scheduled maintenance; no work units | Wait; BOINC auto-recovers |
| No space left on device | Docker images filled 78GB root volume | Dedicated 150GB data EBS for Docker |
| NVMe data lost on stop | Instance store is ephemeral | Never use NVMe for Docker data |
| New IP on every start | No Elastic IP assigned | Allocate and associate an Elastic IP |
| `RequestExpired` AWS CLI | Temp credentials expired (STS/SSO) | `aws sso login` to refresh |
| `docker compose` needs sudo | ubuntu not in docker group | userdata adds ubuntu to docker group |
| Grafana datasource not found | provisioning not wired | datasource + dashboards auto-provisioned in `docker/grafana/provisioning` |
| Grafana dashboard "No data" | malformed JSON / wrong metrics | dashboards validated; use `nvidia_smi_*` (community exporter) |
| Two competing compose files | root + `docker/` copies | consolidated to a single `docker/` layout |
| BOINC no GPU work | project sends CPU-only or maintenance | GPU projects: Einstein@home, Milkyway (separation app) |

---

## Monthly Rebuild Runbook

AWS terminates all resources on the 1st (`Monthly-Expiration-Trigger`). To rebuild
**and keep your Ollama models + BOINC data**, snapshot the data volume first:

```bash
# 1. Before month end — snapshot the data volume
VOL=$(aws ec2 describe-volumes \
  --filters "Name=tag:Name,Values=lab-data" \
  --query "Volumes[0].VolumeId" --output text)
aws ec2 create-snapshot --volume-id "$VOL" --description "lab-data-$(date +%Y-%m)"

# 2. Tear down
cd terraform && terraform destroy

# 3. New month — restore from snapshot
#    set in terraform.tfvars:  data_volume_snapshot_id = "snap-xxxxxxxx"
terraform apply           # data volume restored, models intact

# 4. (Fresh volume only) pull models again
docker exec ollama ollama pull qwen3:14b
```

Leave `data_volume_snapshot_id = ""` for a clean blank volume.

The instance is tagged `auto-schedule=true` so the morning-start Lambda finds it
automatically — no manual tagging after rebuild.

---

## Next Steps

1. Add **Elastic IP** so the instance IP is stable across restarts
2. Per-process GPU panels are live (`gpu-process-attribution.json`) — extend with
   Ollama token-rate panels once the Ollama `/metrics` endpoint is confirmed
3. Wire the **spot termination monitor** if spot is ever re-enabled
4. Month 4: OCP4 SNO / ROSA stretch goals

