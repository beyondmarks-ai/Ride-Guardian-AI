import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/ride_models.dart';

Future<void> openExternal(BuildContext context, Uri uri) async {
  try {
    if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
  } catch (_) {}
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Could not open Maps or the phone app. Please try again.',
        ),
      ),
    );
  }
}

Future<void> showHospitalSearch(
  BuildContext context, {
  required Future<List<NearbyPlace>> Function() search,
  required String title,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _HospitalResults(search: search, title: title),
  );
}

class _HospitalResults extends StatefulWidget {
  const _HospitalResults({required this.search, required this.title});
  final Future<List<NearbyPlace>> Function() search;
  final String title;
  @override
  State<_HospitalResults> createState() => _HospitalResultsState();
}

class _HospitalResultsState extends State<_HospitalResults> {
  late Future<List<NearbyPlace>> result = widget.search();
  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .7,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text(
              'Tap a hospital for directions. Call to confirm emergency care is available.',
            ),
            const SizedBox(height: 16),
            Expanded(
              child: FutureBuilder<List<NearbyPlace>>(
                future: result,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('Getting location and finding hospitals…'),
                        ],
                      ),
                    );
                  }
                  if (snapshot.hasError || (snapshot.data?.isEmpty ?? true)) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            snapshot.hasError
                                ? snapshot.error.toString()
                                : 'No hospitals found within 10 km.',
                          ),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: () => setState(() {
                              result = widget.search();
                            }),
                            child: const Text('Try again'),
                          ),
                        ],
                      ),
                    );
                  }
                  return ListView.separated(
                    itemCount: snapshot.data!.length,
                    separatorBuilder: (_, _) => const Divider(),
                    itemBuilder: (context, i) {
                      final h = snapshot.data![i];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.local_hospital_outlined),
                        title: Text(h.name),
                        subtitle: Text(
                          '${h.distanceKm.toStringAsFixed(1)} km • Directions',
                        ),
                        onTap: () => openExternal(
                          context,
                          Uri.parse(
                            'https://www.google.com/maps/dir/?api=1&destination=${h.latitude},${h.longitude}',
                          ),
                        ),
                        trailing: h.phone == null
                            ? const Icon(Icons.directions)
                            : IconButton(
                                tooltip: 'Call hospital',
                                icon: const Icon(Icons.call_outlined),
                                onPressed: () => openExternal(
                                  context,
                                  Uri(scheme: 'tel', path: h.phone),
                                ),
                              ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
