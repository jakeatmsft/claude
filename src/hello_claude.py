"""Minimal Claude-on-Foundry sample using the Claude SDK with Entra ID.

Reads configuration from environment (or .env / .env.local):
    CLAUDE_BASE_URL          e.g. https://<resource>.services.ai.azure.com/anthropic
    CLAUDE_DEPLOYMENT_NAME   the Foundry deployment name (NOT the model id)

Auth: Microsoft Entra ID via DefaultAzureCredential. Run `az login` first.
"""

from __future__ import annotations

import os
import sys

from anthropic import AnthropicFoundry
from azure.identity import DefaultAzureCredential, get_bearer_token_provider
from dotenv import load_dotenv


def main() -> int:
    # Load .env.local first (developer overrides), then .env
    load_dotenv(".env.local", override=False)
    load_dotenv(".env", override=False)

    base_url = os.environ.get("CLAUDE_BASE_URL")
    deployment = os.environ.get("CLAUDE_DEPLOYMENT_NAME")

    if not base_url or not deployment:
        print(
            "Set CLAUDE_BASE_URL and CLAUDE_DEPLOYMENT_NAME (see .env.sample).",
            file=sys.stderr,
        )
        return 1

    token_provider = get_bearer_token_provider(
        DefaultAzureCredential(), "https://ai.azure.com/.default"
    )

    client = AnthropicFoundry(
        azure_ad_token_provider=token_provider,
        base_url=base_url,
    )

    message = client.messages.create(
        model=deployment,
        max_tokens=1024,
        messages=[
            {"role": "user", "content": "What are 3 things to visit in Seattle?"}
        ],
    )

    for block in message.content:
        text = getattr(block, "text", None)
        if text:
            print(text)

    print(f"\n[usage] input={message.usage.input_tokens} output={message.usage.output_tokens}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
