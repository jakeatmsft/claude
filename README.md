# Claude on Microsoft Foundry — Starter

> Short link: **<https://aka.ms/claude/start>**

Provision a [Microsoft Foundry](https://learn.microsoft.com/azure/ai-foundry/) account with a **Claude** model deployment, then call it with the **[Claude SDK](https://docs.claude.com/en/api/client-sdks)** using Microsoft Entra ID — end-to-end via [Azure Developer CLI (`azd`)](https://learn.microsoft.com/azure/developer/azure-developer-cli/).

Two equivalent IaC variants ship side-by-side. Pick one and `azd up`:

| Variant | Folder | Run from |
|---|---|---|
| **Bicep** | [`infra-bicep/`](./infra-bicep/) | `cd infra-bicep && azd up` |
| **Terraform** | [`infra-terraform/`](./infra-terraform/) | `cd infra-terraform && azd up` |

The Python sample under [`src/`](./src/) works against either.

> **Looking for something more advanced?** Jump to: [auto-refreshing Entra ID tokens for long-running processes](#advanced-long-running-processes-auto-refreshing-the-entra-id-token) · [preprovision preflight](#preprovision-preflight-terms-acceptance--quota) · [check Claude quota & capacity programmatically](#advanced-check-claude-quota--capacity-programmatically).

## Prerequisites

- An Azure subscription [eligible to deploy Claude in Foundry](https://learn.microsoft.com/azure/ai-foundry/foundry-models/how-to/use-foundry-models-claude#prerequisites), with `Contributor` on the target subscription/resource group (see [Required permissions](#required-permissions) for the full breakdown, including the data-plane role you need to call the model).
- Region: `eastus2` or `swedencentral` (or `westus2` for `claude-opus-*`).
- Tools: [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli), [azd](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd), Python ≥ 3.10, and [Terraform](https://developer.hashicorp.com/terraform/install) ≥ 1.6 (Terraform variant only).

## Quickstart

```powershell
git clone https://github.com/Azure-Samples/claude.git
cd claude/infra-terraform   # or: cd claude/infra-bicep

# If your Claude-eligible subscription lives in a non-default tenant, pass --tenant-id:
azd auth login   # or: azd auth login --tenant-id <tenant-id>

azd env new my-claude
azd env set CLAUDE_ORGANIZATION_NAME "Contoso"
azd env set AZURE_LOCATION "eastus2"
# Optional — skip the interactive subscription picker on first `azd up`:
# azd env set AZURE_SUBSCRIPTION_ID <subscription-id>
azd up

# Export endpoint + deployment name to a shared .env.local at the repo root.
# Use Out-File so the file is UTF-8 (Windows PowerShell 5.1's `>` writes UTF-16, which python-dotenv mis-parses).
azd env get-values | Out-File -Encoding utf8 ..\.env.local
# macOS/Linux: azd env get-values > ../.env.local

# Run the Python sample from the repo root (so .env.local is discovered)
cd ..
python -m venv .venv && . .venv/Scripts/Activate.ps1   # macOS/Linux: source .venv/bin/activate
pip install -r requirements.txt
python src/hello_claude.py     # one-shot Messages call
python src/chat_stream.py      # interactive streaming chat — type a message, `exit` to quit
```

<details>
<summary><strong>Alternative: API-key auth (dev/test only)</strong></summary>

If you don't have a data-plane role on the Foundry account yet, you can run a quick check with an API key. Prefer Entra ID for anything beyond local testing — keys can't be scoped per-user and rotate manually.

```powershell
# FOUNDRY_ACCOUNT_NAME and AZURE_RESOURCE_GROUP are emitted by `azd env get-values`
$env:CLAUDE_API_KEY = (az cognitiveservices account keys list `
    --name $env:FOUNDRY_ACCOUNT_NAME `
    --resource-group $env:AZURE_RESOURCE_GROUP --query key1 -o tsv)
python src/hello_claude_apikey.py
```

</details>

## Configuration

| Var | Required | Default | Notes |
|---|---|---|---|
| `CLAUDE_ORGANIZATION_NAME` | yes | — | Surfaced via `modelProviderData` |
| `AZURE_LOCATION` | yes | — | `eastus2` / `swedencentral` / `westus2` |
| `CLAUDE_COUNTRY_CODE` | no | `US` | 2-letter ISO |
| `CLAUDE_INDUSTRY` | no | `technology` | **lowercase**: `technology`, `finance`, `healthcare`, `education`, `retail`, `manufacturing`, `government`, `media`, `other` |
| `CLAUDE_MODEL_NAME` | no | `claude-sonnet-4-6` | Run `./Get-ClaudeRegions.ps1` to see availability |
| `CLAUDE_MODEL_VERSION` | no | `1` | |
| `CLAUDE_MODEL_CAPACITY` | no | `50` | TPM / 1000 |
| `ASSIGN_RBAC` | no | `false` | `true` to grant Azure AI User to `AZURE_PRINCIPAL_ID` (needs `roleAssignments/write`) |

## SDK call shape

We use the plain `anthropic.Anthropic` client. The Entra ID token is captured once at startup and is valid for ~1 hour — fine for a one-shot script or a short-lived process. For long-running processes, see the [advanced section below](#advanced-long-running-processes-auto-refreshing-the-entra-id-token).

```python
from anthropic import Anthropic
from azure.identity import DefaultAzureCredential

token = DefaultAzureCredential().get_token(
    "https://ai.azure.com/.default"
).token
client = Anthropic(
    auth_token=token,
    base_url="https://<resource>.services.ai.azure.com/anthropic",
)
msg = client.messages.create(
    model="<deployment-name>",
    max_tokens=1024,
    messages=[{"role": "user", "content": "Hi"}],
)
```

> Pass the **deployment name** (not the model id) as `model`. The SDK appends `/v1/messages` to the configured `base_url`.

<details id="advanced-long-running-processes-auto-refreshing-the-entra-id-token">
<summary><strong>Advanced: long-running processes (auto-refreshing the Entra ID token)</strong></summary>

The plain `anthropic.Anthropic` client only accepts `auth_token: str | None`, so a captured token will start failing with `401 Unauthorized` after ~1 hour.

For services, daemons, long batch jobs, or notebooks left open, use [src/hello_claude_token_refresh.py](./src/hello_claude_token_refresh.py). It defines a tiny `AnthropicIdentity(Anthropic)` subclass that overrides the `auth_token` property to call `azure.identity.get_bearer_token_provider(...)` per request, giving free per-request token refresh:

```python
from azure.identity import DefaultAzureCredential, get_bearer_token_provider
# AnthropicIdentity is defined in hello_claude_token_refresh.py
from hello_claude_token_refresh import AnthropicIdentity

token_provider = get_bearer_token_provider(
    DefaultAzureCredential(), "https://ai.azure.com/.default"
)
client = AnthropicIdentity(
    azure_ad_token_provider=token_provider,
    base_url="https://<resource>.services.ai.azure.com/anthropic",
)
```

If the Anthropic SDK ever accepts a callable for `auth_token`, this shim becomes unnecessary.

</details>

<details>
<summary><strong>What gets deployed</strong></summary>

- **Microsoft Foundry** account (`Microsoft.CognitiveServices/accounts`, kind `AIServices`, SKU `S0`, `allowProjectManagement = true`)
- **Foundry project**
- A **Claude model deployment** (`GlobalStandard`) with the required `modelProviderData` block
- *Optional* RBAC: *Azure AI User* + *Azure AI Project Manager* on the deploying principal (set `ASSIGN_RBAC=true`)

</details>

<details>
<summary><strong>Repo layout</strong></summary>

```
claude/
├── infra-bicep/        # azd template — Bicep variant
├── infra-terraform/    # azd template — Terraform variant
├── scripts/
│   ├── preflight-claude.ps1          # `azd up` preflight: gates on terms-accepted + quota
│   └── preflight-claude.sh           # POSIX equivalent
├── src/
│   ├── hello_claude.py               # One-shot Messages call (Entra ID)
│   ├── hello_claude_apikey.py        # Same, but with an API key (dev/test only)
│   ├── hello_claude_token_refresh.py # Long-running variant with auto-refreshing Entra token
│   ├── chat_stream.py                # Streaming multi-turn chat loop
│   └── check_claude_quota.py         # Inspect Claude quota + capacity via ARM (see Advanced)
├── Get-ClaudeRegions.ps1
├── requirements.txt
└── .env.sample
```

</details>

## Troubleshooting

| Symptom | Fix |
|---|---|
| `AnthropicOrganizationCreationException` / `AnthropicOrganizationCreationFailed` | `modelProviderData` is missing or malformed. Ensure all three of `organizationName`, `countryCode`, `industry` are set, and that `industry` is lowercase. |
| `Project can only be created under AIServices Kind account with allowProjectManagement set to true` | Account property missing. Both variants here set it; check you didn't downgrade the API version. |
| `404 Not Found` on inference | Base URL must end in `/anthropic` — `https://<resource>.services.ai.azure.com/anthropic`. |
| `401 Unauthorized` | Token scope must be `https://ai.azure.com/.default`. Re-run `az login`. |
| `401 Unauthorized` after ~1 hour of running | The Entra ID token captured at startup has expired. The plain `Anthropic` client doesn't auto-refresh — see the [advanced section](#advanced-long-running-processes-auto-refreshing-the-entra-id-token) for [src/hello_claude_token_refresh.py](./src/hello_claude_token_refresh.py), which uses an `AnthropicIdentity` shim to refresh per request. |
| `403 Forbidden` | Missing a data-plane role on the Foundry account. Grant `Cognitive Services User`, `Azure AI User`, or `Azure AI Developer` (see permissions details below). |
| `Region not available` | Deploy to `eastus2` or `swedencentral` (or `westus2` for opus-only). |
| Subscription can't deploy Claude | Confirm subscription eligibility per the [official docs](https://learn.microsoft.com/azure/ai-foundry/foundry-models/how-to/use-foundry-models-claude#prerequisites). The [preprovision preflight](#preprovision-preflight-terms-acceptance--quota) warns about this before `azd up` calls the RP. |
| `Error occurred when subscribing to Marketplace: Marketplace Subscription purchase eligibility check failed` | Your subscription cannot purchase the Anthropic offer (no entitlement, internal/sandbox sub, paid-offer policy denial, etc.). Either use a subscription with Claude-on-Foundry entitlement, or pre-accept the agreement explicitly with `az term accept --publisher anthropic --product anthropic-<model>-offer --plan anthropic-<model>-test-plan`. |
| Preflight: `Marketplace offer ... not found` | `CLAUDE_MODEL_NAME` is misspelled, the model isn't in the Anthropic-on-Foundry catalog yet, or Anthropic changed the plan-name convention. |

<details>
<summary><strong>Why <code>modelProviderData</code> matters</strong></summary>

Claude deployments fail with `AnthropicOrganizationCreationException` if `modelProviderData` is missing. **`industry` must be lowercase** to match the Foundry portal dropdown.

The Terraform variant uses `azapi_resource` for both the Foundry account and the Claude deployment, because the native `azurerm_cognitive_account` / `azurerm_cognitive_deployment` resources do not yet expose `allowProjectManagement` or `modelProviderData` ([tracked here](https://github.com/hashicorp/terraform-provider-azurerm/issues/31140)). The Bicep variant uses native resources at API version `2025-10-01-preview`, which support both.

</details>

<details id="preprovision-preflight-terms-acceptance--quota">
<summary><strong>Preprovision preflight: Marketplace catalog &amp; quota</strong></summary>

Both IaC variants run [`scripts/preflight-claude.ps1`](./scripts/preflight-claude.ps1) (with [`preflight-claude.sh`](./scripts/preflight-claude.sh) as a POSIX fallback) from the `preprovision` hook in `azure.yaml`, to give you a fast, descriptive error for the most common misconfigurations before `azd up` calls the Cognitive Services RP.

The script queries the [Microsoft.MarketplaceOrdering REST API](https://learn.microsoft.com/rest/api/marketplaceordering/marketplace-agreements/get). Claude models are published under publisher `anthropic` with offer/plan naming `anthropic-<model-name>-offer` / `anthropic-<model-name>-test-plan`.

What the preflight does, and does not, do:

| Check | Behavior |
|---|---|
| `CLAUDE_ORGANIZATION_NAME` / `AZURE_LOCATION` set | Hard fail (exit 1) if missing. |
| Marketplace offer/plan resolves at all | Hard fail (exit 4) on 400 "offer not found" — catches `CLAUDE_MODEL_NAME` typos and unreleased SKUs. |
| Marketplace agreement `properties.accepted == true` | **Warning only.** See note below. |
| `az cognitiveservices usage list` quota headroom for the SKU | Warning if requested capacity exceeds available. |

> **Why `accepted: false` is a warning, not a hard fail.** On eligible subscriptions, the Cognitive Services RP performs an implicit Marketplace subscribe during deployment that auto-accepts the agreement — every signed Anthropic plan on the test sub used to build this template was signed by the subscription's managed identity at the moment the model was first deployed, not by a human. `accepted: false` therefore means "no agreement record exists yet," which may or may not block deployment depending on subscription entitlement. If your sub is ineligible (sandbox/internal, no entitlement, paid-offer policy denial), `azd up` will fail with `Error occurred when subscribing to Marketplace` a minute into provisioning — the preflight warning surfaces that risk early but cannot definitively tell which case you're in.

Run it standalone any time:

```powershell
$env:CLAUDE_ORGANIZATION_NAME = "Contoso"
$env:AZURE_LOCATION = "eastus2"
$env:CLAUDE_MODEL_NAME = "claude-sonnet-4-6"
pwsh -File scripts/preflight-claude.ps1
```

To list all Anthropic agreements (signed or not) visible on the active subscription:

```powershell
$sub = az account show --query id -o tsv
az rest --method get --url "https://management.azure.com/subscriptions/$sub/providers/Microsoft.MarketplaceOrdering/agreements?api-version=2021-01-01" --query "value[?properties.publisher=='anthropic']"
```

To pre-accept explicitly (rarely needed thanks to the RP auto-accept; useful for restricted-subscription scenarios):

```powershell
az term accept --publisher anthropic --product anthropic-claude-sonnet-4-6-offer --plan anthropic-claude-sonnet-4-6-test-plan
```

</details>

<details id="advanced-check-claude-quota--capacity-programmatically">
<summary><strong>Advanced: check Claude quota &amp; capacity programmatically</strong></summary>

[`src/check_claude_quota.py`](./src/check_claude_quota.py) queries the Azure Resource Manager APIs documented for Foundry quota — the [Usages API](https://learn.microsoft.com/azure/foundry/openai/how-to/quota?tabs=python#programmatically-check-quota-and-capacity) and the Model Capacities API — and prints a single merged table keyed on `(model, region)` with TPM utilization, derived RPM limits, deployable capacity, and model version.

Requirements:

- Caller authenticated via `az login` / `azd auth login` (or any other `DefaultAzureCredential` source).
- `Cognitive Services Usages Reader` (or `Reader`) at subscription scope. Without it, the calls return `403`.
- The subscription must be Enterprise or MCA-E for Claude quota lines to appear (per the [official prerequisites](https://learn.microsoft.com/azure/ai-foundry/foundry-models/how-to/use-foundry-models-claude#prerequisites)).

Run it:

```powershell
python src/check_claude_quota.py                                    # current subscription, default regions
python src/check_claude_quota.py --regions eastus2 swedencentral    # explicit regions
python src/check_claude_quota.py --subscription <sub-id> --tenant <tenant-id>
python src/check_claude_quota.py --json                             # machine-readable
```

Flags:

| Flag | Default | Notes |
|---|---|---|
| `--subscription` | current `az` subscription / `AZURE_SUBSCRIPTION_ID` | Subscription to query. |
| `--tenant` | caller's home tenant | Use when the subscription lives in a different tenant. Auth chain becomes `AzureCliCredential` + `AzureDeveloperCliCredential` scoped to that tenant. |
| `--regions` | `eastus2 swedencentral` | Regions to query for usages. |
| `--models` | all known Claude models | Filter capacity lookup. |
| `--json` | off | Emit raw JSON instead of the merged table. |

Notes on the output:

- **RPM is not a separate quota line** in the Usages API for Claude — only TPM is allocated. The `RPM Limit*` column is **derived** from the per-model RPM:TPM ratios published in the [Foundry Claude docs](https://learn.microsoft.com/azure/foundry/foundry-models/how-to/use-foundry-models-claude#api-quotas-and-limits) (e.g. Sonnet 4.5 ships at 2 RPM per 1 kTPM; everything else at 1:1).
- **TPM Limit values are reported in thousands** by the underlying API; the script multiplies by 1,000 so the table reads in raw tokens-per-minute.
- The **Model Capacities API requires `modelVersion`**, not just `modelName`. The script discovers active versions automatically from `locations/{region}/models` filtered to `format=Anthropic`.
- The `Def RPM` / `Def TPM` columns are the **public non-EA defaults** (always 0/0 because Claude is gated to Enterprise + MCA-E subscriptions); the `TPM Used` / `TPM Limit` / `RPM Limit*` / `Capacity` columns are the values your EA/MCA-E subscription is actually getting.

</details>

## Required permissions

| Action | Role | Scope |
|---|---|---|
| Provision Foundry + Claude deployment | `Contributor` (or `Cognitive Services Contributor`) | Resource group / subscription |
| Assign RBAC inside this template (`ASSIGN_RBAC=true`) | `User Access Administrator` or `Owner` | Resource group / subscription |
| Call the Messages API with Entra ID | `Azure AI User` *(or `Azure AI Developer` — see note)* | Foundry account |

If you do not have `Microsoft.Authorization/roleAssignments/write`, leave `ASSIGN_RBAC=false` (the default) and ask an admin to grant one of the roles below on the Foundry account afterwards.

**Roles that work for Claude inference:**

| Role | Data action(s) | Notes |
|---|---|---|
| `Cognitive Services User` | `Microsoft.CognitiveServices/*/read` + inference action | The minimum role recommended by [the official docs](https://learn.microsoft.com/azure/ai-foundry/foundry-models/how-to/use-foundry-models-claude#troubleshooting). |
| `Azure AI User` | `Microsoft.CognitiveServices/*` | Broadest data-plane access; what this template assigns when `ASSIGN_RBAC=true`. |
| `Azure AI Developer` | includes `Microsoft.CognitiveServices/accounts/MaaS/*` | Sufficient for Claude because Claude routes through the **MaaS** data path as a partner/marketplace model. (It is **not** sufficient for first-party Foundry models that route through `accounts/AIServices/*`.) |

> The role `Azure AI Developer` was historically called out as *insufficient* for Foundry inference. That guidance still applies to first-party `AIServices` models, but Claude/Anthropic deployments dispatch through `Microsoft.CognitiveServices/accounts/MaaS/*`, which `Azure AI Developer` already grants. Verified against `claude-sonnet-4-6` on `2025-10-01-preview`.

## References

- [Use Claude models in Microsoft Foundry](https://learn.microsoft.com/azure/ai-foundry/foundry-models/how-to/use-foundry-models-claude?tabs=python)
- [Claude SDK (Python)](https://docs.claude.com/en/api/client-sdks)
- [Claude Messages API](https://docs.claude.com/en/api/messages)
- [azd Terraform support](https://learn.microsoft.com/azure/developer/azure-developer-cli/use-terraform-for-azd)

## Contributing

Issues and PRs welcome. Please open an issue describing the change before sending large PRs.

## License

[MIT](./LICENSE)
