import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import 'background/alarms.dart';
import 'background/tasks.dart';
import 'core/app_state.dart';
import 'core/db.dart';
import 'core/theme.dart';
import 'ui/root.dart';

Future<void> main() async {
  await runStartup();

  runApp(const ProviderScope(
    child: GrowthApp(),
  ));
}

/// Separated so tests can skip real background work.
Future<void> runStartup() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Timezones (needed by flutter_local_notifications).
  tzdata.initializeTimeZones();

  // Local database first: the app must open offline-first.
  await Db.instance();

  // Restore the theme preference early so first paint is right.
  final light = await Db.kvGet('light_mode');
  appTheme.value = light == '1' ? ThemeMode.light : ThemeMode.dark;

  // Background work: workmanager + exact alarms (best effort).
  try {
    await workmanagerInit();
    await registerBackgroundTasks();
  } catch (_) {
    // The app still works fully offline without background registration.
  }
  try {
    await AndroidAlarmManager.initialize();
    await GrowthAlarms.scheduleAll();
  } catch (_) {
    // Exact alarms may be denied (Android 14+); in-app check-in remains.
  }
}

/// The Material app shell.
class GrowthApp extends StatelessWidget {
  const GrowthApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: appTheme,
      builder: (context, mode, _) => MaterialApp(
        title: 'Growth',
        debugShowCheckedModeBanner: false,
        navigatorKey: navigatorKey,
        theme: buildGrowthTheme(false),
        darkTheme: buildGrowthTheme(true),
        themeMode: mode,
        home: const GrowthRoot(),
      ),
    );
  }
}
