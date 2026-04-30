<#
.SYNOPSIS
    Lists Azure regions where Claude models are available for the currently
    selected Azure subscription.

.DESCRIPTION
    Queries the Cognitive Services model catalog in parallel across a curated
    list of Azure regions and returns every Claude model offering visible to
    the current `az` login context (tenant + subscription).

    Run `az login --tenant <TENANT_ID>` and `az account set --subscription <SUB_ID>`
    before invoking this script.

.PARAMETER Regions
    Optional list of Azure region short names to scan. Defaults to a broad
    set of public commercial regions where Foundry is typically offered.

.PARAMETER ThrottleLimit
    Maximum number of parallel az CLI calls. Default 16.

.PARAMETER OutputFormat
    Table (default) or Json or Object (raw pipeline output).

.EXAMPLE
    ./Get-ClaudeRegions.ps1

.EXAMPLE
    ./Get-ClaudeRegions.ps1 -OutputFormat Json | Out-File claude-regions.json
#>
[CmdletBinding()]
param(
    [string[]]$Regions = @(
        'eastus','eastus2','westus','westus2','westus3',
        'northcentralus','southcentralus','centralus',
        'westeurope','northeurope','uksouth','francecentral',
        'germanywestcentral','switzerlandnorth','swedencentral',
        'norwayeast','polandcentral','italynorth','spaincentral',
        'japaneast','koreacentral','southeastasia','eastasia',
        'australiaeast','brazilsouth','canadacentral','canadaeast',
        'southafricanorth','centralindia','uaenorth','israelcentral'
    ),
    [int]$ThrottleLimit = 16,
    [ValidateSet('Table','Json','Object')]
    [string]$OutputFormat = 'Table'
)

$ErrorActionPreference = 'Stop'

# Verify az login context
try {
    $ctx = az account show -o json 2>$null | ConvertFrom-Json
    if (-not $ctx) { throw "Not logged in." }
} catch {
    Write-Error "Run 'az login --tenant <TENANT_ID>' first."
    exit 1
}

Write-Verbose "Tenant:       $($ctx.tenantId)"
Write-Verbose "Subscription: $($ctx.name) ($($ctx.id))"

# NOTE: 'Anthropic' is the value Foundry uses in its model catalog `format`
# field. It is the on-the-wire API literal — do not change it.
$found = $Regions | ForEach-Object -Parallel {
    $r = $_
    $json = az cognitiveservices model list --location $r -o json 2>$null
    if (-not $json) { return }
    try { $models = $json | ConvertFrom-Json } catch { return }
    $models |
        Where-Object { $_.model.format -eq 'Anthropic' } |
        ForEach-Object {
            [PSCustomObject]@{
                Region  = $r
                Model   = $_.model.name
                Version = $_.model.version
                SKU     = (($_.model.skus | ForEach-Object name) -join ',')
            }
        }
} -ThrottleLimit $ThrottleLimit |
    Sort-Object Model, Region, Version -Unique

switch ($OutputFormat) {
    'Json'   { $found | ConvertTo-Json -Depth 4 }
    'Object' { $found }
    default  { $found | Format-Table -AutoSize }
}
