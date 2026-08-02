import 'package:flutter/material.dart';

import '../../theme/aevum_colors.dart';
import '../session/session_page.dart';

class WebHomePage extends StatelessWidget {
  const WebHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _LandingBackdrop(),
          LayoutBuilder(
            builder: (context, viewport) {
              final compact = viewport.maxWidth < 820;
              final isVeryNarrow = viewport.maxWidth < 430;
              final heroCard = Container(
                padding: EdgeInsets.all(compact ? 20 : 28),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xCC11263B), Color(0xE61B3B59)],
                  ),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: AevumColors.border),
                  boxShadow: const [
                    BoxShadow(color: Color(0x66040A10), blurRadius: 30, offset: Offset(0, 16)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: compact ? MainAxisAlignment.start : MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AevumColors.cream.withAlpha(24),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: AevumColors.cream.withAlpha(40)),
                      ),
                      child: const Text(
                        'Movement assessment with Aevum BioAge',
                        style: TextStyle(
                          color: AevumColors.cream,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.7,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Estimate biological age through motion, rhythm, and repeatable effort.',
                      style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                        fontSize: compact ? 30 : 52,
                        height: 1.05,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      compact
                          ? 'Start with a quick camera-guided movement check and get a BioAge estimate.'
                          : 'Inspired by Aevum\'s longevity approach, this assessment blends deliberate movement, body awareness, and a coordinated feedback loop into one focused experience.',
                      style: const TextStyle(
                        color: AevumColors.textSecondary,
                        fontSize: 16,
                        height: 1.5,
                      ),
                    ),
                    SizedBox(height: compact ? 20 : 24),
                    if (compact) ...[
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          ElevatedButton.icon(
                            onPressed: () {
                              Navigator.of(context).pushNamed(SessionPage.routeName);
                            },
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('Start Assessment'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () {
                              showDialog<void>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  backgroundColor: AevumColors.surface,
                                  title: const Text('Camera Access'),
                                  content: const Text(
                                    'Allow camera permission in your browser when prompted. For best results, keep your upper body visible with steady lighting and room to move.',
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
                            icon: const Icon(Icons.videocam_outlined),
                            label: const Text('Camera Guidance'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        if (!isVeryNarrow) const _InfoPill(label: 'Push-ups or squats'),
                        const _InfoPill(label: 'Camera-guided tracking'),
                        const _InfoPill(label: 'BioAge estimate'),
                      ],
                    ),
                    if (!compact) ...[
                      const SizedBox(height: 28),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          ElevatedButton.icon(
                            onPressed: () {
                              Navigator.of(context).pushNamed(SessionPage.routeName);
                            },
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('Start Assessment'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () {
                              showDialog<void>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  backgroundColor: AevumColors.surface,
                                  title: const Text('Camera Access'),
                                  content: const Text(
                                    'Allow camera permission in your browser when prompted. For best results, keep your upper body visible with steady lighting and room to move.',
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
                            icon: const Icon(Icons.videocam_outlined),
                            label: const Text('Camera Guidance'),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              );

              final metricCard = Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AevumColors.surfaceDim.withAlpha(214),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: AevumColors.border),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _MetricRow(index: '01', title: 'Assess', copy: 'Capture motion quality and rep performance through a guided camera view.'),
                    SizedBox(height: 18),
                    _MetricRow(index: '02', title: 'Play', copy: 'Use body movement to keep the crane aloft while navigating a coordinated flow.'),
                    SizedBox(height: 18),
                    _MetricRow(index: '03', title: 'Reflect', copy: 'Turn exercise output into a simple wellness estimate with visible progress cues.'),
                  ],
                ),
              );

              if (compact) {
                return SafeArea(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            heroCard,
                            const SizedBox(height: 20),
                            if (!isVeryNarrow) metricCard,
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }

              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1060),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(flex: 11, child: heroCard),
                        const SizedBox(width: 20),
                        Expanded(flex: 8, child: metricCard),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _LandingBackdrop extends StatelessWidget {
  const _LandingBackdrop();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF08111B), Color(0xFF10253A), Color(0xFF173856)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -120,
            right: -40,
            child: _GlowOrb(size: 320, color: AevumColors.primary),
          ),
          Positioned(
            bottom: -120,
            left: -60,
            child: _GlowOrb(size: 280, color: AevumColors.gold),
          ),
          Positioned.fill(
            child: CustomPaint(painter: _LandingLinePainter()),
          ),
        ],
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  final double size;
  final Color color;

  const _GlowOrb({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color.withAlpha(80), color.withAlpha(0)],
          ),
        ),
      ),
    );
  }
}

class _LandingLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = AevumColors.secondary.withAlpha(18)
      ..strokeWidth = 1;
    const spacing = 40.0;
    for (var x = 0.0; x <= size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (var y = 0.0; y <= size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final orbitPaint = Paint()
      ..color = AevumColors.cream.withAlpha(26)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    canvas.drawOval(
      Rect.fromCenter(center: Offset(size.width * 0.78, size.height * 0.18), width: 220, height: 120),
      orbitPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(size.width * 0.18, size.height * 0.68), width: 180, height: 90),
      orbitPaint,
    );

    final craneMark = Path()
      ..moveTo(size.width * 0.8, size.height * 0.24)
      ..lineTo(size.width * 0.85, size.height * 0.29)
      ..lineTo(size.width * 0.9, size.height * 0.21);
    canvas.drawPath(
      craneMark,
      Paint()
        ..color = AevumColors.cream.withAlpha(40)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _InfoPill extends StatelessWidget {
  final String label;

  const _InfoPill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AevumColors.mist.withAlpha(120),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AevumColors.border),
      ),
      child: Text(label, style: const TextStyle(color: AevumColors.cream, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

class _MetricRow extends StatelessWidget {
  final String index;
  final String title;
  final String copy;

  const _MetricRow({required this.index, required this.title, required this.copy});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(index, style: const TextStyle(color: AevumColors.gold, fontSize: 26, fontWeight: FontWeight.w700)),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(copy, style: const TextStyle(color: AevumColors.textSecondary, height: 1.45)),
            ],
          ),
        ),
      ],
    );
  }
}
