import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show HapticFeedback;
import 'package:intl/intl.dart';

import '../core/db.dart';
import '../notifications/notifs.dart';
import '../repos/export.dart';
import 'checkin.dart';
import 'dashboard.dart';
import 'eval_screen.dart';
import 'feed.dart';
import 'onboarding.dart';
import 'reader.dart';
import 'settings.dart';

/// Bottom-nav shell with deep-link routing. Tabs: Feed, Dashboard,
/// Check-in (nightly), Settings. Eval and Reader push above the shell.
class GrowthRoot extends StatefulWidget {
  const GrowthRoot({super.key});

  @override
  State<GrowthRoot> createState() => _GrowthRootState();
}

class _GrowthRootState extends State<GrowthRoot>
    with WidgetsBindingObserver {
  int _index = 0;
  bool _onboarded = true;
  bool _weeklyExportReady = false;

  final _pages = const <Widget>[
    FeedPage(),
    DashboardPage(),
    CheckinPage(),
    SettingsPage(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    // Channels + notification tap routing.
    await _initNotifications();
    // First-run onboarding gate.
    final done = await Db.kvGet('onboarding_done');
    final weekly = await shouldOfferWeeklyExport();
    if (!mounted) return;
    setState(() {
      _onboarded = done == '1';
      _weeklyExportReady = weekly;
    });
    if (!_onboarded) return;
    // Cold-start deep link from a notification tap.
    final payload = await Notifications.launchPayload();
    if (payload != null) _routePayload(payload);
    // Sunday: offer the weekly export share.
    if (_weeklyExportReady && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(seconds: 6),
        content: const Text('Your week summary is ready to share.'),
        action: SnackBarAction(
          label: 'Share',
          onPressed: () async {
            try {
              await Exports.shareWeeklySummary();
            } catch (_) {}
          },
        ),
      ));
    }
  }

  Future<void> _initNotifications() async {
    await Notifications.init();
    Notifications.onPayload = _routePayload;
  }

  void _routePayload(String payload) {
    if (!mounted) return;
    switch (payload) {
      case RoutePayloads.checkin:
        setState(() => _index = 2);
        break;
      case RoutePayloads.dashboard:
        setState(() => _index = 1);
        break;
      case 'eval':
        Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const EvalPage()));
        break;
      default:
        setState(() => _index = payload.startsWith('reader:') ? 0 : 0);
        final id = int.tryParse(payload.replaceFirst('reader:', ''));
        if (id != null && payload.startsWith('reader:')) {
          Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ReaderPage(readId: id)));
        }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Auto-advance pauses handled inside the feed; nothing needed here.
  }

  @override
  void dispose() {
    Notifications.onPayload = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      resizeToAvoidBottomInset: false,
      body: _onboarded
          ? IndexerStack(pages: _pages, index: _index)
          : OnboardingPage(
              onDone: () async {
                await Db.kvSet('onboarding_done', '1');
                if (!mounted) return;
                setState(() => _onboarded = true);
              },
            ),
      bottomNavigationBar: _onboarded
          ? NavigationBar(
              height: 68,
              selectedIndex: _index,
              onDestinationSelected: (i) {
                setState(() => _index = i);
                HapticFeedback.selectionClick();
              },
              destinations: const [
                NavigationDestination(
                    icon: Icon(Icons.layers_outlined), label: 'Feed'),
                NavigationDestination(
                    icon: Icon(Icons.auto_graph_outlined), label: 'Dashboard'),
                NavigationDestination(
                    icon: Icon(Icons.nightlight_round), label: 'Tonight'),
                NavigationDestination(
                    icon: Icon(Icons.settings_outlined), label: 'Settings'),
              ],
            )
          : null,
    );
  }
}

class IndexerStack extends StatelessWidget {
  const IndexerStack({super.key, required this.pages, required this.index});

  final List<Widget> pages;
  final int index;

  @override
  Widget build(BuildContext context) {
    return IndexedStack(index: index, children: [
      for (final p in pages) p,
    ]);
  }
}

/// Formats "Last updated" stamps used across the dashboard tabs.
String lastUpdatedLabel(DateTime? time) {
  if (time == null) return 'Never updated';
  return 'Last updated ${DateFormat('EEE, HH:mm').format(time)}';
}
