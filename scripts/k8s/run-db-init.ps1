param(
    [string]$Region = "ap-northeast-2",
    [string]$DbInstanceIdentifier = "erumpay-mysql",
    [string]$Namespace = "platform-operations",
    [string]$SecretName = "erumpay-rds-secret",
    [string]$JobName = "erumpay-db-init",
    [int]$TimeoutSeconds = 600
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $scriptDir "..\..")
$jobManifestPath = Join-Path $repoRoot "k8s\jobs\db-init-job.yaml"
$tempManifestPath = Join-Path $env:TEMP "$JobName.yaml"

Write-Host "==> Checking AWS identity"
aws sts get-caller-identity | Out-Null

Write-Host "==> Resolving RDS endpoint: $DbInstanceIdentifier ($Region)"
$dbHost = aws rds describe-db-instances `
    --region $Region `
    --db-instance-identifier $DbInstanceIdentifier `
    --query "DBInstances[0].Endpoint.Address" `
    --output text

if ([string]::IsNullOrWhiteSpace($dbHost) -or $dbHost -eq "None") {
    throw "RDS endpoint was not found for DB instance: $DbInstanceIdentifier"
}

Write-Host "RDS endpoint: $dbHost"

Write-Host "==> Checking Kubernetes secret: $SecretName ($Namespace)"
kubectl get secret $SecretName -n $Namespace | Out-Null

Write-Host "==> Preparing DB init job manifest"
$content = Get-Content -Path $jobManifestPath -Raw
$pattern = '(?m)(\s*-\s*name:\s*DB_HOST\s*\r?\n\s*value:\s*).+'
$content = [regex]::Replace($content, $pattern, {
    param($match)
    return $match.Groups[1].Value + $dbHost
})
Set-Content -Path $tempManifestPath -Value $content -Encoding UTF8

Write-Host "==> Recreating DB init job: $JobName"
kubectl delete job $JobName -n $Namespace --ignore-not-found
kubectl apply -f $tempManifestPath

Write-Host "==> Waiting for DB init job to complete"
try {
    kubectl wait --for=condition=complete "job/$JobName" -n $Namespace --timeout="${TimeoutSeconds}s"
} catch {
    Write-Host "==> DB init job did not complete. Current pods:"
    kubectl get pods -n $Namespace -l job-name=$JobName
    Write-Host "==> DB init job logs:"
    kubectl logs -n $Namespace "job/$JobName" --tail=-1
    throw
}

Write-Host "==> DB init job completed. Logs:"
kubectl logs -n $Namespace "job/$JobName" --tail=-1
