from __future__ import annotations

import base64
import io
import json
import os
from urllib import request

from PIL import Image


AZURE_OPENAI_ENDPOINT = os.getenv(
    "AZURE_OPENAI_ENDPOINT",
    "https://guardian-ai-openai-617db5.openai.azure.com",
).rstrip("/")
AZURE_OPENAI_DEPLOYMENT = os.getenv(
    "AZURE_OPENAI_DEPLOYMENT", "guardian-vision-accurate"
)
AZURE_OPENAI_API_VERSION = os.getenv("AZURE_OPENAI_API_VERSION", "2024-10-21")


def verify_helmet(image: Image.Image) -> dict[str, object]:
    api_key = os.getenv("AZURE_OPENAI_API_KEY")
    if not api_key:
        raise RuntimeError("AZURE_OPENAI_API_KEY is not configured")

    output = io.BytesIO()
    image.convert("RGB").save(output, format="JPEG", quality=88)
    encoded = base64.b64encode(output.getvalue()).decode("ascii")
    payload = {
        "messages": [
            {
                "role": "system",
                "content": (
                    "You are a motorcycle safety verifier. Inspect only the main visible "
                    "person. A motorcycle helmet with a visor counts as a helmet. Return "
                    "JSON only with helmet_present (boolean), properly_worn (boolean), "
                    "helmet_type (string), confidence (0 to 1), and reason (short string). "
                    "Do not infer helmet status from clothing, printed letters, or objects "
                    "away from the person's head. If the head is not clearly visible, set "
                    "both booleans false and explain that verification is uncertain."
                ),
            },
            {
                "role": "user",
                "content": [
                    {
                        "type": "text",
                        "text": "Is this person wearing a motorcycle helmet correctly?",
                    },
                    {
                        "type": "image_url",
                        "image_url": {
                            "url": f"data:image/jpeg;base64,{encoded}",
                            "detail": "high",
                        },
                    },
                ],
            },
        ],
        "temperature": 0,
        "max_tokens": 220,
        "response_format": {"type": "json_object"},
    }
    url = (
        f"{AZURE_OPENAI_ENDPOINT}/openai/deployments/"
        f"{AZURE_OPENAI_DEPLOYMENT}/chat/completions"
        f"?api-version={AZURE_OPENAI_API_VERSION}"
    )
    http_request = request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"api-key": api_key, "Content-Type": "application/json"},
        method="POST",
    )
    with request.urlopen(http_request, timeout=60) as response:
        body = json.loads(response.read().decode("utf-8"))
    return json.loads(body["choices"][0]["message"]["content"])
