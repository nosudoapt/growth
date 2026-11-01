import 'package:workmanager/workmanager.dart';

import '../core/db.dart';
import '../domain/dashboard.dart' show DashboardData;
import '../repos/dashboard.dart';
import '../repos/feeds.dart';
import '../repos/llm.dart';
import '../repos/profile.dart';
import '../repos/rss.dart';
import '../notifications/notifs.dart';

/// Background task names (passed to the dispatcher).
const String kTaskDailyRefresh = 'growth.daily_feed_refresh';
const String kTaskWeeklyRebuild = 'growth.weekly_rebuild';

/// Called by WorkManager when a background task starts. Every task here is
/// idempotent: Android may delay or repeat them, and each run checks a
/// date-stamp in kv before doing real work.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    await Db.instance();
    await Notifications.init();
    switch (task) {
      case kTaskDailyRefresh:
        await dailyFeedRefresh();
        return true;
      case kTaskWeeklyRebuild:
        await weeklyRebuild();
        return true;
      case 'growth.followup_rebuild':
        // Queued after an offline check-in completes.
        await runPendingRebuild();
        return true;
      default:
        return true;
    }
  });
}

/// One-time WorkManager wiring with the dispatcher above.
Future<void> workmanagerInit() =>
    Workmanager().initialize(callbackDispatcher);

/// Once daily (only when online). Also flushes any pending LLM rebuilds.
/// Idempotent by day-stamp.
Future<void> dailyFeedRefresh() async {
  final today = Db.today();
  if (await Db.kvGet('last_feed_refresh') == today) return;
  final feeds = await FeedsRepo.all();
  final rss = RssRepo();
  var stored = 0;
  for (final f in feeds) {
    if (f.url.isEmpty) continue;
    stored += await rss.fetchAndCache(f.url, f.topic);
  }
  await Db.kvSet('last_feed_refresh', today);
  await runPendingRebuild();
}

/// Weekly full rebuild (Sunday 9 PM when scheduled). Applies the fresh
/// profile and refreshes dashboards from the last 7 days.
Future<void> weeklyRebuild() async {
  final weekKey = weekStamp();
  if (await Db.kvGet('last_weekly_rebuild') == weekKey) return;
  await ProfileRepo.refresh();
  await profileDrivenRebuild();
  await Db.kvSet('last_weekly_rebuild', weekKey);
}

/// Runs the check-in → dashboard → highlight pipeline when the LLM is
/// configured and the interacted spend cap allows it.
Future<void> runPendingRebuild() async {
  if (await Db.kvGet('pending_rebuild') == null) return;
  await profileDrivenRebuild();
}

/// Builds the dashboard via the LLM, falls back to the last good result on
/// validation failure, and posts the weekly highlight notification.
Future<void> profileDrivenRebuild() async {
  final llm = LlmService();
  final LlmConfig config;
  try {
    config = await llm.loadConfig();
  } catch (_) {
    return;
  }
  if (!config.apiKeySet) return;
  final profile = await ProfileRepo.current();
  final weekly = DateTime.now().weekday == DateTime.sunday;
  try {
    await DashboardRepo.rebuild(
        llm: llm, config: config, profileText: profile, weekly: weekly);
  } on SpendBlocked {
    return; // calm stop; usage estimate already visible in Settings
  } catch (_) {
    return;
  }
  await Db.kvDelete('pending_rebuild');

  // Weekly dashboard highlight (same build).
  if (await Db.kvGet('last_highlight_week') != weekStamp()) {
    final dash = await DashboardRepo.current();
    final insight = dash == null
        ? 'Your dashboard is ready.'
        : _bestInsight(dash);
    try {
      await Notifications.showDashboardHighlight(insight);
      await Db.kvSet('last_highlight_week', weekStamp());
    } catch (_) {
      // Notifications can be denied; all data still stored locally.
    }
  }
}

String _bestInsight(DashboardData dash) {
  final s = dash.weeklySuggestion.trim();
  if (s.isNotEmpty) return s;
  final w = dash.winOfTheWeek.trim();
  if (w.isNotEmpty) return w;
  return 'Take a look at your weekly dashboard.';
}

String weekStamp() {
  final n = DateTime.now();
  final sunday = n.subtract(Duration(days: n.weekday % 7));
  return '${sunday.year}-${sunday.month}-${sunday.day}';
}

/// Registration helper (called once at app start).
Future<void> registerBackgroundTasks() async {
  final now = DateTime.now();
  var nextRun = now;
  while (nextRun.weekday != DateTime.sunday ||
      nextRun.hour < 21) {
    nextRun = nextRun.add(const Duration(hours: 1));
  }
  final delay = nextRun.difference(now);
  await Workmanager().registerPeriodicTask(
    kTaskWeeklyRebuild,
    kTaskWeeklyRebuild,
    frequency: const Duration(days: 7),
    initialDelay: delay,
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    backoffPolicy: BackoffPolicy.exponential,
    backoffPolicyDelay: const Duration(minutes: 15),
  );
  await Workmanager().registerPeriodicTask(
    kTaskDailyRefresh,
    kTaskDailyRefresh,
    frequency: const Duration(hours: 24),
    initialDelay: const Duration(hours: 6),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    backoffPolicy: BackoffPolicy.exponential,
    backoffPolicyDelay: const Duration(minutes: 15),
  );
}
