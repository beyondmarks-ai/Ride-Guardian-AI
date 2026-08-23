import base64
import json
import math
import os
from datetime import datetime, timezone
from decimal import Decimal

import boto3


TABLE = boto3.resource("dynamodb").Table(os.environ["TABLE_NAME"])
SNS = boto3.client("sns")
REKOGNITION = boto3.client("rekognition")
PLACES = boto3.client("geo-places")
ROUTES = boto3.client("geo-routes")
TOPIC_ARN = os.environ["EMERGENCY_TOPIC_ARN"]


def handler(event, _context):
    context = event.get("requestContext", {})
    method = context.get("http", {}).get("method", "GET")
    path = event.get("rawPath", "/")
    stage = context.get("stage")
    if stage and path.startswith(f"/{stage}/"):
        path = path[len(stage) + 1 :]
    if path == "/health":
        return response(200, {"status": "ok", "service": "rideguardian"})

    claims = context.get("authorizer", {}).get("jwt", {}).get("claims", {})
    user_id = claims.get("sub")
    if not user_id:
        return response(401, {"message": "Unauthorized"})
    try:
        routes = {
            ("POST", "/location"): lambda: save_location(user_id, claims, json_body(event)),
            ("POST", "/rides"): lambda: save_ride(user_id, json_body(event)),
            ("GET", "/rides"): lambda: list_rides(user_id),
            ("POST", "/emergency"): lambda: emergency(user_id, json_body(event)),
            ("POST", "/helmet-check"): lambda: helmet_check(event),
            ("GET", "/nearby-hospitals"): lambda: hospitals(event.get("queryStringParameters") or {}),
            ("GET", "/route"): lambda: calculate_route(event.get("queryStringParameters") or {}),
            ("GET", "/guardians"): lambda: list_connections(user_id, "GUARDIAN#"),
            ("POST", "/guardians/invite"): lambda: invite_guardian(user_id, claims, json_body(event)),
            ("GET", "/guardians/invitations"): lambda: list_invitations(claims),
            ("POST", "/guardians/accept"): lambda: accept_invitation(user_id, claims, json_body(event)),
            ("GET", "/shared-riders"): lambda: list_connections(user_id, "RIDER#"),
            ("GET", "/rider-status"): lambda: rider_status(user_id, event.get("queryStringParameters") or {}),
            ("GET", "/alerts"): lambda: guardian_alerts(user_id),
        }
        operation = routes.get((method, path))
        return operation() if operation else response(404, {"message": "Not found"})
    except (ValueError, KeyError) as error:
        return response(400, {"message": str(error)})
    except Exception:
        return response(500, {"message": "The safety service could not complete the request"})


def save_location(user_id, claims, payload):
    item = decimalize({
        "pk": f"USER#{user_id}",
        "sk": "LIVE",
        "latitude": required_number(payload, "latitude"),
        "longitude": required_number(payload, "longitude"),
        "speedKph": payload.get("speedKph", 0),
        "safetyScore": payload.get("safetyScore", 100),
        "status": payload.get("status", "RIDING"),
        "riderName": claims.get("email", "Rider"),
        "updatedAt": payload.get("recordedAt", utc_now()),
        "ttl": int(datetime.now(timezone.utc).timestamp()) + 86400,
    })
    TABLE.put_item(Item=item)
    return response(202, {"accepted": True})


def save_ride(user_id, payload):
    ride_id = str(payload.get("id") or f"ride-{int(datetime.now(timezone.utc).timestamp())}")
    TABLE.put_item(Item=decimalize({
        "pk": f"USER#{user_id}",
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
    }))
    return response(201, {"id": ride_id})


def list_rides(user_id):
    result = TABLE.query(
        KeyConditionExpression="pk = :pk AND begins_with(sk, :prefix)",
        ExpressionAttributeValues={":pk": f"USER#{user_id}", ":prefix": "RIDE#"},
        ScanIndexForward=False,
        Limit=50,
    )
    return response(200, {"items": result.get("Items", [])})


def emergency(user_id, payload):
    alert = {
        "type": "RIDE_EMERGENCY",
        "riderId": user_id,
        "reason": payload.get("reason", "Emergency alert"),
        "latitude": payload.get("latitude"),
        "longitude": payload.get("longitude"),
        "timestamp": payload.get("timestamp", utc_now()),
    }
    SNS.publish(TopicArn=TOPIC_ARN, Subject="RideGuardian emergency alert", Message=json.dumps(alert))
    TABLE.put_item(Item=decimalize({"pk": f"USER#{user_id}", "sk": f"ALERT#{utc_now()}", **alert}))
    return response(202, {"alerted": True})


def helmet_check(event):
    raw = event.get("body") or ""
    image = base64.b64decode(raw) if event.get("isBase64Encoded") else raw.encode("latin1")
    if not image or len(image) > 5_000_000:
        raise ValueError("A JPEG image smaller than 5 MB is required")
    result = REKOGNITION.detect_protective_equipment(
        Image={"Bytes": image},
        SummarizationAttributes={"MinConfidence": 50, "RequiredEquipmentTypes": ["HEAD_COVER"]},
    )
    scores = []
    for person in result.get("Persons", []):
        for body_part in person.get("BodyParts", []):
            for detection in body_part.get("EquipmentDetections", []):
                covered = detection.get("CoversBodyPart", {}).get("Value")
                if detection.get("Type") == "HEAD_COVER" and covered:
                    scores.append(float(detection.get("Confidence", 0)))
    confidence = max(scores, default=0.0)
    return response(200, {"detected": confidence >= 80, "confidence": confidence})


