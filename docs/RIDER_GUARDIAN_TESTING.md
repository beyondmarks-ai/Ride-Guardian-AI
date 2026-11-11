# Rider and guardian guide and verification

Updated: 11 November 2026.

Both people use the same RideGuardian Android app with their own Firebase
accounts. There is no shared password or separate guardian installation.

## Connect the two accounts

1. The first screen offers **I am a rider** and **I am a guardian**, before sign-in.
   Choose a role, then sign in with your own verified email/password or phone OTP.
   Existing signed-in sessions are preserved; selecting a role opens its dashboard.
2. For connection by phone, the rider signs in using that phone number. The
   guardian opens **Connect a rider**, enters it with `+91`, and taps
   **Send connection request**. This does not send an SMS or reveal private data.
3. The rider sees **Guardian connection requests** on Home and in Family, with
   the guardian's verified contact. **Allow sharing** grants speed, location,
   completed ride history and SOS access; **Decline** grants none. Existing devices
   can receive a request push. Request taps open the rider's Family page.
4. The guardian sees pending requests until approval. They can cancel requests;
   requests expire after seven days. Approval connects the rider automatically.
   The older rider-to-guardian invitation flow remains available in Family.
5. The dedicated **Guardian dashboard** has a rider selector, animated speedometer,
   Google map, last-update time, expandable ride history and SOS cards. History
   shows up to 50 completed rides with distance, duration, maximum speed, safety
   score and event count. Status and history refresh about every 10 seconds;
   stale or disconnected updates hide speed. Both phones should allow notifications.
6. **Open location** opens Google Maps. **Nearby hospitals** and
   **Hospitals near this SOS** search around the rider's coordinates, rather
   than the guardian's phone. Call the facility to confirm emergency care.
7. The rider can remove sharing. Removed guardians lose access to status and
   past alerts and ride history through the API; pending SOS pushes are checked again before sending.

## What an SOS does

Before each ride, take a fresh helmet photo and confirm you have fastened the
chin strap. A successful check expires after five minutes if the ride has not
started; stopping a ride resets it. A cancelled, negative or failed check cannot
start monitoring. Azure reports helmet presence separately from strap visibility;
the photo does not certify helmet fit or fastening. The actual camera samples from
the connected phone were replayed against the deployed API: helmet-on-head passed,
bare head failed. The original false rejection was caused by strap status being
reported as "not detected" instead of showing the model's explanation.
The rider also completed a fresh camera check on the physical Vivo phone: the UI
showed "Detected 99%" and an active ride after the required confirmation.

During an active ride, a severe impact or eight strong motion peaks over about
1.4–2.5 seconds triggers a suspected-accident check. Normal low-level vibration and
an isolated moderate bump are ignored. The rider has 20 seconds to cancel. If the
countdown expires, an SOS is sent. Thresholds are heuristics and need road/device
calibration; shaking or dropping a phone is not proof of a crash. Monitoring must
remain running; Android force-stop stops sensor detection.

The API saves an alert for accepted guardians and queues push delivery.
A worker checks the queue every 10 seconds and retries transient FCM failures.
The guardian receives an Android notification while the app is in the background,
and can also read the alert in Family. Tapping a push is handled by the Family
notification flow. The alert includes the available location; SOS still records
when GPS is unavailable. A failed request is shown as unconfirmed, not as sent.
Retrying the same pending SOS does not create a duplicate server alert.

Push requires internet, an active sign-in, notification permission, and a valid
device registration. Android force-stop or manufacturer battery restrictions
can prevent delivery. FCM acceptance does not prove that a person saw the alert.
No automatic ambulance call or emergency SMS is implemented. Call 112 directly
when urgent assistance is needed.

## Verified results

| Check | Result |
|---|---|
| Phone-only session survives restart and provides API token | Regression test passed; actual phone restored its session |
| Email verification and phone claims accepted by Azure | Live isolated-account test passed |
| Unverified identities / missing tokens rejected | Live HTTP 403 / 401 verified |
| Invite, accept, list both sides | Live isolated-account test passed |
| Other accounts cannot accept or read rider data | Live permission test passed |
| Shared speed and coordinates | Live API read 37.2 km/h and exact test coordinates; guardian UI displayed rounded 37 km/h and Riding |
| Dedicated dashboard | Speedometer, rider selector, SOS cards and account-specific role restore verified on guardian emulator |
| First-screen role choice | Widget tests passed for rider/guardian selection, role-labelled login and changing role |
| Guardian-initiated connection | Live test passed for phone request, rider approval and pending-request removal |
| Shared ride history | Live API test passed; unrelated accounts and removed guardians denied |
| Guardian map | Tiles and marker visually verified; loading indicator no longer recreates map during polling |
| Google hospitals and two-wheeler routes through Azure | Live API test passed |
| Guardian hospital sheet | Visually checked on the guardian emulator |
| SOS saved, deduplicated, visible only to guardian | Live API and unit tests passed |
| Background push | FCM accepted; ADB confirmed high-importance Android notification on guardian emulator |
| Notification tap | Opened Family with guardian mode selected on the emulator |
| Hospital filtering | Medical-center/chemist results excluded; regression and deployed API checks passed (10 hospitals returned near Bidar) |
| Revocation | Live status and alerts access removed; pending push checks covered by unit test |
| Stale location and stopped ride | Stale status becomes offline; stopped speed is zero |
| Maps on physical Vivo phone | Tiles and actual GPS marker visually checked |
| Physical start/stop | Short stationary ride started GPS foreground service, stopped, and appeared in history |
| Tabs | Overlapping-page bug fixed; widget regression check passes |

Thirteen Flutter tests and nine backend unit tests cover these flows, including
helmet gating, cancellation/expiry, motion windows, cooldown, cancelled/expired
SOS countdowns, stale speed and hospital loading/error/retry. The physical phone's
Hospitals button opened results, and selecting a hospital opened Google Maps.
The new tests cover first-screen role choice, guardian phone-number submission,
rider approval/decline, request cancellation/expiry, and ride-history access
before approval and after revocation.
The live cloud test uses isolated accounts and marked test SOS records; it sends
no SMS and calls no emergency service. Controlled road-crash testing and testing
every Android manufacturer were not performed.

## Repeat the checks

```powershell
flutter analyze
flutter test
python -m unittest discover -s azure_backend -p test_flows.py -v
python tool/test_hybrid_cloud.py
```

Use a Python environment with `azure_backend/requirements.txt` installed and
authorized GCP/Azure CLIs. For a device notification test, `--keep` retains the
isolated fixture in ignored `tmp/`; sign in as its guardian on a test device,
then run `python tool/test_guardian_push.py --send`. Finally run
`python tool/test_hybrid_cloud.py --cleanup`. Credentials are never printed.
