# Growth

A calm, offline-first self-improvement app for Android. Full-screen feed of
thoughts and short reads, a nightly check-in at 22:35, a local LLM-generated
dashboard (your own API key, never exported), and a weekly plain-text
summary you can share.

- Runs entirely on the phone — no backend, no analytics, no ads, no trackers.
- Flutter 3.x, Material 3, Dart null safety, Android API 26+.
- Package name `com.growth.app`, app label `Growth`.

## Build

Open in your IDE of choice, or:

```bash
flutter pub get
flutter test
flutter build apk --release
```

CI: `.github/workflows/build.yml` builds `app-release.apk` on every push to
`main` and uploads it as the `growth-apk` artifact.

## Structure

```
lib/
  core/         theme, motion (reduce-motion aware), SQLite, app state
  seed/         thought bank (30), check-in questions (30), feeds (6), eval items (50)
  domain/       strict dashboard JSON schema + validator + extractor
  logic/        streaks, spend cap, no-repeat rotation, eval scoring, profile
  repos/        RSS, library (reads/likes/notes), check-ins, dashboard, eval,
                profile, feeds, exports, LLM service (Anthropic + OpenAI-compatible)
  notifications/ three Android channels + cold-start deep links
  background/   workmanager tasks (daily refresh, weekly rebuild) and the
                exact 22:35 check-in + 20:00 streak-nudge alarms
  ui/           feed, reader, nightly check-in, dashboard (6 tabs), settings,
                onboarding, eval
```

Fonts: Playfair Display (bundled, variable), Inter (bundled, variable), both
OFL-licensed (see `assets/OFL.txt`).

## Defaults worth knowing

- Nightly check-in 22:35 via `AlarmManager.setExactAndAllowWhileIdle`
  (through `android_alarm_manager_plus`), rescheduled after reboot; on
  Android 14+ the app links to the exact-alarm permission page when denied.
- Streak nudge 20:00, only when nothing was read that day.
- Story hooks: max 2/day at user-chosen times.
- Weekly rebuild Sunday 21:00 (workmanager, network-constrained, idempotent).
- Monthly spend cap stops all LLM calls when the estimate crosses the limit.
