import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'package:roadguard_ai/core/theme/app_theme.dart';
import 'package:roadguard_ai/modules/boarding/routes/boarding_paths.dart';

/// Reference welcome: full-bleed photo with the exact overlay gradient,
/// brand block top-centered, tagline, then bottom copy + pill button.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.light,
    child: Scaffold(
      backgroundColor: const Color(0xFF081321),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Color(0xFF081321)),
          Image.asset(
            'assets/images/welcome_road.png',
            fit: BoxFit.cover,
            alignment: Alignment.center,
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0, .48, 1],
                colors: [
                  RoadColors.welcomeOverlayTop,
                  RoadColors.welcomeOverlayMid,
                  RoadColors.welcomeOverlayEnd,
                ],
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(32, 32, 32, 24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Column(
                          children: [
                            Text.rich(
                              const TextSpan(
                                children: [
                                  TextSpan(text: 'RoadGuard '),
                                  TextSpan(
                                    text: 'AI',
                                    style: TextStyle(
                                      color: RoadColors.welcomeAi,
                                    ),
                                  ),
                                ],
                              ),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 32,
                                height: 1.2,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -.6,
                              ),
                            ),
                            const SizedBox(height: 18),
                            const Text(
                              'Safer Roads. Smarter Journeys',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        Column(
                          children: [
                            const Text(
                              'Road-condition monitoring\nand traveler safety, in your pocket.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                key: const Key('welcome-get-started'),
                                onPressed: () =>
                                    context.go(BoardingPaths.onboarding),
                                child: const Text('Get Started'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
