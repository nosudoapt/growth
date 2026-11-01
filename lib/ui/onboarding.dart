import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart' as intent_flags;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/theme.dart';
import 'widgets.dart';

/// Three onboarding pages: what the app does, notification permission (with
/// an explanation before the system prompt), and battery-optimization
/// exclusion with a button that opens the settings page. Shown once.
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final PageController _c = PageController();
  int _page = 0;

  void _goNext() {
    if (_page >= 2) {
      widget.onDone();
      return;
    }
    _c.nextPage(
        duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
  }

  Future<void> _askNotifications() async {
    // Explanation first (the page itself), then the system prompt.
    await Permission.notification.request();
    if (mounted) {
      _goNext();
    }
  }

  Future<void> _excludeBattery() async {
    // Opens Android's battery-optimization page; users exclude Growth there
    // so the 22:35 ritual fires on time.
    final intent = AndroidIntent(
      action: 'android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS',
      flags: <int>[intent_flags.Flag.FLAG_ACTIVITY_NEW_TASK],
    );
    try {
      await intent.launch();
    } catch (_) {
      // The setting page can be missing on vendor skins; proceed regardless.
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GCol.bg,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _c,
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  _Intro(
                      headline: 'Growth is a quiet corner of your day.',
                      body:
                          'A daily thought, short reads you choose, and one '
                          'small check-in each night. Your data stays on your '
                          'phone: no cloud account, no ads, no trackers. You '
                          'can bring your own AI key later, or none at all.'),
                  _Intro(
                      headline: 'Two gentle reminders, nothing more.',
                      body:
                          'Allow notifications so Growth can send a story '
                          'hook once or twice a day at times you choose, a '
                          'streak nudge at 8 PM only when nothing was read, '
                          'and the nightly check-in at 22:35 (you can skip '
                          'any night). The next page asks the system for '
                          'permission.'),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('One last thing: precise alarms matter',
                          textAlign: TextAlign.left,
                          style: TextStyle(
                              fontFamily: 'Playfair Display',
                              fontSize: 30,
                              height: 1.25,
                              color: GCol.text)),
                      const SizedBox(height: 14),
                      Wrap(children: [
                        const Text(
                            'Android delays background apps to save battery. '
                            'To make sure the 22:35 nightly check-in fires on '
                            'time after reboots, exclude Growth from battery '
                            'optimization: tap below, find Growth, choose Allow.',
                            style: TextStyle(
                                fontSize: 17, height: 1.5, color: GCol.muted)),
                      ]),
                      const SizedBox(height: 20),
                      BigButton(
                        label: 'Open battery settings',
                        secondary: true,
                        onTap: _excludeBattery,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Column(
                children: [
                  Row(
                    children: [
                      for (var i = 0; i < 3; i++)
                        Container(
                          width: 10,
                          height: 10,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i == _page
                                ? GCol.gold
                                : GCol.muted.withValues(alpha: .4),
                          ),
                        ),
                      const Spacer(),
                      TextButton(
                        onPressed: widget.onDone,
                        child: const Text('Skip',
                            style: TextStyle(fontSize: 16, color: GCol.muted)),
                      ),
                    ],
                  ),
                  BigButton(
                    label: _page == 2 ? 'Start using Growth' : 'Next',
                    onTap: _page == 1 ? _askNotifications : _goNext,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro({required this.headline, required this.body});

  final String headline;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(headline,
            style: const TextStyle(
                fontFamily: 'Playfair Display',
                fontSize: 30,
                height: 1.25,
                color: GCol.text)),
        const SizedBox(height: 14),
        Text(body,
            style: const TextStyle(fontSize: 17, height: 1.55, color: GCol.muted)),
      ],
    );
  }
}
