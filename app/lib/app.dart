import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/layout/desktop.dart';
import 'core/providers.dart';
import 'core/theme/nur_theme.dart';
import 'features/chat/chat_screen.dart';
import 'features/memory/memory_screen.dart';
import 'features/nas/nas_screen.dart';
import 'features/nas/onboarding_screen.dart';
import 'features/nas/pair_approvals.dart';
import 'features/providers/providers_screen.dart';
import 'features/shell/app_shell.dart';
import 'features/shell/settings_screen.dart';
import 'features/tools/tools_screen.dart';
import 'features/voice/voice_call_screen.dart';
import 'features/voice/voice_settings_screen.dart';

/// No transition on desktop (switching chats is instant), the Material one on phones.
Page<void> _page(BuildContext c, GoRouterState s, Widget child) =>
    isDesktopLayout(c) ? NoTransitionPage<void>(key: s.pageKey, child: child) : MaterialPage<void>(key: s.pageKey, child: child);

/// Chats, NAS and settings live in a [ShellRoute]: on desktop the shell keeps the sidebar mounted while the
/// main area changes; on phones the shell is a pass-through. Calls and onboarding stay full screen.
final routerProvider = Provider<GoRouter>((ref) => GoRouter(
      navigatorKey: rootNavigatorKey,
      initialLocation: '/',
      routes: [
        ShellRoute(
          builder: (c, s, child) => AppShell(location: s.uri.path, child: child),
          routes: [
            GoRoute(path: '/', pageBuilder: (c, s) => _page(c, s, const ChatScreen())),
            GoRoute(path: '/chat/:id', pageBuilder: (c, s) => _page(c, s, ChatScreen(chatId: s.pathParameters['id']))),
            GoRoute(path: '/nas', pageBuilder: (c, s) => _page(c, s, const NasScreen())),
            GoRoute(path: '/settings', pageBuilder: (c, s) => _page(c, s, const SettingsScreen()), routes: [
              GoRoute(path: 'providers', pageBuilder: (c, s) => _page(c, s, const ProvidersScreen())),
              GoRoute(path: 'memory', pageBuilder: (c, s) => _page(c, s, const MemoryScreen())),
              GoRoute(path: 'tools', pageBuilder: (c, s) => _page(c, s, const ToolsScreen())),
              GoRoute(path: 'voice', pageBuilder: (c, s) => _page(c, s, const VoiceSettingsScreen())),
            ]),
          ],
        ),
        GoRoute(path: '/call', parentNavigatorKey: rootNavigatorKey, builder: (c, s) => VoiceCallScreen(chatId: s.uri.queryParameters['chat'])),
        GoRoute(path: '/onboarding', parentNavigatorKey: rootNavigatorKey, builder: (c, s) => const OnboardingScreen()),
      ],
    ));

/// Setting `theme_mode`: 'system', 'light' or 'dark'.
final themeModeProvider = StreamProvider<ThemeMode>((ref) => ref.watch(dbProvider).watchSetting('theme_mode').map((v) => switch (v) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    }));

/// Setting `locale`: 'ar' or 'en', null follows the device.
final localeProvider = StreamProvider<Locale?>((ref) => ref.watch(dbProvider).watchSetting('locale').map((v) => v == null || v.isEmpty ? null : Locale(v)));

class NurApp extends ConsumerWidget {
  const NurApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Nur',
      debugShowCheckedModeBanner: false,
      theme: NurTheme.light(),
      darkTheme: NurTheme.dark(),
      themeMode: ref.watch(themeModeProvider).value ?? ThemeMode.system,
      locale: ref.watch(localeProvider).value,
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
      routerConfig: ref.watch(routerProvider),
      builder: (context, child) => PairApprovalListener(navigatorKey: rootNavigatorKey, child: child ?? const SizedBox()),
    );
  }
}
