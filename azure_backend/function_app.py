from __future__ import annotations

import base64
import json
import hashlib
import logging
import re
import math
import os
import time
import uuid
from datetime import datetime, timezone

import azure.functions as func
import jwt
import requests
from azure.cosmos import CosmosClient
from azure.cosmos.exceptions import CosmosResourceNotFoundError
from google.oauth2 import service_account
from google.auth.transport.requests import Request as GoogleAuthRequest


app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)
FIREBASE_PROJECT_ID = os.getenv("FIREBASE_PROJECT_ID", "rideguardian-ai-617db5")
FIREBASE_ISSUER = f"https://securetoken.google.com/{FIREBASE_PROJECT_ID}"
FIREBASE_JWKS = (
    "https://www.googleapis.com/service_accounts/v1/jwk/"
    "securetoken@system.gserviceaccount.com"
)
_jwk_client = jwt.PyJWKClient(FIREBASE_JWKS, cache_keys=True)
_container = None
_push_credentials = None


def container():
    global _container
    if _container is None:
        client = CosmosClient.from_connection_string(os.environ["COSMOS_CONNECTION"])
        _container = client.get_database_client(
            os.getenv("COSMOS_DATABASE", "rideguardian")
        ).get_container_client(os.getenv("COSMOS_CONTAINER", "items"))
    return _container


def response(status: int, body: dict | list) -> func.HttpResponse:
    return func.HttpResponse(
        json.dumps(body, default=str),
        status_code=status,
        mimetype="application/json",
        headers={"cache-control": "no-store"},
    )


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def body_json(req: func.HttpRequest) -> dict:
    try:
        return req.get_json()
    except ValueError as exc:
        raise ValueError("A valid JSON body is required") from exc


def authenticated(req: func.HttpRequest):
    header = req.headers.get("authorization", "")
    if not header.startswith("Bearer "):
        return None, response(401, {"message": "Missing Firebase ID token"})
    token = header[7:].strip()
    try:
        key = _jwk_client.get_signing_key_from_jwt(token).key
        claims = jwt.decode(
            token,
            key,
            algorithms=["RS256"],
            audience=FIREBASE_PROJECT_ID,
            issuer=FIREBASE_ISSUER,
            options={"require": ["exp", "iat", "sub"]},
        )
        verified_email = claims.get("email") and claims.get("email_verified")
        verified_phone = claims.get("phone_number")
        if not (verified_email or verified_phone):
            return None, response(
                403, {"message": "Verify your email or phone number first"}
            )
        return claims, None
    except jwt.PyJWTError:
        return None, response(401, {"message": "Invalid or expired Firebase token"})


def protected(handler):
    def wrapped(req: func.HttpRequest):
        claims, error = authenticated(req)
        if error:
            return error
        try:
            return handler(req, claims)
        except (ValueError, KeyError) as exc:
            return response(400, {"message": str(exc)})
        except Exception:
            logging.exception('RideGuardian API request failed')
            return response(500, {"message": "The safety service could not complete the request"})

    wrapped.__name__ = handler.__name__
    wrapped.__qualname__ = handler.__qualname__
    return wrapped


def query_partition(pk: str, prefix: str) -> list[dict]:
    return list(
        container().query_items(
            query="SELECT * FROM c WHERE c.pk = @pk AND STARTSWITH(c.sk, @prefix)",
            parameters=[
                {"name": "@pk", "value": pk},
                {"name": "@prefix", "value": prefix},
            ],
            partition_key=pk,
        )
    )


def verified_contacts(claims):
    contacts = []
    if claims.get('email_verified') and claims.get('email'):
        contacts.append(claims['email'].strip().lower())
    if claims.get('phone_number'):
        contacts.append(claims['phone_number'])
    return contacts


def normalize_contact(value):
    value = str(value).strip().lower()
    if re.fullmatch(r'[^\s@]+@[^\s@]+\.[^\s@]+', value):
        return value
    value = re.sub(r'[\s()-]', '', value)
    if re.fullmatch(r'\+[1-9][0-9]{7,14}', value):
        return value
    raise ValueError('Enter an email or phone number with country code, such as +91.')


def read_optional(item_id, pk):
    try:
        return container().read_item(item_id, partition_key=pk)
    except CosmosResourceNotFoundError:
        return None


