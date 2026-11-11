import 'package:flutter/material.dart';
import '../controllers/ride_controller.dart';

class ConnectRiderCard extends StatefulWidget {
  const ConnectRiderCard({super.key, required this.controller});
  final RideController controller;
  @override
  State<ConnectRiderCard> createState() => _ConnectRiderCardState();
}

class _ConnectRiderCardState extends State<ConnectRiderCard> {
  final phone = TextEditingController(text: '+91 ');
  final form = GlobalKey<FormState>();
  @override
  void dispose() {
    phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Card(
      child: ExpansionTile(
        key: const PageStorageKey('connect-rider'),
        initiallyExpanded: c.sharedRiders.isEmpty,
        leading: const Icon(Icons.person_add_alt_1),
        title: const Text('Connect a rider'),
        subtitle: const Text('Enter their phone number'),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Form(
              key: form,
              child: Column(
                children: [
                  const Text(
                    'The rider must sign in with this phone number and approve your request. Sharing includes location, speed, ride history and SOS alerts.',
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Rider phone number',
                      hintText: '+91 98765 43210',
                    ),
                    validator: (value) =>
                        RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(
                          (value ?? '').replaceAll(RegExp(r'[\s()-]'), ''),
                        )
                        ? null
                        : 'Enter the full number with country code.',
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: c.connectionBusy
                          ? null
                          : () {
                              if (form.currentState!.validate()) {
                                c.requestRider(phone.text);
                              }
                            },
                      icon: const Icon(Icons.link),
                      label: Text(
                        c.connectionBusy
                            ? 'Sending…'
                            : 'Send connection request',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class GuardianRequestInbox extends StatelessWidget {
  const GuardianRequestInbox({super.key, required this.controller});
  final RideController controller;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (controller.connectionMessage != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(controller.connectionMessage!),
        ),
      if (controller.guardianRequests.isNotEmpty) ...[
        const Text(
          'Guardian connection requests',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
        ),
        ...controller.guardianRequests.map(
          (request) => Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    request.guardianContact,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Wants to see your speed, location, ride history and SOS alerts. Only allow someone you trust.',
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 12,
                    children: [
                      FilledButton(
                        onPressed: controller.connectionBusy
                            ? null
                            : () => controller.respondToGuardian(request, true),
                        child: const Text('Allow sharing'),
                      ),
                      TextButton(
                        onPressed: controller.connectionBusy
                            ? null
                            : () =>
                                  controller.respondToGuardian(request, false),
                        child: const Text('Decline'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    ],
  );
}
