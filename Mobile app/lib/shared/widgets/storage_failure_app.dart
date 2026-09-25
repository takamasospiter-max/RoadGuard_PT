import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class StorageFailureApp extends StatelessWidget {
  const StorageFailureApp({required this.onRetry, super.key});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: roadTheme(Brightness.light),
    home: Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.storage_outlined, size: 48),
                const SizedBox(height: 22),
                const Text(
                  'Local storage could not be opened.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Your existing data has not been cleared. Check device storage and try again.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 22),
                FilledButton(
                  onPressed: onRetry,
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
