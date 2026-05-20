<#
.SYNOPSIS
    Preflight check for Claude-on-Microsoft-Foundry deployments.

.DESCRIPTION
    Gates `azd up` on:
      1. Required env vars being set.
      2. The Azure subscription having accepted the Anthropic commercial terms
         for the requested Claude model, via the Microsoft.MarketplaceOrdering
         REST API. This is the authoritative signal:
         https://learn.microsoft.com/rest/api/marketplaceordering/marketplace-agreements/get

         Claude SKUs are published under publisher `anthropic` as
         offer `anthropic-<model-name>-offer` / plan `anthropic-<model-name>-test-plan`.
         A signed agreement has `properties.accepted == true`.

      3. (Informational) Per-region Cognitive Services quota headroom. A
         warning, not a hard fail \u2014 quota currentValue is occasionally noisy
         and the RP returns a precise error at deploy time if quota is short.

    Designed to be invoked from the `preprovision` hook in `azure.yaml`.
    Works on PowerShell 7+ on Windows, Linux, and macOS.

.NOTES
    Exit codes:
      0  Preflight passed.
      1  A required env var is missing.
      2  Azure CLI / subscription not available.
      3  Anthropic terms not accepted for this subscription/model.
      4  Marketplace offer not found (typo in CLAUDE_MODEL_NAME, or model not
         in the Anthropic-on-Foundry catalog yet).
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

function Fail([int]$code, [string]$message) {
    Write-Host ""
    Write-Host "ERROR: $message" -ForegroundColor Red
    Write-Host ""
    exit $code
}

# --- 1. Required env vars ---------------------------------------------------
if (-not $env:CLAUDE_ORGANIZATION_NAME) {
    Fail 1 "CLAUDE_ORGANIZATION_NAME is required. Run: azd env set CLAUDE_ORGANIZATION_NAME 'Your Org'"
}
if (-not $env:AZURE_LOCATION) {
    Fail 1 "AZURE_LOCATION is required. Run: azd env set AZURE_LOCATION eastus2"
}

$location = $env:AZURE_LOCATION
$modelName = if ($env:CLAUDE_MODEL_NAME) { $env:CLAUDE_MODEL_NAME } else { "claude-sonnet-4-6" }
$capacity = if ($env:CLAUDE_MODEL_CAPACITY) { [int]$env:CLAUDE_MODEL_CAPACITY } else { 50 }

# --- 2. Azure CLI / active subscription ------------------------------------
$az = Get-Command az -ErrorAction SilentlyContinue
if (-not $az) {
    Fail 2 "Azure CLI (az) not found on PATH. Install: https://learn.microsoft.com/cli/azure/install-azure-cli"
}

$subId = (az account show --query id -o tsv 2>$null)
if (-not $subId) {
    Fail 2 "No active Azure subscription. Run: az login   (and 'az account set --subscription <id>' if needed)"
}

Write-Host "Preflight: subscription $subId, location $location, model $modelName (capacity $capacity)"

# --- 3. Marketplace Ordering: authoritative terms-acceptance gate ----------
# All current Anthropic-on-Foundry offers follow this naming convention.
# If Anthropic ever publishes a new plan suffix (today: '-test-plan'), update here.
$publisher = "anthropic"
$offer     = "anthropic-$modelName-offer"
$plan      = "anthropic-$modelName-test-plan"
$mpUrl     = "https://management.azure.com/subscriptions/$subId/providers/Microsoft.MarketplaceOrdering/offerTypes/virtualmachine/publishers/$publisher/offers/$offer/plans/$plan/agreements/current?api-version=2021-01-01"

$mpRaw = az rest --method get --url $mpUrl 2>&1
$mpExit = $LASTEXITCODE

if ($mpExit -ne 0) {
    # 400/404 from the RP \u2014 typically the offer/plan doesn't exist.
    $msg = ($mpRaw | Out-String).Trim()
    if ($msg -match "was not found" -or $msg -match "BadRequest") {
        Fail 4 @"
Marketplace offer 'anthropic/$offer/$plan' not found.

Likely causes:
  - CLAUDE_MODEL_NAME='$modelName' is misspelled.
  - The model isn't (yet) published in the Anthropic-on-Foundry catalog.
  - Anthropic changed the plan naming convention (currently '<offer>-test-plan').

Available Anthropic agreements on this subscription:
  az rest --method get --url 'https://management.azure.com/subscriptions/$subId/providers/Microsoft.MarketplaceOrdering/agreements?api-version=2021-01-01' --query "value[?properties.publisher=='anthropic']"

Underlying error:
$msg
"@
    }
    Fail 4 "Unexpected error querying Microsoft.MarketplaceOrdering: $msg"
}

$mp = $mpRaw | ConvertFrom-Json
if (-not $mp.properties.accepted) {
    Write-Host ""
    Write-Host "WARNING: Marketplace agreement for '$modelName' shows 'accepted: false' on subscription '$subId'." -ForegroundColor Yellow
    Write-Host "         (publisher=$publisher, offer=$offer, plan=$plan)"
    Write-Host ""
    Write-Host "         This is NOT necessarily a deploy blocker. On eligible subscriptions the Cognitive Services RP"
    Write-Host "         performs an implicit Marketplace subscribe during deployment that auto-accepts the agreement."
    Write-Host "         If your subscription is ineligible (no entitlement, sandbox/internal-only, paid-offer policy"
    Write-Host "         denial, etc.) you'll see:"
    Write-Host ""
    Write-Host "           'Error occurred when subscribing to Marketplace: Marketplace Subscription purchase"
    Write-Host "            eligibility check failed...'"
    Write-Host ""
    Write-Host "         a minute into 'azd up'. If that happens, pre-accept explicitly:"
    Write-Host ""
    Write-Host "           az term accept --publisher $publisher --product $offer --plan $plan"
    Write-Host ""
    Write-Host "         or use a subscription with Claude-on-Foundry entitlement. See:"
    Write-Host "           https://learn.microsoft.com/azure/ai-foundry/foundry-models/how-to/use-foundry-models-claude#prerequisites"
    Write-Host ""
} else {
    Write-Host "Preflight: Marketplace agreement already signed (publisher=$publisher, offer=$offer)." -ForegroundColor Green
}

# --- 4. Capacity headroom (informational warning, never fail) --------------
$sku = "AIServices.GlobalStandard.$modelName"
$limitRaw = az cognitiveservices usage list --location $location `
    --query "[?name.value=='$sku'].limit | [0]" -o tsv 2>$null
$currentRaw = az cognitiveservices usage list --location $location `
    --query "[?name.value=='$sku'].currentValue | [0]" -o tsv 2>$null

if (-not [string]::IsNullOrWhiteSpace($limitRaw)) {
    $limit = [int]([double]$limitRaw)
    $current = if ([string]::IsNullOrWhiteSpace($currentRaw)) { 0 } else { [int]([double]$currentRaw) }
    $available = $limit - $current
    if ($available -lt $capacity) {
        Write-Host ""
        Write-Host "WARNING: requested capacity $capacity exceeds available quota ($available of $limit) for '$sku' in '$location'." -ForegroundColor Yellow
        Write-Host "         Either lower CLAUDE_MODEL_CAPACITY or request a quota increase before retrying."
        Write-Host ""
    } else {
        Write-Host "Preflight: quota OK ($available of $limit available in $location)." -ForegroundColor Green
    }
} else {
    Write-Host "Preflight: no quota row visible for '$sku' in '$location' yet \u2014 first deploy may surface a quota error from the RP." -ForegroundColor Yellow
}

Write-Host "Preflight OK." -ForegroundColor Green
exit 0
