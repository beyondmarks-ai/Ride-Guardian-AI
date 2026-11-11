# RideGuardian Azure API

Python Azure Functions backend using Firebase ID tokens, Cosmos DB Serverless,
Azure GPT-4.1 Vision, and Google Places/Routes APIs.

The public `GET /api/health` route requires no token. Every other route verifies
a Firebase ID token issued by `rideguardian-ai-617db5` and requires a verified
email address or phone number. Invitations only match verified contacts.

Google hospital and route endpoints return `503` until a billed Google Maps
Platform API key is configured as `GOOGLE_MAPS_API_KEY`. Billing and live API
requests have been verified for the deployed project.

SOS records are idempotent by rider and request ID. Notifications are persisted
in Cosmos and a timer checks the outbox every 10 seconds. Failed FCM requests
retry up to 10 times. `accepted_by_fcm` indicates transport acceptance, not that
a person read an alert. Guardians can read the alert independently in Family.

`FIREBASE_MESSAGING_CREDENTIALS` is a JSON service account credential stored only
in Azure app settings. Its account has only the Firebase messaging role.
Use `tool/configure_push.ps1` for initial setup; never place this credential in
Flutter or commit it. Production deployments should rotate the key regularly.

Additional routes: `POST/DELETE /devices` (notification registration),
`POST /guardians/remove` (revokes status, alert and future push access).

Tests: `python -m unittest discover -s azure_backend -p test_flows.py -v`
from the repository root. `tool/test_hybrid_cloud.py` tests the deployed API
with temporary isolated identities and cleans them up by default.