def can_watch(guardian_id, rider_id):
    return bool(read_optional(f'guardian:{guardian_id}', f'USER#{rider_id}'))


def active_requests(pk, prefix):
    return [r for r in query_partition(pk, prefix) if r.get('expiresAt', 0) > time.time()]


@app.route(route='riders/request', methods=['POST'])
@protected
def request_rider(req, claims):
    contact = normalize_contact(str(body_json(req).get('contact', '')))
    if not contact.startswith('+'):
        raise ValueError('Enter the rider phone number with country code, such as +91.')
    if contact in verified_contacts(claims):
        raise ValueError('Enter the rider number, not your own number.')
    guardian_id = claims['sub']
    pk = f'USER#{guardian_id}'
    pending_id = f'request:{contact}'
    existing = read_optional(pending_id, pk)
    if existing and existing.get('expiresAt', 0) > time.time():
        return response(202, {'requested': True})
    if len(active_requests(pk, 'REQUEST#')) >= 10:
        return response(429, {'message': 'You have 10 pending requests. Cancel one before adding another.'})
    item = {'id': f'request:{guardian_id}', 'pk': f'REQUEST#{contact}', 'sk': f'GUARDIAN#{guardian_id}',
        'guardianId': guardian_id, 'guardianContact': verified_contacts(claims)[0],
        'contact': contact, 'createdAt': utc_now(), 'expiresAt': int(time.time()) + 7 * 86400}
    container().upsert_item(item)
    container().upsert_item({**item, 'id': pending_id, 'pk': pk, 'sk': f'REQUEST#{contact}'})
    recipient = read_optional('profile', f'CONTACT#{contact}')
    if recipient and recipient['userId'] != guardian_id:
        queue_notice(recipient['userId'], 'CONNECTION_REQUEST', recipient['userId'], f'request-{guardian_id}-{int(time.time())}')
    # The response does not reveal whether the number has an account.
    return response(202, {'requested': True})


@app.route(route='riders/requests', methods=['GET'])
@protected
def pending_rider_requests(_req, claims):
    return response(200, {'items': active_requests(f"USER#{claims['sub']}", 'REQUEST#')})


@app.route(route='riders/request/cancel', methods=['POST'])
@protected
def cancel_rider_request(req, claims):
    contact = normalize_contact(str(body_json(req).get('contact', '')))
    for item_id, pk in [(f"request:{claims['sub']}", f'REQUEST#{contact}'), (f'request:{contact}', f"USER#{claims['sub']}")]:
        if read_optional(item_id, pk):
            container().delete_item(item_id, partition_key=pk)
    return response(200, {'cancelled': True})


@app.route(route='guardian-requests', methods=['GET'])
@protected
def guardian_requests(_req, claims):
    items = []
    for contact in verified_contacts(claims):
        items.extend(active_requests(f'REQUEST#{contact}', 'GUARDIAN#'))
    return response(200, {'items': items})


@app.route(route='guardian-requests/respond', methods=['POST'])
@protected
def respond_guardian_request(req, claims):
    payload = body_json(req)
    guardian_id = str(payload.get('guardianId', ''))
    action = payload.get('action')
    if action not in ('accept', 'decline'):
        raise ValueError('Choose accept or decline.')
    invitation = None
    for contact in verified_contacts(claims):
        candidate = read_optional(f'request:{guardian_id}', f'REQUEST#{contact}')
        if candidate and candidate.get('expiresAt', 0) > time.time():
            invitation = candidate
            break
    if not invitation or guardian_id == claims['sub']:
        return response(404, {'message': 'Connection request not found or expired.'})
    rider_id = claims['sub']
    if action == 'accept':
        container().upsert_item({'id': f'guardian:{guardian_id}', 'pk': f'USER#{rider_id}',
            'sk': f'GUARDIAN#{guardian_id}', 'userId': guardian_id,
            'email': invitation['guardianContact'], 'createdAt': utc_now()})
        container().upsert_item({'id': f'rider:{rider_id}', 'pk': f'USER#{guardian_id}',
            'sk': f'RIDER#{rider_id}', 'userId': rider_id, 'email': invitation['contact'], 'createdAt': utc_now()})
        queue_notice(guardian_id, 'CONNECTION_ACCEPTED', rider_id, f'connected-{rider_id}-{guardian_id}-{int(time.time())}')
    container().delete_item(invitation['id'], partition_key=invitation['pk'])
    pending_id = f"request:{invitation['contact']}"
    if read_optional(pending_id, f'USER#{guardian_id}'):
        container().delete_item(pending_id, partition_key=f'USER#{guardian_id}')
    return response(200, {'accepted': action == 'accept'})


