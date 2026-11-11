"""Live contract test using isolated Firebase accounts; never sends SMS.

--keep keeps only the test fixtures in ignored tmp/ for device testing.
--cleanup removes exactly the recorded test UIDs and their Cosmos fixtures.
"""
import argparse
import json
import pathlib
import secrets
import subprocess
import uuid
from datetime import datetime, timezone

import requests
from azure.cosmos import CosmosClient

ROOT = pathlib.Path(__file__).resolve().parents[1]
FIXTURE = ROOT / 'tmp' / 'hybrid-test-fixture.json'
PROJECT = 'rideguardian-ai-617db5'
BASE = 'https://rideguardian-api-617db5.azurewebsites.net/api'


def cli(*args):
    result = subprocess.run(args, check=True, capture_output=True, text=True, shell=True)
    return result.stdout.strip()


def admin_headers():
    return {'Authorization': 'Bearer ' + cli('gcloud', 'auth', 'print-access-token'),
            'x-goog-user-project': PROJECT}


def cleanup(fixture):
    headers = admin_headers()
    settings = json.loads(cli('az', 'functionapp', 'config', 'appsettings', 'list', '--name',
        'rideguardian-api-617db5', '--resource-group', 'guardian-ai-rg', '-o', 'json'))
    connection = next(x['value'] for x in settings if x['name'] == 'COSMOS_CONNECTION')
    db = CosmosClient.from_connection_string(connection).get_database_client('rideguardian').get_container_client('items')
    users = fixture['users']
    for user in users.values():
        uid = user['uid']
        parts = [f'USER#{uid}', f"INVITE#{user['email']}", f"CONTACT#{user['email']}"]
        if user.get('phone'):
            parts.extend([f"INVITE#{user['phone']}", f"CONTACT#{user['phone']}", f"REQUEST#{user['phone']}"])
        for pk in parts:
            for item in list(db.query_items('SELECT * FROM c WHERE c.pk = @pk',
                    parameters=[{'name': '@pk', 'value': pk}], partition_key=pk)):
                db.delete_item(item['id'], partition_key=pk)
        for item in list(db.query_items('SELECT * FROM c WHERE c.userId = @uid OR c.riderId = @uid OR c.guardianId = @uid',
                parameters=[{'name': '@uid', 'value': uid}], enable_cross_partition_query=True)):
            db.delete_item(item['id'], partition_key=item['pk'])
        result = requests.post(f'https://identitytoolkit.googleapis.com/v1/projects/{PROJECT}/accounts:delete',
            headers=headers, json={'localId': uid}, timeout=20)
        result.raise_for_status()
    FIXTURE.unlink(missing_ok=True)
    print('Removed isolated test accounts and their test records.')


