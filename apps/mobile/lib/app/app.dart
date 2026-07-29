import 'package:flutter/material.dart';

import '../features/session/session_page.dart';
import '../theme/aevum_theme.dart';

class AevumBioAgeApp extends StatelessWidget {
  const AevumBioAgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aevum BioAge',
      debugShowCheckedModeBanner: false,
      theme: AevumTheme.light(),
      home: const SessionPage(),
    );
  }
}
