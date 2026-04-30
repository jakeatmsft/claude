"""Streaming chat loop against a Claude deployment in Microsoft Foundry."""

from __future__ import annotations

import os
import sys

from anthropic import AnthropicFoundry
from azure.identity import DefaultAzureCredential, get_bearer_token_provider
from dotenv import load_dotenv


SYSTEM_PROMPT = (
    "You are a concise, helpful assistant running on Microsoft Foundry."
)


def build_client() -> tuple[AnthropicFoundry, str]:
    load_dotenv(".env.local", override=False)
    load_dotenv(".env", override=False)

    base_url = os.environ.get("CLAUDE_BASE_URL")
    deployment = os.environ.get("CLAUDE_DEPLOYMENT_NAME")
    if not base_url or not deployment:
        print(
            "Set CLAUDE_BASE_URL and CLAUDE_DEPLOYMENT_NAME (see .env.sample).",
            file=sys.stderr,
        )
        sys.exit(1)

    token_provider = get_bearer_token_provider(
        DefaultAzureCredential(), "https://ai.azure.com/.default"
    )
    return AnthropicFoundry(
        azure_ad_token_provider=token_provider, base_url=base_url
    ), deployment


def main() -> None:
    client, deployment = build_client()
    history: list[dict] = []

    print(f"Connected to {deployment}. Type 'exit' to quit.\n")
    while True:
        try:
            user = input("you> ").strip()
        except (EOFError, KeyboardInterrupt):
            print()
            return
        if not user:
            continue
        if user.lower() in {"exit", "quit"}:
            return

        history.append({"role": "user", "content": user})

        print("claude> ", end="", flush=True)
        assistant_text = ""
        with client.messages.stream(
            model=deployment,
            max_tokens=1024,
            system=SYSTEM_PROMPT,
            messages=history,
        ) as stream:
            for text in stream.text_stream:
                assistant_text += text
                print(text, end="", flush=True)
        print("\n")
        history.append({"role": "assistant", "content": assistant_text})


if __name__ == "__main__":
    main()
