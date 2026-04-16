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
├── Prometheus + nvidia_gpu_exporter + boinc_exporter
└── Grafana (dashboards for GPU, BOINC, Ollama metrics)
```

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
| EBS storage 50GB gp3 | ~$4 |
| Data transfer | ~$5 |
| **Total** | **~$139** |

~$61 under $200 budget — comfortable margin for spot price spikes.

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

## Docker Compose Starting Point

*Ask Claude to generate the full file — this is a reminder of what to include:*

- `ollama` service (GPU passthrough)
- `open-webui` service
- `prometheus` service
- `grafana` service
- `boinc` service with PVC-equivalent volume for checkpoint data
- Shared bridge network

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

## Next Steps (pick up here)

1. Ask Claude to generate the **Docker Compose file** for the full stack
2. Ask Claude to generate the **VPC + security group Terraform/OpenTofu config**
3. Ask Claude to generate the **spot termination detection script**
4. Decide on a BOINC project (Folding@home, World Community Grid, etc.)

