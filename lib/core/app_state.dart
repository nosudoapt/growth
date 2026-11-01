import 'package:flutter/material.dart';

/// Global navigator key for deep links.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Theme toggle shared between Settings and the app shell.
final ValueNotifier<ThemeMode> appTheme =
    ValueNotifier<ThemeMode>(ThemeMode.dark);