@app.route(route='rider-rides', methods=['GET'])
@protected
def rider_rides(req, claims):
    rider_id = str(req.params.get('riderId', ''))
    if not can_watch(claims['sub'], rider_id):
        return response(403, {'message': 'This rider has not shared access.'})
    rides = query_partition(f'USER#{rider_id}', 'RIDE#')
    rides.sort(key=lambda r: r.get('startedAt', ''), reverse=True)
    keys = ('id', 'rideId', 'startedAt', 'durationSeconds', 'distanceKm', 'maxSpeedKph', 'safetyScore')
    return response(200, {'items': [{**{k: r[k] for k in keys if k in r}, 'eventCount': len(r.get('events', []))} for r in rides[:50]]})


def validate_coordinates(lat, lng):
    lat, lng = float(lat), float(lng)
    if not math.isfinite(lat) or not math.isfinite(lng) or not (-90 <= lat <= 90 and -180 <= lng <= 180):
        raise ValueError('Invalid location coordinates')
    return lat, lng


def queue_notice(user_id, kind, rider_id, event_id):
    notice_id = hashlib.sha256(f'{user_id}:{kind}:{event_id}'.encode()).hexdigest()
    pk = 'NOTIFICATIONS'
    if not read_optional(notice_id, pk):
        container().upsert_item({
            'id': notice_id, 'pk': pk, 'sk': f'NOTICE#{notice_id}',
            'userId': user_id, 'kind': kind, 'riderId': rider_id,
            'eventId': event_id, 'status': 'pending', 'attempts': 0,
            'createdAt': utc_now(), 'ttl': 86400,
        })


def send_notice(notice):
    global _push_credentials
    if notice['kind'] == 'SOS' and not can_watch(notice['userId'], notice['riderId']):
        notice['status'] = 'revoked'
        container().upsert_item(notice)
        return
    devices = list(container().query_items(
        query='SELECT * FROM c WHERE c.entityType = @type AND c.userId = @uid',
        parameters=[{'name': '@type', 'value': 'DEVICE'}, {'name': '@uid', 'value': notice['userId']}],
        enable_cross_partition_query=True,
    ))
    if not devices:
        notice['status'] = 'no_registered_device'
    else:
        if _push_credentials is None:
            _push_credentials = service_account.Credentials.from_service_account_info(
                json.loads(os.environ['FIREBASE_MESSAGING_CREDENTIALS']),
                scopes=['https://www.googleapis.com/auth/firebase.messaging'],
            )
        if not _push_credentials.valid:
            _push_credentials.refresh(GoogleAuthRequest())
        accepted = set(notice.get('acceptedDevices', []))
        failed = False
        for device in devices:
            if device['id'] in accepted:
                continue
            result = requests.post(
                f'https://fcm.googleapis.com/v1/projects/{FIREBASE_PROJECT_ID}/messages:send',
                headers={'Authorization': f'Bearer {_push_credentials.token}'},
                json={'message': {
                    'token': device['token'],
                    'notification': {
                        'title': 'RideGuardian SOS' if notice['kind'] == 'SOS' else 'RideGuardian connection',
                        'body': {'SOS': 'A rider needs help. Open their dashboard for the alert.',
                            'CONNECTION_REQUEST': 'A guardian wants to connect. Review the request in Family.',
                            'CONNECTION_ACCEPTED': 'Your rider accepted. Open your guardian dashboard.'}.get(notice['kind'], 'You have a new invitation. Open Family to review it.'),
                    },
                    'data': {'kind': notice['kind'], 'riderId': notice['riderId'], 'eventId': notice['eventId']},
                    'android': {'priority': 'HIGH', 'ttl': '3600s', 'notification': {
                        'channel_id': 'guardian_alerts', 'sound': 'default', 'tag': notice['eventId'],
                    }},
                }}, timeout=10,
            )
            if result.ok:
                accepted.add(device['id'])
            elif result.status_code == 404:
                container().delete_item(device['id'], partition_key=device['pk'])
            else:
                failed = True
                logging.warning('FCM request failed with HTTP %s', result.status_code)
        notice['acceptedDevices'] = list(accepted)
        notice['status'] = 'pending' if failed else ('accepted_by_fcm' if accepted else 'no_registered_device')
    notice['attempts'] += 1
    notice['updatedAt'] = utc_now()
    container().upsert_item(notice)


