# RideGuardian Azure Vision Helmet Check

This laptop webcam demo uses the existing Azure OpenAI `guardian-vision-accurate`
GPT-4.1 deployment. It has no local YOLO model. A camera frame is uploaded only
when the user presses **Verify helmet with Azure Vision**; continuous video is
not uploaded.

## Run

```powershell
.\helmet_demo\setup.ps1
.\helmet_demo\run.ps1
```

Open `http://127.0.0.1:8765`, allow camera access, and press Verify. Keep the
terminal open while using the page. Each verification is a metered Azure AI
request.

The launcher retrieves the API key for `guardian-ai-openai-617db5` through the
currently signed-in Azure CLI session and keeps it only in process memory.
