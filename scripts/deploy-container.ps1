<#
.SYNOPSIS
    Builds the Chargeback API container image and deploys it to the provisioned infrastructure.
.DESCRIPTION
    Post-deploy script to run after Terraform (or Bicep) has provisioned the infrastructure.
    Builds the Docker image (multi-stage: Node.js UI + .NET API), pushes to ACR,
    and updates the Container App to use the new image.

    This two-stage approach is required because:
    1. Terraform deploys infrastructure with a placeholder image (mcr.microsoft.com/dotnet/aspnet:10.0)
    2. This script builds the real image, pushes to the deployed ACR, and updates the Container App
    
    This is the standard pattern for enterprise environments where public container registries are disabled.
.PARAMETER ResourceGroupName
    Resource group containing the deployed infrastructure.
.PARAMETER WorkloadName
    Workload name prefix used during infrastructure deployment (default: chrgbk).
.PARAMETER Tag
    Image tag (default: timestamped run-YYYYMMDDHHMMSS).
.PARAMETER SkipBuild
    Skip the Docker build step (push and update only — assumes image is already built locally).
.EXAMPLE
    .\deploy-container.ps1 -ResourceGroupName rg-chrgbk-eastus2
.EXAMPLE
    .\deploy-container.ps1 -ResourceGroupName rg-chrgbk-eastus2 -WorkloadName chrgbk -Tag v1.0.0
#>
param(
    [Parameter(Mandatory = $true)][string]$ResourceGroupName,
    [string]$WorkloadName = "chrgbk",
    [string]$Tag = "",
    [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptDir

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Chargeback API — Container Build & Deploy              ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# ── Step 1: Discover infrastructure ──────────────────────────────────

Write-Host "  Step 1: Discovering infrastructure..." -ForegroundColor Yellow

$acrName = az acr list --resource-group $ResourceGroupName --query "[0].name" -o tsv
if ([string]::IsNullOrWhiteSpace($acrName)) { throw "No ACR found in resource group $ResourceGroupName" }
Write-Host "    ACR: $acrName" -ForegroundColor Green

$containerAppName = az containerapp list --resource-group $ResourceGroupName --query "[0].name" -o tsv
if ([string]::IsNullOrWhiteSpace($containerAppName)) { throw "No Container App found in resource group $ResourceGroupName" }
Write-Host "    Container App: $containerAppName" -ForegroundColor Green

$acrLoginServer = az acr show --name $acrName --query "loginServer" -o tsv
Write-Host "    ACR Login Server: $acrLoginServer" -ForegroundColor Green

# Resolve API app ID and tenant for UI auth config
$tenantId = (az account show --query "tenantId" -o tsv)
$containerAppFqdn = az containerapp show --name $containerAppName --resource-group $ResourceGroupName --query "properties.configuration.ingress.fqdn" -o tsv

# Look up the Entra API app for dashboard auth config
$apiAppId = az ad app list --display-name "Chargeback API" --query "[0].appId" -o tsv
$client1AppId = az ad app list --display-name "Chargeback Sample Client" --query "[0].appId" -o tsv

# ── Step 2: Write UI auth config ─────────────────────────────────────

Write-Host ""
Write-Host "  Step 2: Writing dashboard auth config..." -ForegroundColor Yellow

$uiEnvDir = Join-Path $RepoRoot "src\chargeback-ui"
$uiEnvFile = Join-Path $uiEnvDir ".env.production.local"
$uiEnvContent = @(
    "VITE_AZURE_TENANT_ID=$tenantId"
    "VITE_AZURE_CLIENT_ID=$client1AppId"
    "VITE_AZURE_API_APP_ID=$apiAppId"
    "VITE_AZURE_REDIRECT_URI=https://$containerAppFqdn/"
    "VITE_AZURE_SCOPE=api://$apiAppId/access_as_user"
    "VITE_API_URL=https://$containerAppFqdn"
)
Set-Content -Path $uiEnvFile -Value $uiEnvContent -Encoding UTF8
Write-Host "    ✓ Wrote $uiEnvFile" -ForegroundColor Green

# ── Step 3: Build Docker image ───────────────────────────────────────

$imageRepository = "$acrLoginServer/chargeback-api"
if ([string]::IsNullOrWhiteSpace($Tag)) {
    $Tag = "run-$([DateTime]::UtcNow.ToString('yyyyMMddHHmmss'))"
}
$imageTag = "${imageRepository}:$Tag"

Write-Host ""
Write-Host "  Step 3: Building container image..." -ForegroundColor Yellow
Write-Host "    Image: $imageTag" -ForegroundColor Gray

if ($SkipBuild) {
    Write-Host "    ⊘ Build skipped (-SkipBuild)" -ForegroundColor DarkGray
} else {
    docker build -t $imageTag -f "$RepoRoot/src/Dockerfile" "$RepoRoot/src"
    if ($LASTEXITCODE -ne 0) { throw "Docker build failed." }
    Write-Host "    ✓ Image built" -ForegroundColor Green
}

# ── Step 4: Push to ACR ──────────────────────────────────────────────

Write-Host ""
Write-Host "  Step 4: Pushing to ACR..." -ForegroundColor Yellow

az acr login --name $acrName
if ($LASTEXITCODE -ne 0) { throw "ACR login failed." }

docker push $imageTag
if ($LASTEXITCODE -ne 0) { throw "Docker push failed." }

# Also tag as latest
docker tag $imageTag "${imageRepository}:latest"
docker push "${imageRepository}:latest"

Write-Host "    ✓ Image pushed to $acrLoginServer" -ForegroundColor Green

# ── Step 5: Update Container App ─────────────────────────────────────

Write-Host ""
Write-Host "  Step 5: Updating Container App..." -ForegroundColor Yellow

az containerapp update `
    --name $containerAppName `
    --resource-group $ResourceGroupName `
    --image $imageTag `
    -o none

if ($LASTEXITCODE -ne 0) { throw "Container App update failed." }

$newFqdn = az containerapp show --name $containerAppName --resource-group $ResourceGroupName --query "properties.configuration.ingress.fqdn" -o tsv
Write-Host "    ✓ Container App updated" -ForegroundColor Green
Write-Host "    URL: https://$newFqdn" -ForegroundColor Cyan

# ── Done ─────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "  ✓ Deployment complete!" -ForegroundColor Green
Write-Host ""
Write-Host "  Container App: https://$newFqdn" -ForegroundColor Cyan
Write-Host "  Image:         $imageTag" -ForegroundColor Cyan
Write-Host ""
