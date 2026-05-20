#!/usr/bin/env bash
# Preflight check for Claude-on-Microsoft-Foundry deployments.
#
# Gates `azd up` on:
#   1. Required env vars being set.
#   2. The chosen Claude model exists in the Anthropic-on-Foundry Marketplace
#      catalog at all (offer/plan must resolve via Microsoft.MarketplaceOrdering).
#      A typo in CLAUDE_MODEL_NAME is a hard fail here, before any RP call.
#   3. (Informational) Whether the Marketplace agreement is already signed.
#      An UNSIGNED agreement is NOT a hard fail \u2014 the Cognitive Services RP
#      performs an implicit Marketplace subscribe during deployment that
#      auto-accepts on eligible subscriptions. The preflight warns instead.
#   4. (Informational) Per-region Cognitive Services quota headroom.
#
# Exit codes:
#   0  Preflight passed (possibly with warnings).
#   1  A required env var is missing.
#   2  Azure CLI / subscription not available.
#   4  Marketplace offer not found.

set -euo pipefail

fail() {
    local code="$1"; shift
    printf '\nERROR: %s\n\n' "$*" >&2
    exit "$code"
}

# --- 1. Required env vars ---------------------------------------------------
if [ -z "${CLAUDE_ORGANIZATION_NAME:-}" ]; then
    fail 1 "CLAUDE_ORGANIZATION_NAME is required. Run: azd env set CLAUDE_ORGANIZATION_NAME 'Your Org'"
fi
if [ -z "${AZURE_LOCATION:-}" ]; then
    fail 1 "AZURE_LOCATION is required. Run: azd env set AZURE_LOCATION eastus2"
fi

LOCATION="$AZURE_LOCATION"
MODEL_NAME="${CLAUDE_MODEL_NAME:-claude-sonnet-4-6}"
CAPACITY="${CLAUDE_MODEL_CAPACITY:-50}"

# --- 2. Azure CLI / active subscription ------------------------------------
if ! command -v az >/dev/null 2>&1; then
    fail 2 "Azure CLI (az) not found on PATH. Install: https://learn.microsoft.com/cli/azure/install-azure-cli"
fi

SUB_ID="$(az account show --query id -o tsv 2>/dev/null || true)"
if [ -z "$SUB_ID" ]; then
    fail 2 "No active Azure subscription. Run: az login   (and 'az account set --subscription <id>' if needed)"
fi

echo "Preflight: subscription $SUB_ID, location $LOCATION, model $MODEL_NAME (capacity $CAPACITY)"

# --- 3. Marketplace Ordering: authoritative terms-acceptance gate ----------
PUBLISHER="anthropic"
OFFER="anthropic-$MODEL_NAME-offer"
PLAN="anthropic-$MODEL_NAME-test-plan"
MP_URL="https://management.azure.com/subscriptions/$SUB_ID/providers/Microsoft.MarketplaceOrdering/offerTypes/virtualmachine/publishers/$PUBLISHER/offers/$OFFER/plans/$PLAN/agreements/current?api-version=2021-01-01"

set +e
MP_RAW="$(az rest --method get --url "$MP_URL" 2>&1)"
MP_EXIT=$?
set -e

if [ "$MP_EXIT" -ne 0 ]; then
    if echo "$MP_RAW" | grep -qE "was not found|BadRequest"; then
        fail 4 "Marketplace offer 'anthropic/$OFFER/$PLAN' not found.

Likely causes:
  - CLAUDE_MODEL_NAME='$MODEL_NAME' is misspelled.
  - The model isn't (yet) published in the Anthropic-on-Foundry catalog.
  - Anthropic changed the plan naming convention (currently '<offer>-test-plan').

Available Anthropic agreements on this subscription:
  az rest --method get --url 'https://management.azure.com/subscriptions/$SUB_ID/providers/Microsoft.MarketplaceOrdering/agreements?api-version=2021-01-01' --query \"value[?properties.publisher=='anthropic']\"

Underlying error:
$MP_RAW"
    fi
    fail 4 "Unexpected error querying Microsoft.MarketplaceOrdering: $MP_RAW"
fi

ACCEPTED="$(echo "$MP_RAW" | python -c 'import json, sys; print(json.load(sys.stdin)["properties"]["accepted"])' 2>/dev/null || true)"
if [ "$ACCEPTED" != "True" ] && [ "$ACCEPTED" != "true" ]; then
    cat >&2 <<EOF

WARNING: Marketplace agreement for '$MODEL_NAME' shows 'accepted: false' on subscription '$SUB_ID'.
         (publisher=$PUBLISHER, offer=$OFFER, plan=$PLAN)

         This is NOT necessarily a deploy blocker. On eligible subscriptions the Cognitive Services RP
         performs an implicit Marketplace subscribe during deployment that auto-accepts the agreement.
         If your subscription is ineligible (no entitlement, sandbox/internal-only, paid-offer policy
         denial, etc.) you'll see:

           'Error occurred when subscribing to Marketplace: Marketplace Subscription purchase
            eligibility check failed...'

         a minute into 'azd up'. If that happens, pre-accept explicitly:

           az term accept --publisher $PUBLISHER --product $OFFER --plan $PLAN

         or use a subscription with Claude-on-Foundry entitlement. See:
           https://learn.microsoft.com/azure/ai-foundry/foundry-models/how-to/use-foundry-models-claude#prerequisites

EOF
else
    echo "Preflight: Marketplace agreement already signed (publisher=$PUBLISHER, offer=$OFFER)."
fi

# --- 4. Capacity headroom (informational warning, never fail) --------------
SKU="AIServices.GlobalStandard.$MODEL_NAME"
LIMIT="$(az cognitiveservices usage list --location "$LOCATION" \
    --query "[?name.value=='$SKU'].limit | [0]" -o tsv 2>/dev/null || true)"
CURRENT="$(az cognitiveservices usage list --location "$LOCATION" \
    --query "[?name.value=='$SKU'].currentValue | [0]" -o tsv 2>/dev/null || true)"

if [ -n "$LIMIT" ]; then
    LIMIT_INT="${LIMIT%%.*}"
    CURRENT_INT="${CURRENT%%.*}"
    CURRENT_INT="${CURRENT_INT:-0}"
    AVAILABLE=$(( LIMIT_INT - CURRENT_INT ))
    if [ "$AVAILABLE" -lt "$CAPACITY" ]; then
        printf '\nWARNING: requested capacity %s exceeds available quota (%s of %s) for %s in %s.\n' \
            "$CAPACITY" "$AVAILABLE" "$LIMIT_INT" "$SKU" "$LOCATION" >&2
        printf '         Either lower CLAUDE_MODEL_CAPACITY or request a quota increase before retrying.\n\n' >&2
    else
        echo "Preflight: quota OK ($AVAILABLE of $LIMIT_INT available in $LOCATION)."
    fi
else
    echo "Preflight: no quota row visible for '$SKU' in '$LOCATION' yet — first deploy may surface a quota error from the RP." >&2
fi

echo "Preflight OK."
