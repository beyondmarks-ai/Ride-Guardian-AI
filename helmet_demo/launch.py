"""Run the local webcam demo using a private .env file; no Azure CLI required."""
from __future__ import annotations

import argparse
import getpass
import os
from pathlib import Path
from urllib.parse import urlparse

from dotenv import load_dotenv, set_key

ROOT = Path(__file__).resolve().parent
DEFAULTS = {
    'AZURE_OPENAI_ENDPOINT': 'https://guardian-ai-openai-617db5.openai.azure.com',
    'AZURE_OPENAI_DEPLOYMENT': 'guardian-vision-accurate',
    'AZURE_OPENAI_API_VERSION': '2024-10-21',
}


def configure(env_file: Path = ROOT / '.env', interactive: bool = True) -> None:
    # Existing environment variables take precedence. Never evaluate shell code.
    load_dotenv(env_file, override=False, encoding='utf-8-sig', interpolate=False)
    for key, value in DEFAULTS.items():
        os.environ.setdefault(key, value)
    api_key = os.environ.get('AZURE_OPENAI_API_KEY', '').strip()
    if not api_key or api_key == 'YOUR_AZURE_OPENAI_API_KEY':
        if not interactive:
            raise ValueError('Set AZURE_OPENAI_API_KEY in helmet_demo/.env or your environment.')
        print('First-time setup. Credentials will be saved in the local .env file, excluded from Git.')
        for key, label in [('AZURE_OPENAI_ENDPOINT', 'Azure endpoint'), ('AZURE_OPENAI_DEPLOYMENT', 'Deployment name')]:
            value = input(f'{label} [{os.environ[key]}]: ').strip()
            if value:
                os.environ[key] = value
        api_key = getpass.getpass('Azure OpenAI API key (hidden): ').strip()
        if not api_key or api_key == 'YOUR_AZURE_OPENAI_API_KEY':
            raise ValueError('An Azure OpenAI API key is required.')
        os.environ['AZURE_OPENAI_API_KEY'] = api_key
        validate_endpoint()
        for key in [*DEFAULTS, 'AZURE_OPENAI_API_KEY']:
            set_key(str(env_file), key, os.environ[key], quote_mode='always')
    validate_endpoint()


def validate_endpoint() -> None:
    endpoint = urlparse(os.environ['AZURE_OPENAI_ENDPOINT'])
    if endpoint.scheme != 'https' or not endpoint.hostname or endpoint.username or endpoint.password or endpoint.query or endpoint.fragment:
        raise ValueError('AZURE_OPENAI_ENDPOINT must be an HTTPS resource endpoint.')
    if not os.environ['AZURE_OPENAI_DEPLOYMENT'].strip():
        raise ValueError('AZURE_OPENAI_DEPLOYMENT is required.')


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check-config', action='store_true')
    parser.add_argument('--port', type=int, default=8765)
    args = parser.parse_args()
    try:
        configure(interactive=not args.check_config)
    except (ValueError, EOFError, KeyboardInterrupt) as exc:
        parser.exit(1, f'Configuration incomplete: {exc}\n')
    if args.check_config:
        print('Configuration is present. No Azure CLI required; credentials are not displayed.')
        return
    import uvicorn
    print(f'Open http://127.0.0.1:{args.port}, allow the camera, and click Verify.')
    print('Keep this window open. Press Ctrl+C to stop.')
    uvicorn.run('app:app', host='127.0.0.1', port=args.port, app_dir=str(ROOT))


if __name__ == '__main__':
    main()