@app.timer_trigger(schedule='*/10 * * * * *', arg_name='timer', run_on_startup=False)
def deliver_notifications(timer: func.TimerRequest):
    pending = container().query_items(
        query="SELECT TOP 25 * FROM c WHERE c.pk = @pk AND c.status = 'pending' AND c.attempts < 10",
        parameters=[{'name': '@pk', 'value': 'NOTIFICATIONS'}],
        partition_key='NOTIFICATIONS',
    )
    for notice in pending:
        if notice.get('status') != 'pending' or notice.get('attempts', 0) >= 10:
            continue
        try:
            send_notice(notice)
        except Exception:
            logging.exception('Notification delivery will retry')
            notice['attempts'] += 1
            container().upsert_item(notice)


@app.route(route='devices', methods=['POST', 'DELETE'])
@protected
def register_device(req, claims):
    token = str(body_json(req).get('token', ''))
    if len(token) < 20 or len(token) > 4096:
        raise ValueError('Invalid notification token')
    digest = hashlib.sha256(token.encode()).hexdigest()
    pk = f'DEVICE#{digest}'
    if req.method == 'DELETE':
        existing = read_optional(digest, pk)
        if existing and existing['userId'] == claims['sub']:
            container().delete_item(digest, partition_key=pk)
    else:
        container().upsert_item({'id': digest, 'pk': pk, 'entityType': 'DEVICE',
            'userId': claims['sub'], 'token': token, 'updatedAt': utc_now()})
        for contact in verified_contacts(claims):
            container().upsert_item({'id': 'profile', 'pk': f'CONTACT#{contact}',
                'userId': claims['sub'], 'updatedAt': utc_now()})
    return response(200, {'registered': req.method == 'POST'})


@app.route(route="health", methods=["GET"])
def health(req: func.HttpRequest):
    return response(
        200,
        {
            "status": "ok",
            "service": "rideguardian-azure",
            "identity": "firebase",
            "database": "cosmos-serverless",
        },
    )


@app.route(route="location", methods=["POST"])
@protected
def save_location(req, claims):
    payload = body_json(req)
    user_id = claims["sub"]
    lat, lng = validate_coordinates(payload['latitude'], payload['longitude'])
    state = payload.get('status', 'RIDING')
    if state not in ('RIDING', 'SAFE'):
        raise ValueError('Unsupported ride status')
    previous = read_optional('live', f'USER#{user_id}')
    # A delayed heartbeat must not overwrite a newer stopped-ride update.
    recorded_at = payload.get('recordedAt', utc_now())
    if previous and recorded_at < previous.get('recordedAt', ''):
        return response(202, {'accepted': False, 'reason': 'Older update ignored'})
    item = {
        "id": "live",
        "pk": f"USER#{user_id}",
        "sk": "LIVE",
        "latitude": lat,
        "longitude": lng,
        "speedKph": max(0, float(payload.get("speedKph", 0))) if state == 'RIDING' else 0,
        "safetyScore": payload.get("safetyScore", 100),
        "status": state,
        "riderName": claims.get("email") or claims.get("phone_number", "Rider"),
        "updatedAt": utc_now(),
        "recordedAt": recorded_at,
        "ttl": 86400,
    }
    container().upsert_item(item)
    return response(202, {"accepted": True})


@app.route(route="rides", methods=["GET", "POST"])
@protected
def rides(req, claims):
    user_id = claims["sub"]
    pk = f"USER#{user_id}"
    if req.method == "GET":
        items = query_partition(pk, "RIDE#")
        items.sort(key=lambda item: item.get("startedAt", ""), reverse=True)
        return response(200, {"items": items[:50]})
    payload = body_json(req)
    ride_id = str(payload.get("id") or f"ride-{int(time.time())}")
    item = {
        "id": f"ride:{ride_id}",
        "pk": pk,
        "sk": f"RIDE#{payload.get('startedAt', utc_now())}#{ride_id}",
        "entityType": "RIDE",
        "rideId": ride_id,
        "startedAt": payload.get("startedAt", utc_now()),
        "durationSeconds": payload.get("durationSeconds", 0),
        "distanceKm": payload.get("distanceKm", 0),
        "maxSpeedKph": payload.get("maxSpeedKph", 0),
        "safetyScore": payload.get("safetyScore", 100),
        "events": payload.get("events", []),
        "points": payload.get("points", []),
        "createdAt": utc_now(),
    }
    container().upsert_item(item)
    return response(201, {"id": ride_id})


