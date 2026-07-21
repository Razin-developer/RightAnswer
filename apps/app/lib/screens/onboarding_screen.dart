import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/app_logo.dart';

const _onboardingSeenKey = 'right_answer_onboarding_seen';

Future<bool> hasSeenOnboarding() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_onboardingSeenKey) ?? false;
}

Future<void> markOnboardingSeen() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_onboardingSeenKey, true);
}

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onDone;

  const OnboardingScreen({super.key, required this.onDone});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _index = 0;

  static const _slides = [
    _OnboardingSlide(
      icon: Icons.menu_book_rounded,
      title: 'Study from your chapters',
      body:
          'Import textbook pages, split them into searchable chunks, and keep your study material organized by subject and chapter.',
      badges: [
        _SlideBadge(icon: Icons.bookmark_rounded, alignment: Alignment(0.9, -0.85)),
        _SlideBadge(icon: Icons.folder_copy_rounded, alignment: Alignment(-0.95, 0.8)),
      ],
    ),
    _OnboardingSlide(
      icon: Icons.forum_rounded,
      title: 'Ask with context',
      body:
          'Questions use your selected textbook content first, then the backend handles caching, reranking, and model routing.',
      badges: [
        _SlideBadge(icon: Icons.format_quote_rounded, alignment: Alignment(0.95, -0.7)),
        _SlideBadge(icon: Icons.auto_awesome_rounded, alignment: Alignment(-0.9, 0.85)),
      ],
    ),
    _OnboardingSlide(
      icon: Icons.fact_check_rounded,
      title: 'Create practice exams',
      body:
          'Generate MCQs, short answers, fill blanks, and mixed tests from the chapters you are revising.',
      badges: [
        _SlideBadge(icon: Icons.check_circle_rounded, alignment: Alignment(0.9, -0.8)),
        _SlideBadge(icon: Icons.timer_rounded, alignment: Alignment(-0.95, 0.75)),
      ],
    ),
    _OnboardingSlide(
      icon: Icons.cloud_sync_rounded,
      title: 'Sync and share',
      body:
          'Sign in to sync chats, share study sets, and continue across devices with the same backend.',
      badges: [
        _SlideBadge(icon: Icons.devices_rounded, alignment: Alignment(0.95, -0.75)),
        _SlideBadge(icon: Icons.link_rounded, alignment: Alignment(-0.9, 0.85)),
      ],
    ),
  ];

  Future<void> _finish() async {
    await markOnboardingSeen();
    if (mounted) widget.onDone();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isLast = _index == _slides.length - 1;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
          child: Column(
            children: [
              Row(
                children: [
                  const AppLogo(size: 38),
                  const SizedBox(width: 10),
                  Text(
                    'RightAnswer',
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                      color: color.onSurface,
                    ),
                  ),
                  const Spacer(),
                  TextButton(onPressed: _finish, child: const Text('Skip')),
                ],
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _slides.length,
                  onPageChanged: (value) => setState(() => _index = value),
                  itemBuilder: (context, index) => _SlideView(
                    slide: _slides[index],
                    isDark: isDark,
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _slides.length,
                  (index) => AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    width: index == _index ? 22 : 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: index == _index
                          ? color.primary
                          : color.outlineVariant,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: isLast
                      ? _finish
                      : () => _controller.nextPage(
                            duration: const Duration(milliseconds: 320),
                            curve: Curves.easeOutCubic,
                          ),
                  child: Text(isLast ? 'Get Started' : 'Next'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One onboarding page: an illustrative "hero" graphic built entirely from
/// theme-aware shapes/icons (no external assets), a headline, and body copy.
class _SlideView extends StatelessWidget {
  final _OnboardingSlide slide;
  final bool isDark;

  const _SlideView({required this.slide, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Cross-fades + gently slides in whenever the slide changes —
              // a subtle transition rather than a hard cut.
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 380),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.06),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: _SlideArt(
                  key: ValueKey(slide.title),
                  slide: slide,
                  isDark: isDark,
                ),
              ),
              const SizedBox(height: 40),
              Text(
                slide.title,
                textAlign: TextAlign.center,
                style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  slide.body,
                  textAlign: TextAlign.center,
                  style: text.bodyLarge?.copyWith(
                    color: color.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The illustrative hero for a slide: a soft gradient disc with a faint
/// concentric ring, the slide's primary icon in a raised circular badge at
/// its center, and 1-2 small floating "accent" badges scattered around it —
/// reads as a composed, finished illustration rather than a bare icon.
class _SlideArt extends StatelessWidget {
  final _OnboardingSlide slide;
  final bool isDark;

  const _SlideArt({super.key, required this.slide, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    const size = 220.0;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Soft gradient backdrop disc.
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  color.primaryContainer,
                  color.primaryContainer.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
          // Faint outer ring for depth.
          Container(
            width: size * 0.86,
            height: size * 0.86,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: color.outlineVariant.withValues(alpha: 0.7),
                width: 1.2,
              ),
            ),
          ),
          // Scattered decorative dots for texture.
          ..._decorativeDots(color),
          // Floating accent badges themed to the feature.
          for (final badge in slide.badges)
            Align(
              alignment: badge.alignment,
              child: _AccentBadge(icon: badge.icon, color: color),
            ),
          // Primary icon medallion.
          Container(
            width: 108,
            height: 108,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.primary,
              boxShadow: [
                BoxShadow(
                  color: color.primary.withValues(alpha: isDark ? 0.35 : 0.25),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Icon(slide.icon, size: 50, color: color.onPrimary),
          ),
        ],
      ),
    );
  }

  List<Widget> _decorativeDots(ColorScheme color) {
    const positions = [
      Alignment(-0.55, -0.95),
      Alignment(0.6, 0.95),
      Alignment(-0.98, -0.25),
      Alignment(0.98, 0.15),
    ];
    return [
      for (final pos in positions)
        Align(
          alignment: pos,
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.primary.withValues(alpha: 0.35),
            ),
          ),
        ),
    ];
  }
}

/// A small circular badge with a secondary icon, floating near the edge of
/// the hero medallion to reinforce what the slide's feature actually does
/// (e.g. citations, checkmarks, sync) without adding new colors.
class _AccentBadge extends StatelessWidget {
  final IconData icon;
  final ColorScheme color;

  const _AccentBadge({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.surface,
        border: Border.all(color: color.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: color.shadow.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Icon(icon, size: 18, color: color.primary),
    );
  }
}

class _OnboardingSlide {
  final IconData icon;
  final String title;
  final String body;
  final List<_SlideBadge> badges;

  const _OnboardingSlide({
    required this.icon,
    required this.title,
    required this.body,
    this.badges = const [],
  });
}

class _SlideBadge {
  final IconData icon;
  final Alignment alignment;

  const _SlideBadge({required this.icon, required this.alignment});
}
