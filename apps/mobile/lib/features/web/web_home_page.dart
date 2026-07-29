import 'package:flutter/material.dart';

import '../../theme/aevum_colors.dart';
import '../session/session_page.dart';

class WebHomePage extends StatelessWidget {
  const WebHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Aevum BioAge',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Estimate biological age from push-up or squat performance '
                  'with an Aevum crane rhythm game.',
                  style: TextStyle(color: AevumColors.textSecondary, fontSize: 16),
                ),
                const SizedBox(height: 20),
                const Text(
                  'This is a wellness estimate, not a medical diagnosis.',
                  style: TextStyle(color: AevumColors.textSecondary, fontSize: 13, fontStyle: FontStyle.italic),
                ),
                const SizedBox(height: 32),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pushNamed(SessionPage.routeName);
                      },
                      child: const Text('Start Assessment'),
                    ),
                    OutlinedButton(
                      onPressed: () {
                        showDialog<void>(
                          context: context,
                          builder: (context) => AlertDialog(
                            backgroundColor: AevumColors.surface,
                            title: const Text('Camera Access'),
                            content: const Text(
                              'Allow camera permission in your browser when prompted. '
                              'For best results, keep full body visible with good lighting.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: const Text('OK'),
                              ),
                            ],
                          ),
                        );
                      },
                      child: const Text('Camera Guidance'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
