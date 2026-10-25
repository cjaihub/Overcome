import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/admin/admin_dashboard_screen.dart';
import '../../features/admin/admin_user_detail_screen.dart';
import '../../features/auth/phone_sign_in_screen.dart';
import '../../features/auth/redeem_code_screen.dart';
import '../../features/auth/welcome_screen.dart';
import '../../features/home/dashboard_screen.dart';
import '../../features/home/home_shell.dart';
import '../../features/library/ai_narrator_screen.dart';
import '../../features/library/audiobook_player_screen.dart';
import '../../features/library/book_detail_screen.dart';
import '../../features/library/library_screen.dart';
import '../../features/library/pdf_reader_screen.dart';
import '../../features/onboarding/onboarding_wizard_screen.dart';
import '../../features/onboarding/plan_generation_screen.dart';
import '../../features/progress/progress_screen.dart';
import '../../features/progress/template_form_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/subscription/paywall_screen.dart';
import '../services/firebase_providers.dart';
import 'splash_screen.dart';

/// Bridges Riverpod state into go_router's refresh mechanism.
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(Ref ref) {
    ref
      ..listen(authStateProvider, (_, _) => notifyListeners())
      ..listen(userDocProvider, (_, _) => notifyListeners())
      ..listen(isAdminProvider, (_, _) => notifyListeners());
  }
}

const _public = {'/welcome', '/sign-in'};

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final path = state.uri.path;
      final auth = ref.read(authStateProvider);
      if (auth.isLoading) return '/';
      if (auth.value == null) return _public.contains(path) ? null : '/welcome';

      final doc = ref.read(userDocProvider);
      if (doc.isLoading && !doc.hasValue) return path == '/' ? null : '/';
      final onboarded = doc.value?['onboardingCompletedAt'] != null;

      if (!onboarded) {
        const allowed = {'/onboarding', '/onboarding/plan', '/redeem', '/paywall'};
        return allowed.contains(path) ? null : '/onboarding';
      }
      if (path == '/' || path == '/onboarding' || _public.contains(path)) {
        return state.uri.queryParameters['next'] ?? '/home';
      }
      if (path.startsWith('/admin') && !ref.read(isAdminProvider)) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/welcome', builder: (_, _) => const WelcomeScreen()),
      GoRoute(
        path: '/sign-in',
        builder: (_, s) => PhoneSignInScreen(next: s.uri.queryParameters['next']),
      ),
      GoRoute(path: '/redeem', builder: (_, _) => const RedeemCodeScreen()),
      GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingWizardScreen()),
      GoRoute(path: '/onboarding/plan', builder: (_, _) => const PlanGenerationScreen()),
      GoRoute(
        path: '/paywall',
        builder: (_, s) => PaywallScreen(bookId: s.uri.queryParameters['book']),
      ),
      GoRoute(
        path: '/form/:id',
        builder: (_, s) => TemplateFormScreen(formId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/book/:id',
        builder: (_, s) => BookDetailScreen(bookId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/book/:id/read',
        builder: (_, s) => PdfReaderScreen(bookId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/book/:id/listen',
        builder: (_, s) => AudiobookPlayerScreen(bookId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/book/:id/narrator',
        builder: (_, s) => AiNarratorScreen(bookId: s.pathParameters['id']!),
      ),
      GoRoute(path: '/admin', builder: (_, _) => const AdminDashboardScreen()),
      GoRoute(
        path: '/admin/user/:uid',
        builder: (_, s) => AdminUserDetailScreen(uid: s.pathParameters['uid']!),
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => HomeShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: '/home', builder: (_, _) => const DashboardScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/progress', builder: (_, _) => const ProgressScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/library', builder: (_, _) => const LibraryScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen())],
          ),
        ],
      ),
    ],
  );
});
