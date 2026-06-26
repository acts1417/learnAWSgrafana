<#
.SYNOPSIS
Starts the lab EC2 instance and waits until it's actually usable.

.DESCRIPTION
Starts the instance if it's stopped (no-op if already running), waits for
state=running, waits for SSH to accept connections, then waits for the
open-webui container to report healthy. Prints connection info on success.
#>
param(
    [string]$InstanceId = "i-0d4c07ce4d04b27e1",
    [string]$ProfileName = "sparx-admin",
    [string]$KeyPath = "$HOME\.ssh\lab-key.pem",
    [string]$SshUser = "ubuntu"
)

$ErrorActionPreference = "Stop"

function Write-Step($msg) {
    Write-Host "==> $msg" -ForegroundColor Cyan
}

Write-Step "Verifying AWS credentials (profile: $ProfileName)"
$identity = aws sts get-caller-identity --profile $ProfileName --output json | ConvertFrom-Json
Write-Host "  Account $($identity.Account) as $($identity.Arn)"

Write-Step "Checking instance state"
$state = aws ec2 describe-instances --instance-ids $InstanceId --profile $ProfileName `
    --query "Reservations[0].Instances[0].State.Name" --output text

if ($state -eq "running") {
    Write-Host "  Already running."
}
else {
    Write-Step "Starting instance (current state: $state)"
    aws ec2 start-instances --instance-ids $InstanceId --profile $ProfileName --output table
    Write-Step "Waiting for state=running"
    aws ec2 wait instance-running --instance-ids $InstanceId --profile $ProfileName
}

$publicIp = aws ec2 describe-instances --instance-ids $InstanceId --profile $ProfileName `
    --query "Reservations[0].Instances[0].PublicIpAddress" --output text
Write-Host "  Public IP: $publicIp"

Write-Step "Waiting for SSH on ${publicIp}:22"
$deadline = (Get-Date).AddSeconds(120)
$sshReady = $false
while ((Get-Date) -lt $deadline) {
    $test = Test-NetConnection -ComputerName $publicIp -Port 22 -WarningAction SilentlyContinue
    if ($test.TcpTestSucceeded) { $sshReady = $true; break }
    Start-Sleep -Seconds 5
}
if (-not $sshReady) {
    throw "SSH did not become reachable on ${publicIp}:22 within 120s"
}
Write-Host "  SSH is up."

Write-Step "Waiting for open-webui container health"
$remoteCmd = 'for i in $(seq 1 30); do s=$(docker inspect -f {{.State.Health.Status}} open-webui 2>/dev/null); if [ "$s" = healthy ]; then echo READY; break; fi; sleep 3; done'
$result = & ssh -i $KeyPath -o StrictHostKeyChecking=accept-new "$SshUser@$publicIp" $remoteCmd
if ($result -notcontains "READY") {
    Write-Host "  WARNING: open-webui did not report healthy within 90s - check it manually." -ForegroundColor Yellow
}
else {
    Write-Host "  open-webui is healthy."
}

Write-Host ""
Write-Host "Lab is up:" -ForegroundColor Green
Write-Host "  SSH:        ssh -i $KeyPath $SshUser@$publicIp"
Write-Host "  Grafana:    http://${publicIp}:3000"
Write-Host "  Open WebUI: http://${publicIp}:8080"