@app.route(route="emergency", methods=["POST"])
@protected
def emergency(req, claims):
    payload = body_json(req)
    user_id = claims["sub"]
    alert_id = str(payload.get('requestId') or uuid.uuid4())
    if not re.fullmatch(r'[a-zA-Z0-9_-]{1,100}', alert_id):
        raise ValueError('Invalid emergency request ID')
    existing = read_optional(f'alert:{alert_id}', f'USER#{user_id}')
    lat, lng = payload.get('latitude'), payload.get('longitude')
    if lat is not None and lng is not None:
        lat, lng = validate_coordinates(lat, lng)
    else:
        live = read_optional('live', f'USER#{user_id}') or {}
        lat, lng = live.get('latitude'), live.get('longitude')
    item = {
        "id": f"alert:{alert_id}",
        "pk": f"USER#{user_id}",
        "sk": f"ALERT#{utc_now()}#{alert_id}",
        "type": "RIDE_EMERGENCY",
        "riderId": user_id,
        "reason": payload.get("reason", "Emergency alert"),
        "latitude": lat,
        "longitude": lng,
        "timestamp": utc_now(),
        "riderName": (verified_contacts(claims) or ['Rider'])[0],
    }
    if not existing:
        container().upsert_item(item)
    connections = query_partition(f'USER#{user_id}', 'GUARDIAN#')
    for guardian in connections:
        queue_notice(guardian['userId'], 'SOS', user_id, alert_id)
    return response(202, {'saved': True, 'alertId': alert_id,
        'guardians': len(connections), 'notificationStatus': 'queued' if connections else 'no_guardians'})


