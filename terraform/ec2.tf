# ── Security Group ────────────────────────────────────────────────────────────
# FedRAMP: SC-7 (Boundary Protection), AC-17 (Remote Access)
# Only your IP is allowed inbound on user-facing ports.
# Prometheus (9090), Ollama (11434), BOINC RPC (31416) are NOT opened —
# reach them via SSH tunnel: ssh -L 9090:localhost:9090 ubuntu@<ip>

resource "aws_security_group" "lab" {
  name        = "lab-sg"
  description = "Lab instance - SSH/Grafana/WebUI inbound from your IP only"
  vpc_id      = aws_vpc.lab.id

  ingress {
    description = "SSH (FedRAMP AC-17)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.your_ip_cidr]
  }

  ingress {
    description = "Grafana dashboard"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = [var.your_ip_cidr]
  }

  ingress {
    description = "Open WebUI (Ollama chat frontend)"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.your_ip_cidr]
  }

  egress {
    description = "Allow all outbound (Docker pulls, BOINC work, OS updates)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "lab-sg" }
}

# ── Spot Instance ─────────────────────────────────────────────────────────────

resource "aws_instance" "lab" {
  ami                    = data.aws_ami.dlami.id
  instance_type          = "g4dn.xlarge"
  key_name               = var.key_pair_name
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.lab.id]
  iam_instance_profile   = aws_iam_instance_profile.lab.name

  # Spot: ~60-70% cheaper than on-demand.
  # Set use_spot = false in terraform.tfvars to use on-demand while waiting
  # for spot quota approval (Service Quotas > "All G and VT Spot Instance Requests").
  dynamic "instance_market_options" {
    for_each = var.use_spot ? [1] : []
    content {
      market_type = "spot"
      spot_options {
        max_price                      = var.spot_max_price
        spot_instance_type             = "persistent"
        instance_interruption_behavior = "stop"
      }
    }
  }

  # IMDSv2 enforcement — FedRAMP IA-3, protects IAM role credentials from SSRF.
  # hop_limit = 1 blocks containers from reaching the metadata service.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv1 disabled
    http_put_response_hop_limit = 1
  }

  # Root volume holds only the OS + DLAMI driver. All Docker data (images,
  # containers, named volumes = models/BOINC/Grafana/Prometheus) lives on the
  # separate /data volume below — see userdata.sh, which relocates Docker's
  # data-root there. This keeps the root volume from filling up.
  root_block_device {
    volume_size           = 80
    volume_type           = "gp3"
    encrypted             = true
    kms_key_id            = aws_kms_key.ebs.arn # CMK — FedRAMP SC-28
    delete_on_termination = false                # Preserve data on spot reclaim
  }

  user_data = base64encode(templatefile("${path.module}/userdata.sh", {
    boinc_password         = var.boinc_rpc_password
    grafana_admin_password = var.grafana_admin_password
    repo_url               = var.repo_url
  }))

  tags = {
    Name          = "lab-boinc-grafana"
    auto-schedule = "true" # Picked up by lab-start-ec2 Lambda (morning_start.tf)
  }

  lifecycle {
    ignore_changes = [user_data, ami] # Prevent replacement on userdata or new DLAMI publish
  }
}

# ── Persistent data volume ────────────────────────────────────────────────────
# Holds Docker's data-root (/data/docker): all images, containers, and named
# volumes — which means Ollama models, BOINC checkpoints, Grafana, and Prometheus
# data. Separate from the instance so it survives rebuilds and supports the
# monthly snapshot/restore workflow.
#
# Monthly rebuild with model/data preservation:
#   1. aws ec2 create-snapshot --volume-id <id> --description "lab-data-YYYY-MM"
#   2. terraform destroy
#   3. set data_volume_snapshot_id = "<snap-id>" in terraform.tfvars
#   4. terraform apply   (volume restored from snapshot, models intact)
resource "aws_ebs_volume" "data" {
  availability_zone = aws_subnet.public.availability_zone
  size              = var.data_volume_size
  type              = "gp3"
  encrypted         = true
  kms_key_id        = aws_kms_key.ebs.arn # CMK — FedRAMP SC-28

  # When set, the volume is restored from a prior snapshot (preserves models/data).
  snapshot_id = var.data_volume_snapshot_id != "" ? var.data_volume_snapshot_id : null

  tags = { Name = "lab-data" }

  lifecycle {
    ignore_changes = [snapshot_id] # Don't recreate volume if snapshot var changes later
  }
}

resource "aws_volume_attachment" "data" {
  device_name = "/dev/sdf" # Presents inside the instance as a /dev/nvme*n1 device
  volume_id   = aws_ebs_volume.data.id
  instance_id = aws_instance.lab.id
}
