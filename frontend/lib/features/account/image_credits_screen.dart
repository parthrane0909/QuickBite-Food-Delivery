/// In-app attribution for real bundled food photographs.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/app_colors.dart';

class ImageCreditsScreen extends StatelessWidget {
  const ImageCreditsScreen({super.key});

  Future<Map<String, dynamic>> _load() async =>
      (jsonDecode(await rootBundle.loadString('assets/food/CREDITS.json'))
          as Map<String, dynamic>);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Image credits & licenses')),
    body: FutureBuilder<Map<String, dynamic>>(
      future: _load(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('Photo attribution is unavailable.'));
        }
        final entries = snapshot.data;
        if (entries == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.screenPadding),
              children: [
                Text(
                  'Food photography',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Images are resized and recompressed for the app. Creative Commons ShareAlike terms apply to the corresponding photographs; the QuickBite application code is separate.',
                  style: TextStyle(color: AppColors.inkSoft, height: 1.5),
                ),
                const SizedBox(height: 20),
                for (final entry in entries.entries)
                  _CreditCard(
                    id: entry.key,
                    data: entry.value as Map<String, dynamic>,
                  ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class _CreditCard extends StatelessWidget {
  const _CreditCard({required this.id, required this.data});
  final String id;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(id, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            '${data['title'] ?? 'Photo'} · ${data['artist'] ?? 'Author not recorded'}',
          ),
          Text('${data['licence'] ?? 'License not recorded'} · asset $id.jpg'),
          const SizedBox(height: 4),
          SelectableText(
            '${data['page'] ?? ''}',
            style: const TextStyle(color: AppColors.primaryDark),
          ),
          if (data['licence_url'] != null)
            SelectableText(
              '${data['licence_url']}',
              style: const TextStyle(color: AppColors.inkSoft),
            ),
        ],
      ),
    ),
  );
}
