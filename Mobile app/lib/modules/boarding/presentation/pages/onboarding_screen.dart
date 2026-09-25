import 'package:roadguard_ai/core/routes/route_paths.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:roadguard_ai/core/theme/app_theme.dart';
import 'package:roadguard_ai/modules/boarding/routes/boarding_paths.dart';

/// Reference onboarding: blue illustration card, 26px heading, muted copy,
/// progress dots (10px idle / 31px current, welcome blue), block pill button.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pages = PageController();
  int _index = 0;
  static const _titles = [
    'Know the road ahead',
    'Plan your journey',
    'Stay informed',
  ];
  static const _descriptions = [
    'Explore places and view confirmed reports on a live map.',
    'Review directions before you travel or start with a suggested route.',
    'Receive brief route warnings and find them later in your alert history.',
  ];
  static const _glyphs = [
    Icons.my_location_rounded,
    Icons.diamond_outlined,
    Icons.warning_amber_rounded,
  ];
  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF6F9FA),
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxHeight < 560;
          final illHeight = (constraints.maxHeight * (compact ? .3 : .38))
              .clamp(130.0, 300.0);
          return Column(
            children: [
              Expanded(
                child: PageView.builder(
                  controller: _pages,
                  itemCount: 3,
                  onPageChanged: (value) => setState(() => _index = value),
                  // Each page scrolls, so large text sizes or landscape phones
                  // never overflow — the content just becomes scrollable.
                  itemBuilder: (context, index) => SingleChildScrollView(
                    key: ValueKey('onboarding-page-$index'),
                    padding: const EdgeInsets.fromLTRB(25, 36, 25, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Illustration(glyph: _glyphs[index], height: illHeight),
                        const SizedBox(height: 26),
                        Text(
                          _titles[index],
                          style: const TextStyle(
                            fontSize: 26,
                            height: 1.18,
                            fontWeight: FontWeight.w700,
                            color: RoadColors.ink,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _descriptions[index],
                          style: const TextStyle(
                            color: RoadColors.muted,
                            fontSize: 15,
                            height: 1.45,
                          ),
                        ),
                        if (compact) ...[
                          const SizedBox(height: 18),
                          _controls(context, inPage: true),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              if (!compact) _controls(context),
            ],
          );
        },
      ),
    ),
  );

  Widget _controls(BuildContext context, {bool inPage = false}) => Padding(
    padding: EdgeInsets.fromLTRB(inPage ? 0 : 25, 12, inPage ? 0 : 25, 22),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            for (var i = 0; i < 3; i++)
              AnimatedContainer(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 220),
                width: _index == i ? 31 : 10,
                height: 6,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: _index == i
                      ? RoadColors.blueBright
                      : RoadColors.progressTrack,
                  borderRadius: BorderRadius.circular(7),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            key: const Key('onboarding-next'),
            onPressed: () {
              if (_index == 2) {
                context.go(BoardingPaths.permissions);
              } else {
                _pages.nextPage(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                );
              }
            },
            child: Text(_index == 2 ? 'Get started' : 'Continue →'),
          ),
        ),
        if (_index > 0) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: _GhostButton(
              key: const Key('onboarding-back'),
              onPressed: () => _pages.previousPage(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 250),
                curve: Curves.easeOut,
              ),
              child: const Text('Back'),
            ),
          ),
        ],
      ],
    ),
  );
}

/// Reference illustration: welcome-blue gradient, 27px radius,
/// centered 100px blue glyph, sized from screen height (42% in the HTML).
class _Illustration extends StatelessWidget {
  const _Illustration({required this.glyph, required this.height});
  final IconData glyph;
  final double height;
  @override
  Widget build(BuildContext context) => Container(
    height: height,
    width: double.infinity,
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          RoadColors.blueIllustrationStart,
          RoadColors.blueIllustrationEnd,
        ],
      ),
      borderRadius: BorderRadius.all(Radius.circular(27)),
    ),
    alignment: Alignment.center,
    child: Icon(glyph, size: 100, color: RoadColors.welcomeButton),
  );
}

/// Reference ghost pill: #eff3f4 background, #26404a label, 25px radius.
class _GhostButton extends StatelessWidget {
  const _GhostButton({required this.child, this.onPressed, super.key});
  final Widget child;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => FilledButton(
    key: key,
    style: FilledButton.styleFrom(
      backgroundColor: RoadColors.ghostBg,
      foregroundColor: RoadColors.ghostInk,
      elevation: 0,
    ),
    onPressed: onPressed,
    child: child,
  );
}
