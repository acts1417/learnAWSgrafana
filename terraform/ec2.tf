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
  # persistent + stop = instance stops (not terminates) on reclaim; EBS survives;
  # spot request stays open so the instance restarts when capacity returns.
  instance_market_options {
    market_type = "spot"
    spot_options {
      max_price                      = var.spot_max_price
      spot_instance_type             = "persistent"
      instance_interruption_behavior = "stop"
    }
  }

  # IMDSv2 enforcement — FedRAMP IA-3, protects IAM role credentials from SSRF.
  # hop_limit = 1 blocks containers from reaching the metadata service.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv1 disabled
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_size           = 50
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

  tags = { Name = "lab-boinc-grafana" }

  lifecycle {
    ignore_changes = [user_data] # Prevent replacement on userdata-only changes
  }
}
