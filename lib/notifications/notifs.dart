import 'dart:convert';

import 'package:flutter/material.dart' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../core/db.dart';

/// Four Android channels (three feature channels + the nightly check-in).
/// Tapping any notification deep-links via a payload string.
class Notifications {
  const Notifications._();

  static final _plugin = FlutterLocalNotificationsPlugin();

  static const String channelStoryHook = 'story_hook';
  static const String channelStreakNudge = 'streak_nudge';
  static const String channelDashboardHighlight = 'dashboard_highlight';
  static const String channelCheckin = 'check_in';

  static void Function(String payload)? onPayload;

  /// Idempotent init: creates/replaces all channels, wires taps.
  static Future<void> init() async {
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('ic_notification'),
    );
    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (NotificationResponse r) {
        final p = r.payload;
        if (p != null && p.isNotEmpty) onPayload?.call(p);
      },
    );
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(_channelSpec(
        channelStoryHook, 'Story hook', 'One curiosity line for a new read',
        importance: Importance.defaultImportance, vibrate: false));
    await androidPlugin?.createNotificationChannel(_channelSpec(
        channelStreakNudge, 'Streak nudge',
        'A gentle 8 PM reminder when nothing was read today',
        importance: Importance.high, vibrate: true));
    await androidPlugin?.createNotificationChannel(_channelSpec(
        channelDashboardHighlight, 'Dashboard highlight', 'One weekly insight',
        importance: Importance.high, vibrate: true));
    await androidPlugin?.createNotificationChannel(_channelSpec(
        channelCheckin, 'Nightly check-in', 'The 22:35 ritual',
        importance: Importance.max, vibrate: true));
  }

  /// User toggles POST_NOTIFICATIONS (Android 13+) via the system ask in
  /// onboarding; showing notifications is silent-fails otherwise.
  static Future<void> showCheckIn() async {
    try {
      await _plugin.show(
        id: 1,
        title: 'Tonight’s check-in',
        body: 'Two minutes, one question, three sliders.',
        notificationDetails: NotificationDetails(
          android: _channel(channelCheckin, 'Nightly check-in',
              'The end-of-day ritual',
              importance: Importance.max, vibrate: true),
        ),
        payload: RoutePayloads.checkin,
      );
    } catch (_) {
      // Notifications denied or channel blocked; the in-app entry remains.
    }
  }

  static Future<void> showStreakNudge() async {
    try {
      await _plugin.show(
        id: 2,
        title: 'Your reading streak',
        body: 'Nothing read today yet — one small read keeps the streak alive.',
        notificationDetails: NotificationDetails(
          android: _channel(channelStreakNudge, 'Streak nudge',
              'A gentle reminder when nothing was read today',
              importance: Importance.high, vibrate: true),
        ),
        payload: RoutePayloads.feed,
      );
    } catch (_) {}
  }

  static Future<void> showDashboardHighlight(String insight) async {
    try {
      await _plugin.show(
        id: 3,
        title: 'This week’s insight',
        body: insight,
        notificationDetails: NotificationDetails(
          android: _channel(channelDashboardHighlight, 'Dashboard highlight',
              'One weekly insight',
              importance: Importance.high, vibrate: true),
        ),
        payload: RoutePayloads.dashboard,
      );
    } catch (_) {}
  }

  /// Story-hook notifications: max 2/day at user-chosen times, repeated
  /// daily. `alarmClock` mode works even when SCHEDULE_EXACT_ALARM is denied.
  static Future<void> scheduleStoryHooks(List<String> hhmm) async {
    await _plugin.cancel(id: 101);
    await _plugin.cancel(id: 102);
    const lines = [
      ('Something to think about', 'A new read is waiting for you tonight.'),
      ('One more, if you like', 'A short read worth two minutes.'),
    ];
    final details = NotificationDetails(
      android: _channel(channelStoryHook, 'Story hook',
          'One curiosity line for a new read',
          importance: Importance.defaultImportance, vibrate: false),
    );
    var shown = 0;
    for (final h in hhmm) {
      if (shown >= 2) break;
      final parsed = _parseTime(h);
      if (parsed == null) continue;
      final now = tz.TZDateTime.now(tz.local);
      var when = tz.TZDateTime(
          tz.local, now.year, now.month, now.day, parsed.$1, parsed.$2);
      if (!when.isAfter(now)) {
        when = when.add(const Duration(days: 1));
      }
      await _plugin.zonedSchedule(
        id: 101 + shown,
        title: lines[shown].$1,
        body: lines[shown].$2,
        scheduledDate: when,
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.alarmClock,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: RoutePayloads.feed,
      );
      shown++;
    }
  }

  static (int, int)? _parseTime(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
      return null;
    }
    return (h, m);
  }

  static Future<void> cancelStoryHooks() async {
    await _plugin.cancel(id: 101);
    await _plugin.cancel(id: 102);
  }

  /// Cold-start deep link: was the app launched by a notification tap?
  static Future<String?> launchPayload() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details == null || !details.didNotificationLaunchApp) return null;
    return details.notificationResponse?.payload;
  }
}

/// Payload strings that the root widget maps to screens.
class RoutePayloads {
  const RoutePayloads._();
  static const String feed = 'feed';
  static const String checkin = 'checkin';
  static const String dashboard = 'dashboard';
}

AndroidNotificationDetails _channel(
  String id,
  String name,
  String desc, {
  required Importance importance,
  required bool vibrate,
}) {
  return AndroidNotificationDetails(
    id,
    name,
    channelDescription: desc,
    importance: importance,
    priority: Priority.high,
    color: const Color(0xFFF5C04A),
    category: AndroidNotificationCategory.reminder,
    enableVibration: vibrate,
    playSound: true,
  );
}

/// Channel *specification* for createNotificationChannel (a different type
/// than AndroidNotificationDetails in v22).
AndroidNotificationChannel _channelSpec(
  String id,
  String name,
  String desc, {
  required Importance importance,
  required bool vibrate,
}) {
  return AndroidNotificationChannel(
    id,
    name,
    description: desc,
    importance: importance,
    playSound: false,
    enableVibration: vibrate,
  );
}

/// Settings-facing helper: user-chosen hook times (max 2), scheduled daily.
class NotifSettings {
  const NotifSettings._();

  static Future<List<String>> hookTimes() async {
    final raw = await Db.kvGet('hook_times');
    if (raw == null) return <String>['08:30'];
    try {
      final l = jsonDecode(raw) as List;
      return l.whereType<String>().take(2).toList();
    } catch (_) {
      return <String>['08:30'];
    }
  }

  static Future<void> setHookTimes(List<String> times) async {
    await Db.kvSet('hook_times', jsonEncode(times.take(2).toList()));
    await Notifications.scheduleStoryHooks(times.take(2).toList());
  }
}
