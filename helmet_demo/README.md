# RideGuardian Azure Vision Helmet Check

This laptop webcam demo uses the existing Azure OpenAI `guardian-vision-accurate`
GPT-4.1 deployment. It has no local YOLO model. A camera frame is uploaded only
when the user presses **Verify helmet with Azure Vision**; continuous video is
not uploaded.

## Run on Windows (no Azure CLI)

Install Python 3.11, then run from the repository folder:

```powershell
.\helmet_demo\setup.ps1
.\helmet_demo\run.ps1
```

Open `http://127.0.0.1:8765`, allow camera access, and press Verify. Keep the
terminal open while using the page. Each verification is a metered Azure AI
request.

On the first run, the launcher asks for the Azure endpoint, deployment name and
API key. Press Enter to keep the existing RideGuardian endpoint and deployment.
The key is entered with hidden input and saved in `helmet_demo/.env`, which Git
ignores. Subsequent runs load that file automatically. No Azure CLI or `az login`
is needed. The Python environment is created inside `helmet_demo/.venv`.

Alternatively, copy `helmet_demo/.env.example` to `helmet_demo/.env` and replace
`YOUR_AZURE_OPENAI_API_KEY` with your actual Azure OpenAI key. Endpoint, deployment
and key must belong to the same Azure resource. Existing environment variables
take precedence over `.env` values. You can obtain the key from the Azure portal's
resource **Keys and Endpoint** page; do not put it in the webpage or commit it.

Each other PC needs Python and its own local configuration, but can use the same
authorized Azure resource. Internet access and Azure credits are still required.

To check configuration without starting the server or showing credentials:

```powershell
.\helmet_demo\.venv\Scripts\python.exe .\helmet_demo\launch.py --check-config
```

For macOS/Linux, create a Python virtual environment, install `requirements.txt`,
then run `python helmet_demo/launch.py`. The Python launcher uses the same `.env`.