def hospitals(query):
    lat, lng = float(query["lat"]), float(query["lng"])
    result = PLACES.search_nearby(
        QueryPosition=[lng, lat],
        QueryRadius=10000,
        MaxResults=10,
        Filter={"IncludeCategories": ["hospital"]},
    )
    items = []
    for place in result.get("ResultItems", []):
        position = place.get("Position", [0, 0])
        meters = place.get("Distance")
        if meters is None:
            meters = haversine_km(lat, lng, position[1], position[0]) * 1000
        items.append({
            "name": place.get("Title", "Hospital"),
            "distanceKm": round(float(meters) / 1000, 2),
            "latitude": position[1],
            "longitude": position[0],
        })
    return response(200, {"items": items})


def calculate_route(query):
    result = ROUTES.calculate_routes(
        Origin=[float(query["originLng"]), float(query["originLat"])],
        Destination=[float(query["destinationLng"]), float(query["destinationLat"])],
        TravelMode="Scooter",
        TravelStepType="TurnByTurn",
    )
    result.pop("ResponseMetadata", None)
    return response(200, result)


def invite_guardian(user_id, claims, payload):
    email = str(payload.get("email", "")).strip().lower()
    own_email = str(claims.get("email", "")).lower()
    if "@" not in email:
        raise ValueError("A valid guardian email is required")
    if email == own_email:
        raise ValueError("You cannot invite your own account")
    TABLE.put_item(Item={
        "pk": f"INVITE#{email}",
        "sk": f"RIDER#{user_id}",
        "riderId": user_id,
        "riderEmail": own_email,
        "createdAt": utc_now(),
    })
    return response(201, {"invited": True})


def list_invitations(claims):
    email = str(claims.get("email", "")).lower()
    if not email:
        return response(200, {"items": []})
    result = TABLE.query(
        KeyConditionExpression="pk = :pk AND begins_with(sk, :prefix)",
        ExpressionAttributeValues={":pk": f"INVITE#{email}", ":prefix": "RIDER#"},
    )
    return response(200, {"items": result.get("Items", [])})


def accept_invitation(guardian_id, claims, payload):
    email = str(claims.get("email", "")).lower()
    rider_id = str(payload.get("riderId", ""))
    invite_key = {"pk": f"INVITE#{email}", "sk": f"RIDER#{rider_id}"}
    invitation = TABLE.get_item(Key=invite_key).get("Item")
    if not invitation:
        return response(404, {"message": "Invitation not found"})
    rider_email = invitation.get("riderEmail", "Rider")
    now = utc_now()
    TABLE.put_item(Item={
        "pk": f"USER#{rider_id}",
        "sk": f"GUARDIAN#{guardian_id}",
        "userId": guardian_id,
        "email": email,
        "createdAt": now,
    })
    TABLE.put_item(Item={
        "pk": f"USER#{guardian_id}",
        "sk": f"RIDER#{rider_id}",
        "userId": rider_id,
        "email": rider_email,
        "createdAt": now,
    })
    TABLE.delete_item(Key=invite_key)
    return response(200, {"accepted": True})


def list_connections(user_id, prefix):
    result = TABLE.query(
        KeyConditionExpression="pk = :pk AND begins_with(sk, :prefix)",
        ExpressionAttributeValues={":pk": f"USER#{user_id}", ":prefix": prefix},
    )
    return response(200, {"items": result.get("Items", [])})


def rider_status(guardian_id, query):
    rider_id = str(query.get("riderId", ""))
    permission = TABLE.get_item(
        Key={"pk": f"USER#{guardian_id}", "sk": f"RIDER#{rider_id}"}
    ).get("Item")
    if not permission:
        return response(403, {"message": "This rider has not shared access"})
    live = TABLE.get_item(Key={"pk": f"USER#{rider_id}", "sk": "LIVE"}).get("Item")
    return response(200, {"status": live})


def guardian_alerts(guardian_id):
    connections = TABLE.query(
        KeyConditionExpression="pk = :pk AND begins_with(sk, :prefix)",
        ExpressionAttributeValues={":pk": f"USER#{guardian_id}", ":prefix": "RIDER#"},
    ).get("Items", [])
    alerts = []
    for connection in connections:
        rider_id = connection.get("userId")
        result = TABLE.query(
            KeyConditionExpression="pk = :pk AND begins_with(sk, :prefix)",
            ExpressionAttributeValues={":pk": f"USER#{rider_id}", ":prefix": "ALERT#"},
            ScanIndexForward=False,
            Limit=10,
        )
        alerts.extend(result.get("Items", []))
    alerts.sort(key=lambda item: item.get("timestamp", ""), reverse=True)
    return response(200, {"items": alerts[:25]})


def json_body(event):
    raw = event.get("body") or "{}"
    if event.get("isBase64Encoded"):
        raw = base64.b64decode(raw).decode("utf-8")
    return json.loads(raw)


def required_number(payload, key):
    if key not in payload:
        raise ValueError(f"{key} is required")
    return float(payload[key])


def decimalize(value):
    return json.loads(json.dumps(value), parse_float=Decimal)


def response(status, body):
    return {
        "statusCode": status,
        "headers": {"content-type": "application/json", "cache-control": "no-store"},
        "body": json.dumps(body, default=json_default),
    }


def utc_now():
    return datetime.now(timezone.utc).isoformat()


def json_default(value):
    if isinstance(value, Decimal):
        return int(value) if value % 1 == 0 else float(value)
    return str(value)


def haversine_km(lat1, lon1, lat2, lon2):
    radius = 6371.0
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    value = math.sin(dlat / 2) ** 2 + math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) * math.sin(dlon / 2) ** 2
    return radius * 2 * math.atan2(math.sqrt(value), math.sqrt(1 - value))
