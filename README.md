# Claude on Microsoft Foundry — Starter

Provision a [Microsoft Foundry](https://learn.microsoft.com/azure/ai-foundry/) account with a **Claude** model deployment, then call it with the **[Claude SDK](https://docs.claude.com/en/api/client-sdks)** using Microsoft Entra ID — end-to-end via [Azure Developer CLI (`azd`)](https://learn.microsoft.com/azure/developer/azure-developer-cli/).

Two equivalent IaC variants ship side-by-side. Pick one and `azd up`:

| Variant | Folder | Run from |
|---|---|---|
| **Bicep** | [`infra-bicep/`](./infra-bicep/) | `cd infra-bicep && azd up` |
| **Terraform** | [`infra-terraform/`](./infra-terraform/) | `cd infra-terraform && azd up` |

The Python sample under [`src/`](./src/) works against either.

## Prerequisites

- An Azure subscription [eligible to deploy Claude in Foundry](https://learn.microsoft.com/azure/ai-foundry/foundry-models/how-to/use-foundry-models-claude#prerequisites), with `Contributor` on the target subscription/resource group (see [Required permissions](#required-permissions) for the full breakdown, including the data-plane role you need to call the model).
- Region: `eastus2` or `swedencentral` (or `westus2` for `claude-opus-*`).
- Tools: [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli), [azd](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd), Python ≥ 3.10, and [Terraform](https://developer.hashicorp.com/terraform/install) ≥ 1.6 (Terraform variant only).

## Quickstart

```powershell
git clone https://github.com/Azure-Samples/claude.git
cd claude/infra-terraform   # or: cd claude/infra-bicep

azd auth login
azd env new my-claude
azd env set CLAUDE_ORGANIZATION_NAME "Contoso"
azd env set AZURE_LOCATION "eastus2"
azd up

# Export endpoint + deployment name to a shared .env.local at repo root
azd env get-values > ..\.env.local

# Run the Python sample
cd ..
python -m venv .venv && . .venv/Scripts/Activate.ps1   # macOS/Linux: source .venv/bin/activate
pip install -r requirements.txt
python src/hello_claude.py
python src/chat_stream.py
```

<details>
<summary><strong>Alternative: API-key auth (dev/test only)</strong></summary>

If you don't have a data-plane role on the Foundry account yet, you can run a quick check with an API key. Prefer Entra ID for anything beyond local testing — keys can't be scoped per-user and rotate manually.

```powershell
$env:CLAUDE_API_KEY = (az cognitiveservices account keys list `
    --name <foundry-account-name> `
    --resource-group <rg> --query key1 -o tsv)
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

```python
from anthropic import AnthropicFoundry
from azure.identity import DefaultAzureCredential, get_bearer_token_provider

token_provider = get_bearer_token_provider(
    DefaultAzureCredential(), "https://ai.azure.com/.default"
)
client = AnthropicFoundry(
    azure_ad_token_provider=token_provider,
    base_url="https://<resource>.services.ai.azure.com/anthropic",
)
msg = client.messages.create(
    model="<deployment-name>",
    max_tokens=1024,
    messages=[{"role": "user", "content": "Hi"}],
)
```

> Pass the **deployment name** (not the model id) as `model`. The SDK appends `/v1/messages` to the configured `base_url`.

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
├── src/
│   ├── hello_claude.py        # One-shot Messages call (Entra ID)
│   ├── hello_claude_apikey.py # Same, but with an API key (dev/test only)
│   └── chat_stream.py         # Streaming multi-turn chat loop
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
| `403 Forbidden` | Missing a data-plane role on the Foundry account. Grant `Cognitive Services User`, `Azure AI User`, or `Azure AI Developer` (see permissions details below). |
| `Region not available` | Deploy to `eastus2` or `swedencentral` (or `westus2` for opus-only). |
| Subscription can't deploy Claude | Confirm subscription eligibility per the [official docs](https://learn.microsoft.com/azure/ai-foundry/foundry-models/how-to/use-foundry-models-claude#prerequisites). |

<details>
<summary><strong>Why <code>modelProviderData</code> matters</strong></summary>

Claude deployments fail with `AnthropicOrganizationCreationException` if `modelProviderData` is missing. **`industry` must be lowercase** to match the Foundry portal dropdown.

The Terraform variant uses `azapi_resource` for both the Foundry account and the Claude deployment, because the native `azurerm_cognitive_account` / `azurerm_cognitive_deployment` resources do not yet expose `allowProjectManagement` or `modelProviderData` ([tracked here](https://github.com/hashicorp/terraform-provider-azurerm/issues/31140)). The Bicep variant uses native resources at API version `2025-10-01-preview`, which support both.

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
