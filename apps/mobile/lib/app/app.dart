import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../features/session/session_page.dart';
import '../features/web/web_home_page.dart';
import '../theme/aevum_theme.dart';

class AevumBioAgeApp extends StatelessWidget {
  const AevumBioAgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aevum BioAge',
      debugShowCheckedModeBanner: false,
      theme: AevumTheme.light(),
      home: kIsWeb ? const WebHomePage() : const SessionPage(),
      routes: {
        SessionPage.routeName: (_) => const SessionPage(),
      },
    );
  }
}