@app.route(route="helmet-check", methods=["POST"])
@protected
def helmet_check(req, _claims):
    image = req.get_body()
    if not image or len(image) > 5_000_000:
        raise ValueError("A JPEG image smaller than 5 MB is required")
    api_key = os.environ["AZURE_OPENAI_API_KEY"]
    endpoint = os.environ["AZURE_OPENAI_ENDPOINT"].rstrip("/")
    deployment = os.getenv("AZURE_OPENAI_DEPLOYMENT", "guardian-vision-accurate")
    encoded = base64.b64encode(image).decode("ascii")
    payload = {
        "messages": [
            {
                "role": "system",
                "content": (
                    "Inspect only the main visible person's head. Return JSON with "
                    "helmet_present (boolean), worn_on_head (boolean), confidence (number from 0 to 1), "
                    "strap_status (fastened, unfastened, or not_visible), and reason (short explanation). "
                    "Detect a motorcycle helmet positioned on the main person's head. Open-face, "
                    "half-face and full-face motorcycle helmets count, with visor raised or lowered. "
                    "A helmet held in a hand, a cap, headphones, a bicycle helmet or a construction hardhat does not count. "
                    "Judge worn_on_head separately from the chin strap. Do not infer an unfastened strap "
                    "when it is obscured; use not_visible. Do not claim the helmet's fit or safety is certified."
                ),
            },
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": "Is the main person wearing a motorcycle helmet on their head? Report strap visibility separately."},
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
        "max_tokens": 280,
        "response_format": {"type": "json_object"},
    }
    result = requests.post(
        f"{endpoint}/openai/deployments/{deployment}/chat/completions",
        params={"api-version": "2024-10-21"},
        headers={"api-key": api_key, "content-type": "application/json"},
        json=payload,
        timeout=60,
    )
    result.raise_for_status()
    verdict = json.loads(result.json()["choices"][0]["message"]["content"])
    # Never interpret strings such as "false" as a positive detection.
    confidence = verdict.get("confidence")
    if isinstance(confidence, bool) or not isinstance(confidence, (int, float)) or not 0 <= confidence <= 1:
        return response(502, {'message': 'Vision returned an invalid result. Please retake the photo.'})
    passed = verdict.get("helmet_present") is True and verdict.get("worn_on_head") is True and confidence >= 0.8
    confidence *= 100
    return response(
        200,
        {
            "detected": passed,
            "confidence": confidence,
            "strapStatus": verdict.get("strap_status", "not_visible"),
            "reason": verdict.get("reason", ""),
            "source": "azure-gpt-4.1",
        },
    )


@app.route(route="nearby-hospitals", methods=["GET"])
@protected
def nearby_hospitals(req, _claims):
    api_key = os.getenv("GOOGLE_MAPS_API_KEY")
    if not api_key:
        return response(503, {"message": "Google Maps billing/key is not configured", "items": []})
    lat, lng = validate_coordinates(req.params['lat'], req.params['lng'])
    result = requests.post(
        "https://places.googleapis.com/v1/places:searchNearby",
        headers={
            "X-Goog-Api-Key": api_key,
            "X-Goog-FieldMask": "places.displayName,places.location,places.nationalPhoneNumber,places.primaryType",
            "content-type": "application/json",
        },
        json={
            "includedPrimaryTypes": ["hospital"],
            "maxResultCount": 20,
            "rankPreference": "DISTANCE",
            "locationRestriction": {
                "circle": {"center": {"latitude": lat, "longitude": lng}, "radius": 10000}
            },
        },
        timeout=15,
    )
    result.raise_for_status()
    items = []
    for place in result.json().get("places", []):
        # Google's hospital search can also include medical_center subtypes,
        # including chemists. Only show places classified as hospitals.
        if place.get("primaryType") != "hospital":
            continue
        location = place.get("location", {})
        place_lat = float(location.get("latitude", 0))
        place_lng = float(location.get("longitude", 0))
        items.append(
            {
                "name": place.get("displayName", {}).get("text", "Hospital"),
                "distanceKm": round(haversine_km(lat, lng, place_lat, place_lng), 2),
                "latitude": place_lat,
                "longitude": place_lng,
                "phone": place.get("nationalPhoneNumber"),
            }
        )
    return response(200, {"items": items[:10]})


@app.route(route="route", methods=["GET"])
@protected
def calculate_route(req, _claims):
    api_key = os.getenv("GOOGLE_MAPS_API_KEY")
    if not api_key:
        return response(503, {"message": "Google Maps billing/key is not configured"})
    origin = {
        "latitude": float(req.params["originLat"]),
        "longitude": float(req.params["originLng"]),
    }
    destination = {
        "latitude": float(req.params["destinationLat"]),
        "longitude": float(req.params["destinationLng"]),
    }
    result = requests.post(
        "https://routes.googleapis.com/directions/v2:computeRoutes",
        headers={
            "X-Goog-Api-Key": api_key,
            "X-Goog-FieldMask": "routes.distanceMeters,routes.duration",
            "content-type": "application/json",
        },
        json={
            "origin": {"location": {"latLng": origin}},
            "destination": {"location": {"latLng": destination}},
            "travelMode": "TWO_WHEELER",
            "routingPreference": "TRAFFIC_AWARE",
        },
        timeout=20,
    )
    result.raise_for_status()
    routes = []
    for route in result.json().get("routes", []):
        duration = str(route.get("duration", "0s")).removesuffix("s")
        routes.append(
            {
                "Summary": {
                    "Distance": route.get("distanceMeters", 0),
                    "Duration": float(duration or 0),
                }
            }
        )
    return response(200, {"Routes": routes})


@app.route(route="guardians", methods=["GET"])
@protected
def guardians(_req, claims):
    return response(200, {"items": query_partition(f"USER#{claims['sub']}", "GUARDIAN#")})


@app.route(route="guardians/invite", methods=["POST"])
@protected
def invite_guardian(req, claims):
    payload = body_json(req)
    email = normalize_contact(payload.get('contact', payload.get('email', '')))
    own_email = verified_contacts(claims)[0]
    if email in verified_contacts(claims):
        raise ValueError("You cannot invite your own account")
    rider_id = claims["sub"]
    container().upsert_item(
        {
            "id": f"invite:{rider_id}",
            "pk": f"INVITE#{email}",
            "sk": f"RIDER#{rider_id}",
            "riderId": rider_id,
            "riderEmail": own_email,
            "createdAt": utc_now(),
        }
    )
    recipient = read_optional('profile', f'CONTACT#{email}')
    if recipient and recipient['userId'] != rider_id:
        queue_notice(recipient['userId'], 'INVITATION', rider_id, f'invite-{rider_id}-{int(time.time())}')
    return response(201, {"invited": True})


@app.route(route="guardians/invitations", methods=["GET"])
@protected
def invitations(_req, claims):
    items = []
    for contact in verified_contacts(claims):
        items.extend(query_partition(f'INVITE#{contact}', 'RIDER#'))
    return response(200, {"items": items})


@app.route(route="guardians/accept", methods=["POST"])
@protected
def accept_invitation(req, claims):
    guardian_id = claims["sub"]
    rider_id = str(body_json(req).get("riderId", ""))
    invite_id = f"invite:{rider_id}"
    invitation = None
    for email in verified_contacts(claims):
        invite_pk = f'INVITE#{email}'
        invitation = read_optional(invite_id, invite_pk)
        if invitation:
            break
    if not invitation or rider_id == guardian_id:
        return response(404, {"message": "Invitation not found"})
    now = utc_now()
    container().upsert_item(
        {
            "id": f"guardian:{guardian_id}",
            "pk": f"USER#{rider_id}",
            "sk": f"GUARDIAN#{guardian_id}",
            "userId": guardian_id,
            "email": email,
            "createdAt": now,
        }
    )
    container().upsert_item(
        {
            "id": f"rider:{rider_id}",
            "pk": f"USER#{guardian_id}",
            "sk": f"RIDER#{rider_id}",
            "userId": rider_id,
            "email": invitation.get("riderEmail", "Rider"),
            "createdAt": now,
        }
    )
    container().delete_item(invite_id, partition_key=invite_pk)
    return response(200, {"accepted": True})


@app.route(route="shared-riders", methods=["GET"])
@protected
def shared_riders(_req, claims):
    return response(200, {"items": query_partition(f"USER#{claims['sub']}", "RIDER#")})


@app.route(route="rider-status", methods=["GET"])
@protected
def rider_status(req, claims):
    guardian_id = claims["sub"]
    rider_id = str(req.params.get("riderId", ""))
    if not can_watch(guardian_id, rider_id):
        return response(403, {"message": "This rider has not shared access"})
    live = read_optional('live', f'USER#{rider_id}')
    if live and live.get('status') == 'RIDING':
        age = (datetime.now(timezone.utc) - datetime.fromisoformat(live['updatedAt'].replace('Z', '+00:00'))).total_seconds()
        gps_age = (datetime.now(timezone.utc) - datetime.fromisoformat(live.get('recordedAt', live['updatedAt']).replace('Z', '+00:00'))).total_seconds()
        if age > 60 or gps_age > 60:
            live['status'] = 'OFFLINE'
            live['speedKph'] = 0
    return response(200, {"status": live})


@app.route(route='guardians/remove', methods=['POST'])
@protected
def remove_guardian(req, claims):
    guardian_id = str(body_json(req).get('guardianId', ''))
    rider_id = claims['sub']
    for item_id, pk in [(f'guardian:{guardian_id}', f'USER#{rider_id}'),
                        (f'rider:{rider_id}', f'USER#{guardian_id}')]:
        if read_optional(item_id, pk):
            container().delete_item(item_id, partition_key=pk)
    return response(200, {'removed': True})


@app.route(route="alerts", methods=["GET"])
@protected
def alerts(_req, claims):
    connections = query_partition(f"USER#{claims['sub']}", "RIDER#")
    items = []
    for connection in connections:
        if can_watch(claims['sub'], connection['userId']):
            items.extend(query_partition(f"USER#{connection.get('userId')}", "ALERT#"))
    items.sort(key=lambda item: item.get("timestamp", ""), reverse=True)
    return response(200, {"items": items[:25]})


def haversine_km(lat1, lon1, lat2, lon2):
    radius = 6371.0
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    value = (
        math.sin(dlat / 2) ** 2
        + math.cos(math.radians(lat1))
        * math.cos(math.radians(lat2))
        * math.sin(dlon / 2) ** 2
    )
    return radius * 2 * math.atan2(math.sqrt(value), math.sqrt(1 - value))
