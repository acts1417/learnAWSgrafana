output "instance_id" {
  description = "EC2 instance ID — use this with AWS CLI: aws ec2 describe-instances --instance-ids <id>"
  value       = aws_instance.lab.id
}

output "public_ip" {
  description = "Public IP address (changes each time the instance starts — consider an Elastic IP later)"
  value       = aws_instance.lab.public_ip
}

output "ami_used" {
  description = "Deep Learning AMI that was selected"
  value       = data.aws_ami.dlami.name
}

output "ssh_command" {
  description = "SSH into the instance"
  value       = "ssh -i ~/.ssh/${var.key_pair_name}.pem ubuntu@${aws_instance.lab.public_ip}"
}

output "grafana_url" {
  description = "Grafana dashboard — login admin / <grafana_admin_password>"
  value       = "http://${aws_instance.lab.public_ip}:3000"
}

output "open_webui_url" {
  description = "Open WebUI (Ollama chat frontend)"
  value       = "http://${aws_instance.lab.public_ip}:8080"
}

output "prometheus_tunnel" {
  description = "Prometheus is localhost-only. SSH tunnel command to access it:"
  value       = "ssh -L 9090:localhost:9090 -i ~/.ssh/${var.key_pair_name}.pem ubuntu@${aws_instance.lab.public_ip}"
}

output "userdata_log" {
  description = "Check instance bootstrap progress on the instance"
  value       = "sudo tail -f /var/log/userdata.log"
}
