import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/brand.dart';
import 'core/router/app_router.dart';
import 'core/security/screen_security.dart';
import 'core/services/analytics_service.dart';
import 'core/services/push_service.dart';
import 'features/coach/wake_word_service.dart';
import 'features/settings/settings_controller.dart';
import 'features/tracker/usage_sync.dart';
import 'firebase_options.dart';

@pragma('vm:entry-point')
Future<void> _onBackgroundMessage(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  if (DefaultFirebaseOptions.currentPlatform.apiKey == 'REPLACE_ME') {
    // Built before `flutterfire configure`: show a clear screen, don't crash.
    runApp(const SetupRequiredApp());
    return;
  }
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // App Check: only genuine, untampered builds can reach Firestore,
  // Storage and Functions.
  await FirebaseAppCheck.instance.activate(
    providerAndroid: kDebugMode ? const AndroidDebugProvider() : const AndroidPlayIntegrityProvider(),
    providerApple: kDebugMode ? const AppleDebugProvider() : const AppleAppAttestWithDeviceCheckFallbackProvider(),
  );
  FirebaseMessaging.onBackgroundMessage(_onBackgroundMessage);

  await ScreenSecurity.instance.init();
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.overcome.audio',
    androidNotificationChannelName: 'Audiobook playback',
    androidNotificationOngoing: true,
  );

  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
  container.read(analyticsProvider).start();
  PushService(container.read(routerProvider)).start();
  container.read(usageSyncProvider).start();
  container.read(wakeWordProvider).start();

  runApp(UncontrolledProviderScope(container: container, child: const OvercomeApp()));
}

class SetupRequiredApp extends StatelessWidget {
  const SetupRequiredApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.dark(),
    home: Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(BrandAssets.stacked(Brightness.dark), width: 200),
              const SizedBox(height: 24),
              const Text(
                'This build isn\'t connected to a Firebase project yet.\n'
                'Run `flutterfire configure` and rebuild.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
