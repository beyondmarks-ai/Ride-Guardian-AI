import copy
import json
import unittest
from datetime import datetime, timezone, timedelta
from unittest.mock import patch

import azure.functions as func
from azure.cosmos.exceptions import CosmosResourceNotFoundError
import function_app as api


class MemoryContainer:
    def __init__(self):
        self.items = {}

    def upsert_item(self, item):
        self.items[(item['pk'], item['id'])] = copy.deepcopy(item)

    def read_item(self, item, partition_key):
        if (partition_key, item) not in self.items:
            raise CosmosResourceNotFoundError(status_code=404)
        return copy.deepcopy(self.items[(partition_key, item)])

    def delete_item(self, item, partition_key):
        del self.items[(partition_key, item)]

    def query_items(self, query, parameters, **kwargs):
        params = {p['name']: p['value'] for p in parameters}
        if '@uid' in params:
            return [copy.deepcopy(v) for v in self.items.values() if v.get('entityType') == params['@type'] and v.get('userId') == params['@uid']]
        return [copy.deepcopy(v) for v in self.items.values() if v['pk'] == params['@pk'] and v.get('sk', '').startswith(params['@prefix'])]


class FamilyFlows(unittest.TestCase):
    def setUp(self):
        self.db = MemoryContainer()
        self.database = patch.object(api, 'container', return_value=self.db)
        self.database.start()
        self.addCleanup(self.database.stop)
        self.rider = {'sub': 'rider', 'phone_number': '+919999999999'}
        self.guardian = {'sub': 'guardian', 'phone_number': '+918888888888'}
        self.stranger = {'sub': 'stranger', 'email': 'stranger@example.com', 'email_verified': True}

    def call(self, name, claims, body=None, params=None, method='POST'):
        req = func.HttpRequest(method, 'http://localhost', params=params or {}, body=json.dumps(body or {}).encode())
        with patch.object(api, 'authenticated', return_value=(claims, None)):
            result = getattr(api, name)._function.get_user_function()(req)
        return result.status_code, json.loads(result.get_body())

    def connect(self):
        self.assertEqual(self.call('invite_guardian', self.rider, {'contact': '+91 88888 88888'})[0], 201)
        self.assertEqual(len(self.call('invitations', self.guardian)[1]['items']), 1)
        self.assertEqual(self.call('accept_invitation', self.stranger, {'riderId': 'rider'})[0], 404)
        self.assertEqual(self.call('accept_invitation', self.guardian, {'riderId': 'rider'})[0], 200)

    def test_phone_invitation_location_sos_and_revoke(self):
        self.assertEqual(self.call('rider_status', self.guardian, params={'riderId': 'rider'})[0], 403)
        self.connect()
        self.call('save_location', self.rider, {'latitude': 17.91, 'longitude': 77.50, 'speedKph': 42})
        status = self.call('rider_status', self.guardian, params={'riderId': 'rider'})[1]['status']
        self.assertEqual(status['speedKph'], 42)
        self.assertEqual(status['latitude'], 17.91)
        self.assertEqual(self.call('rider_status', self.stranger, params={'riderId': 'rider'})[0], 403)
        for _ in range(2):
            status, sos = self.call('emergency', self.rider, {'requestId': 'test-sos', 'reason': 'TEST ONLY'})
            self.assertEqual(status, 202)
            self.assertEqual(sos['guardians'], 1)
        self.assertEqual(len(self.call('alerts', self.guardian)[1]['items']), 1)
        self.assertEqual(len(self.call('alerts', self.stranger)[1]['items']), 0)
        self.assertEqual(len(api.query_partition('NOTIFICATIONS', 'NOTICE#')), 1)
        self.call('remove_guardian', self.rider, {'guardianId': 'guardian'})
        self.assertEqual(self.call('rider_status', self.guardian, params={'riderId': 'rider'})[0], 403)
        self.assertEqual(self.call('alerts', self.guardian)[1]['items'], [])
        api.send_notice(api.query_partition('NOTIFICATIONS', 'NOTICE#')[0])
        self.assertEqual(api.query_partition('NOTIFICATIONS', 'NOTICE#')[0]['status'], 'revoked')

    def test_guardian_phone_request_requires_rider_approval_and_history_revokes(self):
        contact = self.rider['phone_number']
        for _ in range(2):
            self.assertEqual(self.call('request_rider', self.guardian, {'contact': contact})[0], 202)
        self.assertEqual(len(self.call('guardian_requests', self.rider)[1]['items']), 1)
        self.assertEqual(len(self.call('pending_rider_requests', self.guardian)[1]['items']), 1)
        self.assertEqual(self.call('rider_rides', self.guardian, params={'riderId': 'rider'})[0], 403)
        self.assertEqual(self.call('respond_guardian_request', self.stranger, {'guardianId': 'guardian', 'action': 'accept'})[0], 404)
        self.assertEqual(self.call('respond_guardian_request', self.rider, {'guardianId': 'guardian', 'action': 'accept'})[0], 200)
        self.assertEqual(self.call('pending_rider_requests', self.guardian)[1]['items'], [])
        self.call('rides', self.rider, {'id': 'history-test', 'durationSeconds': 150, 'distanceKm': 2.5, 'maxSpeedKph': 42, 'points': [{'latitude': 17.9}], 'events': [{'type': 'impact'}]})
        status, result = self.call('rider_rides', self.guardian, params={'riderId': 'rider'})
        self.assertEqual(status, 200)
        self.assertEqual(result['items'][0]['distanceKm'], 2.5)
        self.assertEqual(result['items'][0]['eventCount'], 1)
        self.assertNotIn('points', result['items'][0])
        self.call('remove_guardian', self.rider, {'guardianId': 'guardian'})
        self.assertEqual(self.call('rider_rides', self.guardian, params={'riderId': 'rider'})[0], 403)

    def test_request_decline_cancel_expiry_and_wrong_number(self):
        contact = self.rider['phone_number']
        self.call('request_rider', self.guardian, {'contact': contact})
        self.call('respond_guardian_request', self.rider, {'guardianId': 'guardian', 'action': 'decline'})
        self.assertFalse(api.can_watch('guardian', 'rider'))
        self.assertEqual(self.call('pending_rider_requests', self.guardian)[1]['items'], [])
        self.call('request_rider', self.guardian, {'contact': contact})
        self.call('cancel_rider_request', self.stranger, {'contact': contact})
        self.assertEqual(len(self.call('guardian_requests', self.rider)[1]['items']), 1)
        self.call('cancel_rider_request', self.guardian, {'contact': contact})
        self.assertEqual(self.call('guardian_requests', self.rider)[1]['items'], [])
        self.call('request_rider', self.guardian, {'contact': contact})
        for item in self.db.items.values():
            if item.get('guardianId') == 'guardian': item['expiresAt'] = 1
        self.assertEqual(self.call('guardian_requests', self.rider)[1]['items'], [])
        self.assertEqual(self.call('respond_guardian_request', self.rider, {'guardianId': 'guardian', 'action': 'accept'})[0], 404)
        self.assertEqual(self.call('request_rider', self.guardian, {'contact': '999'})[0], 400)

    def test_unverified_email_cannot_accept_invitation(self):
        self.call('invite_guardian', self.rider, {'contact': 'target@example.com'})
        claims = dict(self.guardian, email='target@example.com', email_verified=False)
        self.assertEqual(self.call('invitations', claims)[1]['items'], [])
        self.assertEqual(self.call('accept_invitation', claims, {'riderId': 'rider'})[0], 404)

    def test_hospital_search_excludes_medical_shops(self):
        with patch.dict(api.os.environ, {'GOOGLE_MAPS_API_KEY': 'test-key'}), patch.object(api.requests, 'post') as post:
            post.return_value.json.return_value = {'places': [
                {'primaryType': 'medical_center', 'displayName': {'text': 'Chemist'}, 'location': {'latitude': 17.91, 'longitude': 77.50}},
                {'primaryType': 'hospital', 'displayName': {'text': 'General Hospital'}, 'location': {'latitude': 17.92, 'longitude': 77.51}},
            ]}
            status, result = self.call('nearby_hospitals', self.guardian, params={'lat': '17.91', 'lng': '77.50'}, method='GET')
        self.assertEqual(status, 200)
        self.assertEqual([item['name'] for item in result['items']], ['General Hospital'])

    def test_helmet_presence_is_separate_from_strap_and_rejects_invalid_verdicts(self):
        with patch.dict(api.os.environ, {'AZURE_OPENAI_API_KEY': 'test', 'AZURE_OPENAI_ENDPOINT': 'https://example.invalid'}), patch.object(api.requests, 'post') as post:
            for verdict, expected in [
                ({'helmet_present': True, 'worn_on_head': True, 'confidence': .95, 'strap_status': 'not_visible'}, True),
                ({'helmet_present': False, 'worn_on_head': False, 'confidence': 1}, False),
                ({'helmet_present': True, 'worn_on_head': False, 'confidence': .99}, False),
                ({'helmet_present': 'false', 'worn_on_head': 'true', 'confidence': .99}, False),
                ({'helmet_present': True, 'worn_on_head': True, 'confidence': .6}, False),
            ]:
                post.return_value.json.return_value = {'choices': [{'message': {'content': json.dumps(verdict)}}]}
                status, result = self.call('helmet_check', self.rider)
                self.assertEqual(status, 200)
                self.assertEqual(result['detected'], expected)
            post.return_value.json.return_value = {'choices': [{'message': {'content': json.dumps({'confidence': 99})}}]}
            self.assertEqual(self.call('helmet_check', self.rider)[0], 502)

    def test_stale_riding_status_and_stop_speed(self):
        self.connect()
        self.call('save_location', self.rider, {'latitude': 17.91, 'longitude': 77.50, 'speedKph': 50})
        live = self.db.read_item('live', 'USER#rider')
        live['updatedAt'] = (datetime.now(timezone.utc) - timedelta(minutes=2)).isoformat()
        self.db.upsert_item(live)
        stale = self.call('rider_status', self.guardian, params={'riderId': 'rider'})[1]['status']
        self.assertEqual(stale['status'], 'OFFLINE')
        self.assertEqual(stale['speedKph'], 0)
        self.call('save_location', self.rider, {'latitude': 17.91, 'longitude': 77.50, 'speedKph': 50, 'status': 'SAFE'})
        self.assertEqual(self.call('rider_status', self.guardian, params={'riderId': 'rider'})[1]['status']['speedKph'], 0)

    def test_device_reassignment_and_unregistration_are_scoped(self):
        token = 'test-notification-token-only'
        self.call('register_device', self.guardian, {'token': token})
        self.call('register_device', self.stranger, {'token': token}, method='DELETE')
        self.assertEqual(len([v for v in self.db.items.values() if v.get('entityType') == 'DEVICE']), 1)
        self.call('register_device', self.rider, {'token': token})
        devices = [v for v in self.db.items.values() if v.get('entityType') == 'DEVICE']
        self.assertEqual(len(devices), 1)
        self.assertEqual(devices[0]['userId'], 'rider')

    def test_no_guardians_sos_is_saved_without_delivery_claim(self):
        status, result = self.call('emergency', self.rider, {'requestId': 'solo-sos'})
        self.assertEqual(status, 202)
        self.assertTrue(result['saved'])
        self.assertEqual(result['notificationStatus'], 'no_guardians')
        self.assertNotIn('delivered', result)


if __name__ == '__main__':
    unittest.main()
