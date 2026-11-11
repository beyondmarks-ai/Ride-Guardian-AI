"""Send a marked SOS only between the isolated cloud-test identities."""
import argparse
import json
import time
from datetime import datetime, timezone

import requests
from azure.cosmos import CosmosClient
from test_hybrid_cloud import BASE, FIXTURE, cli

parser = argparse.ArgumentParser()
parser.add_argument('--send', action='store_true')
parser.add_argument('--location', action='store_true')
args = parser.parse_args()
fixture = json.loads(FIXTURE.read_text())
guardian = fixture['users']['guardian']
rider = fixture['users']['rider']
settings = json.loads(cli('az', 'functionapp', 'config', 'appsettings', 'list', '--name',
    'rideguardian-api-617db5', '--resource-group', 'guardian-ai-rg', '-o', 'json'))
connection = next(x['value'] for x in settings if x['name'] == 'COSMOS_CONNECTION')
db = CosmosClient.from_connection_string(connection).get_database_client('rideguardian').get_container_client('items')
devices = list(db.query_items('SELECT c.id FROM c WHERE c.entityType = @type AND c.userId = @uid',
    parameters=[{'name': '@type', 'value': 'DEVICE'}, {'name': '@uid', 'value': guardian['uid']}],
    enable_cross_partition_query=True))
print(f'Guardian test devices registered: {len(devices)}')
if args.send or args.location:
    assert devices, 'Sign in on the guardian test device and enable notifications first'
    result = requests.post(BASE + '/location', headers={'Authorization': 'Bearer ' + rider['token']},
        json={'latitude': 17.9146, 'longitude': 77.5046, 'speedKph': 37.2,
              'recordedAt': datetime.now(timezone.utc).isoformat()}, timeout=35)
    result.raise_for_status()
    print('Published isolated rider location at 37.2 km/h.')
if args.send:
    result = requests.post(BASE + '/emergency', headers={'Authorization': 'Bearer ' + rider['token']},
        json={'requestId': f'device-test-{int(time.time())}', 'reason': 'TEST ONLY - guardian notification check'}, timeout=35)
    result.raise_for_status()
    print('Test SOS saved and notification queued.')
notices = list(db.query_items('SELECT c.status, c.attempts, c.createdAt FROM c WHERE c.pk = @pk AND c.userId = @uid',
    parameters=[{'name': '@pk', 'value': 'NOTIFICATIONS'}, {'name': '@uid', 'value': guardian['uid']}],
    partition_key='NOTIFICATIONS'))
for notice in sorted(notices, key=lambda n: n['createdAt']):
    print('Notification status:', notice['status'], 'attempts:', notice['attempts'])