def run(keep):
    if FIXTURE.exists():
        raise RuntimeError('A prior fixture exists. Use --cleanup before starting another test.')
    config = json.loads((ROOT / 'android/app/google-services.json').read_text())
    key = config['client'][0]['api_key'][0]['current_key']
    headers = admin_headers()
    fixture = {'users': {}}
    FIXTURE.parent.mkdir(exist_ok=True)
    def persist():
        FIXTURE.write_text(json.dumps(fixture), encoding='utf-8')
    def request(role, path, method='GET', body=None, expected=200):
        token = fixture['users'][role]['token'] if role else None
        result = requests.request(method, BASE + path,
            headers={'Authorization': f'Bearer {token}'} if token else {}, json=body, timeout=85)
        if result.status_code != expected:
            raise AssertionError(f'{method} {path.split("?")[0]}: expected {expected}, got {result.status_code}: {result.text[:250]}')
        return result.json()
    try:
        for role in ('rider', 'guardian', 'stranger'):
            email = f'rideguardian-test-{role}-{uuid.uuid4().hex[:12]}@example.com'
            password = secrets.token_urlsafe(24)
            result = requests.post(f'https://identitytoolkit.googleapis.com/v1/accounts:signUp?key={key}',
                json={'email': email, 'password': password, 'returnSecureToken': True}, timeout=20)
            result.raise_for_status()
            signed = result.json()
            user = {'uid': signed['localId'], 'email': email, 'password': password, 'token': signed['idToken']}
            fixture['users'][role] = user
            persist()
            request(role, '/rides', expected=403)
            updates = {'localId': user['uid'], 'emailVerified': role != 'rider'}
            if role == 'rider':
                # Reserved fictional number: no SMS is sent or used for sign-in.
                user['phone'] = '+16505550187'
                updates['phoneNumber'] = user['phone']
            result = requests.post(f'https://identitytoolkit.googleapis.com/v1/projects/{PROJECT}/accounts:update',
                headers=headers, json=updates, timeout=20)
            result.raise_for_status()
            result = requests.post(f'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key={key}',
                json={'email': email, 'password': password, 'returnSecureToken': True}, timeout=20)
            result.raise_for_status()
            user['token'] = result.json()['idToken']
            persist()
        print('PASS verified email + verified phone claims; unverified users rejected')
        request(None, '/rides', expected=401)
        request('rider', '/rides')
        rider = fixture['users']['rider']['uid']
        guardian = fixture['users']['guardian']['uid']
        request('guardian', f'/rider-status?riderId={rider}', expected=403)
        request('rider', '/guardians/invite', 'POST', {'contact': fixture['users']['guardian']['email']}, 201)
        assert len(request('guardian', '/guardians/invitations')['items']) == 1
        request('stranger', '/guardians/accept', 'POST', {'riderId': rider}, 404)
        request('guardian', '/guardians/accept', 'POST', {'riderId': rider})
        assert len(request('rider', '/guardians')['items']) == 1
        assert len(request('guardian', '/shared-riders')['items']) == 1
        print('PASS invitation, accept, both lists, unrelated account denied')
        point = {'latitude': 17.9146, 'longitude': 77.5046, 'speedKph': 37.2,
                 'recordedAt': datetime.now(timezone.utc).isoformat(), 'status': 'RIDING'}
        request('rider', '/location', 'POST', point, 202)
        live = request('guardian', f'/rider-status?riderId={rider}')['status']
        assert live['speedKph'] == 37.2 and live['latitude'] == 17.9146
        request('stranger', f'/rider-status?riderId={rider}', expected=403)
        hospitals = request('guardian', '/nearby-hospitals?lat=17.9146&lng=77.5046')['items']
        assert hospitals
        h = hospitals[0]
        routes = request('guardian', f"/route?originLat=17.9146&originLng=77.5046&destinationLat={h['latitude']}&destinationLng={h['longitude']}")['Routes']
        assert routes
        print('PASS shared speed/location, Azure-to-Google hospitals and routes')
        request('rider', '/rides', 'POST', {'id': 'isolated-test-ride', 'distanceKm': 1.25, 'durationSeconds': 120}, 201)
        assert len(request('rider', '/rides')['items']) == 1
        for _ in range(2):
            sos = request('rider', '/emergency', 'POST', {'requestId': 'isolated-test-sos', 'reason': 'TEST ONLY - no emergency', **point}, 202)
            assert sos['saved'] and sos['guardians'] == 1
        assert len(request('guardian', '/alerts')['items']) == 1
        assert not request('stranger', '/alerts')['items']
        request('rider', '/location', 'POST', {**point, 'status': 'SAFE', 'recordedAt': datetime.now(timezone.utc).isoformat()}, 202)
        live = request('guardian', f'/rider-status?riderId={rider}')['status']
        assert live['status'] == 'SAFE' and live['speedKph'] == 0
        print('PASS ride save, SOS deduplication, guardian alerts, stop sets speed zero')
        request('rider', '/guardians/remove', 'POST', {'guardianId': guardian})
        request('guardian', f'/rider-status?riderId={rider}', expected=403)
        assert not request('guardian', '/alerts')['items']
        print('PASS revocation removes access to status and alerts')
        request('guardian', '/riders/request', 'POST', {'contact': fixture['users']['rider']['phone']}, 202)
        assert len(request('rider', '/guardian-requests')['items']) == 1
        assert len(request('guardian', '/riders/requests')['items']) == 1
        request('guardian', f'/rider-rides?riderId={rider}', expected=403)
        request('stranger', '/guardian-requests/respond', 'POST', {'guardianId': guardian, 'action': 'accept'}, 404)
        request('rider', '/guardian-requests/respond', 'POST', {'guardianId': guardian, 'action': 'accept'})
        shared_history = request('guardian', f'/rider-rides?riderId={rider}')['items']
        assert len(shared_history) == 1 and shared_history[0]['distanceKm'] == 1.25
        assert not request('guardian', '/riders/requests')['items']
        request('stranger', f'/rider-rides?riderId={rider}', expected=403)
        request('rider', '/guardians/remove', 'POST', {'guardianId': guardian})
        request('guardian', f'/rider-rides?riderId={rider}', expected=403)
        print('PASS guardian phone request, rider approval, shared history and revocation')
        if keep:
            request('rider', '/guardians/invite', 'POST', {'contact': fixture['users']['guardian']['email']}, 201)
            request('guardian', '/guardians/accept', 'POST', {'riderId': rider})
            print('Isolated fixture retained for device tests in ignored tmp/.')
    finally:
        if not keep:
            cleanup(fixture)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--keep', action='store_true')
    parser.add_argument('--cleanup', action='store_true')
    args = parser.parse_args()
    if args.cleanup:
        cleanup(json.loads(FIXTURE.read_text()))
    else:
        run(args.keep)
