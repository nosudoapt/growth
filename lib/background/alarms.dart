import 'dart:convert';

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';

import '../core/db.dart';
import '../notifications/notifs.dart';

/// Exact alarms, through android_alarm_manager_plus.
///
/// - 22:35 nightly check-in (exact, allow-while-idle, reschedule-on-reboot).
/// - 20:00 streak-nudge check (shows a notification only if nothing read).
///
/// Both callbacks are top-level functions (entry points for the background
/// isolate) and each one reschedules tomorrow's run, so deleted/rebooted/
/// force-stopped states self-heal on the next fire or app open.
class GrowthAlarms {
  const GrowthAlarms._();

  static const int checkinAlarmId = 11;
  static const int streakAlarmId = 12;

  static String defaultCheckinTime() => '22:35';
  static String defaultStreakCheckTime() => '20:00';

  /// Install/reschedule both exact alarms. Idempotent: same alarm ids are
  /// overwritten each call.
  static Future<void> scheduleAll() async {
    try {
      final hhmm = await Db.kvGet('checkin_time') ?? defaultCheckinTime();
      await AndroidAlarmManager.oneShotAt(
        nextAt(hhmm),
        checkinAlarmId,
        checkinAlarmFired,
        exact: true,
        allowWhileIdle: true,
        wakeup: true,
        rescheduleOnReboot: true,
      );
      final hhmm2 = await Db.kvGet('streak_check_time') ?? defaultStreakCheckTime();
      await AndroidAlarmManager.oneShotAt(
        nextAt(hhmm2),
        streakAlarmId,
        streakCheckFired,
        exact: true,
        allowWhileIdle: true,
        wakeup: true,
        rescheduleOnReboot: true,
      );
    } catch (_) {
      // Exact alarms can be revoked (Android 14+); in-app check-in remains.
    }
  }

  static DateTime nextAt(String hhmm) {
    final parts = hhmm.split(':');
    final h = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 22;
    final m = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 35;
    final now = DateTime.now();
    var at = DateTime(now.year, now.month, now.day, h, m);
    if (!at.isAfter(now)) at = at.add(const Duration(days: 1));
    return at;
  }
}

/// Nightly check-in fired at 22:35. Shows the quiet notification; reschedules
/// itself for tomorrow so the ritual keeps exact time.
@pragma('vm:entry-point')
Future<void> checkinAlarmFired() async {
  try {
    await Db.instance();
    await Notifications.init();
    await Notifications.showCheckIn();
    await GrowthAlarms.scheduleAll();
  } catch (_) {
    // Never alarm-crash a background isolate.
  }
}

/// 20:00 streak nudge: only when nothing was read today.
@pragma('vm:entry-point')
Future<void> streakCheckFired() async {
  try {
    await Db.instance();
    await Notifications.init();
    // LibraryRepo is imported lazily to keep the headless isolate light.
    final today = Db.today();
    final rows = await (await Db.instance()).query('reading_time',
        where: 'date = ?', whereArgs: [today], limit: 1);
    if (rows.isEmpty) {
      await Notifications.showStreakNudge();
    }
    await GrowthAlarms.scheduleAll();
  } catch (_) {}
}

/// Small helper used by the checkin flow to queue an LLM follow-up for when
/// connectivity returns (queued jobs are just kv flags, so idempotent).
Future<void> queueFollowUpRebuild(String date) async {
  await Db.kvSet('pending_rebuild', jsonEncode({'date': date, 'reason': 'followup'}));
}
