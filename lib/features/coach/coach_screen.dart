import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/services/firebase_providers.dart';
import '../../core/theme/brand.dart';
import '../../core/widgets/animated_step_icon.dart';
import '../../core/widgets/aurora_background.dart';
import '../../core/widgets/common.dart';
import '../settings/settings_controller.dart';
import '../tracker/guardian_controller.dart';
import 'coach_repository.dart';
import 'voice_engine.dart';
import 'wake_word_service.dart';

/// Opens web links in an in-app browser tab (Custom Tabs / SFSafariViewController).
Future<void> openInAppTab(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.inAppBrowserView);

/// Chat with the AI coach: text, voice (with emotion cues), photos, links
/// that open in in-app tabs, and actions that jump straight to app screens.
class CoachScreen extends ConsumerStatefulWidget {
  const CoachScreen({super.key, this.startVoice = false});
  final bool startVoice;

  @override
  ConsumerState<CoachScreen> createState() => _CoachScreenState();
}

class _CoachScreenState extends ConsumerState<CoachScreen> {
  final _input = TextEditingController();
  final _tts = FlutterTts();
  Uint8List? _image;
  bool _sending = false;
  bool _listening = false;
  bool _speakReplies = true;
  String _partial = '';
  double _level = 0;
  String? _lastSpokenId;

  static const _suggestions = [
    'I\'m having an urge right now',
    'How did my screen time look today?',
    'Help me plan a phone-free evening',
    'Recommend a book for me',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.startVoice) WidgetsBinding.instance.addPostFrameCallback((_) => _talk());
  }

  @override
  void dispose() {
    _tts.stop();
    _input.dispose();
    ref.read(wakeWordProvider).resume();
    super.dispose();
  }

  String get _assistantName => ref.read(guardianProvider).assistantName;

  Future<void> _send({String? text, VoiceSample? voice}) async {
    final body = (text ?? _input.text).trim();
    if (body.isEmpty && _image == null) return;
    setState(() => _sending = true);
    final image = _image;
    _input.clear();
    setState(() => _image = null);
    try {
      await ref
          .read(coachRepositoryProvider)
          .send(text: body, image: image, voice: voice, assistantName: _assistantName);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _talk() async {
    if (_listening) {
      await ref.read(voiceEngineProvider).stop();
      return;
    }
    if (!await Permission.microphone.request().isGranted) {
      if (mounted) showError(context, 'Microphone permission is needed for voice.');
      return;
    }
    ref.read(wakeWordProvider).pause();
    await _tts.stop();
    HapticFeedback.mediumImpact();
    setState(() {
      _listening = true;
      _partial = '';
    });
    final sample = await ref
        .read(voiceEngineProvider)
        .capture(
          onPartial: (p) => mounted ? setState(() => _partial = p) : null,
          onLevel: (l) => mounted ? setState(() => _level = l) : null,
        );
    if (!mounted) return;
    setState(() => _listening = false);
    if (sample != null) await _send(text: sample.transcript, voice: sample);
  }

  Future<void> _pickImage(ImageSource source) async {
    final file = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 80);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() => _image = bytes);
  }

  /// Speaks new assistant replies with prosody matched to the user's mood.
  Future<void> _maybeSpeak(CoachMessage m) async {
    if (!_speakReplies || m.isUser || m.id == _lastSpokenId) return;
    _lastSpokenId = m.id;
    if (DateTime.now().difference(m.at) > const Duration(minutes: 1)) return;
    final speed = ref.read(settingsProvider).voiceSpeed;
    await _tts.setSpeechRate(((m.voiceRate ?? 0.5) * speed).clamp(0.2, 1.0));
    await _tts.setPitch((m.voicePitch ?? 1.0).clamp(0.6, 1.4));
    await _tts.speak(m.text.replaceAll(RegExp(r'https?://\S+'), 'the link'));
  }

  void _runAction(CoachAction a) {
    HapticFeedback.selectionClick();
    if (a.type == 'url') {
      openInAppTab(a.target);
    } else if (a.target.startsWith('/')) {
      context.push(a.target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(coachMessagesProvider);
    final guardian = ref.watch(guardianProvider);
    final latestEmotion = messages.value?.where((m) => m.emotion != null).firstOrNull?.emotion;
    final name = (ref.watch(userDocProvider).value?['profile'] as Map?)?['displayName'] as String? ?? '';

    ref.listen(coachMessagesProvider, (_, next) {
      final newest = next.value?.firstOrNull;
      if (newest != null) _maybeSpeak(newest);
    });

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset(BrandAssets.mark, width: 32),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(guardian.assistantName),
                Text(
                  guardian.handsFree ? 'Say “${guardian.effectiveWakePhrase(name)}” anytime' : 'Your recovery coach',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ],
        ),
        actions: [
          if (latestEmotion != null) _EmotionChip(emotion: latestEmotion),
          IconButton(
            tooltip: _speakReplies ? 'Mute voice replies' : 'Speak replies',
            icon: Icon(_speakReplies ? Icons.volume_up_rounded : Icons.volume_off_rounded),
            onPressed: () {
              setState(() => _speakReplies = !_speakReplies);
              if (!_speakReplies) _tts.stop();
            },
          ),
        ],
      ),
      body: AuroraBackground(
        accent: _listening ? Brand.ember : Brand.iris,
        child: Column(
          children: [
            Expanded(
              child: messages.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('$e')),
                data: (list) => list.isEmpty
                    ? _EmptyCoach(
                        name: guardian.assistantName,
                        onPick: (s) => _send(text: s),
                      )
                    : ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        itemCount: list.length + (_sending ? 1 : 0),
                        itemBuilder: (context, i) {
                          if (_sending && i == 0) return const _TypingBubble();
                          final m = list[i - (_sending ? 1 : 0)];
                          return _Bubble(message: m, onAction: _runAction);
                        },
                      ),
              ),
            ),
            if (_listening) _ListeningPanel(partial: _partial, level: _level, onStop: _talk),
            if (_image != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(_image!, height: 72, width: 72, fit: BoxFit.cover),
                    ),
                    IconButton(onPressed: () => setState(() => _image = null), icon: const Icon(Icons.close_rounded)),
                  ],
                ),
              ),
            _Composer(
              controller: _input,
              sending: _sending,
              listening: _listening,
              onSend: () => _send(),
              onMic: _talk,
              onCamera: () => _pickImage(ImageSource.camera),
              onGallery: () => _pickImage(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmotionChip extends StatelessWidget {
  const _EmotionChip({required this.emotion});
  final Emotion emotion;

  static const _icons = {
    'calm': Icons.spa_rounded,
    'hopeful': Icons.wb_sunny_rounded,
    'happy': Icons.sentiment_very_satisfied_rounded,
    'stressed': Icons.bolt_rounded,
    'anxious': Icons.waves_rounded,
    'sad': Icons.water_drop_rounded,
    'frustrated': Icons.local_fire_department_rounded,
    'tired': Icons.bedtime_rounded,
    'craving': Icons.phone_android_rounded,
  };

  @override
  Widget build(BuildContext context) => Tooltip(
    message: emotion.cues.isEmpty ? 'Estimated mood' : 'Estimated from ${emotion.cues}',
    child: Chip(
      avatar: Icon(_icons[emotion.label] ?? Icons.sentiment_neutral_rounded, size: 16),
      label: Text(emotion.label),
      visualDensity: VisualDensity.compact,
    ),
  );
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.onAction});
  final CoachMessage message;
  final void Function(CoachAction) onAction;

  @override
  Widget build(BuildContext context) {
    final mine = message.isUser;
    final scheme = Theme.of(context).colorScheme;
    final textStyle = Theme.of(context).textTheme.bodyLarge?.copyWith(color: mine ? Brand.ink : scheme.onSurface);
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: math.min(MediaQuery.of(context).size.width * 0.82, 520)),
        child: Column(
          crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              decoration: BoxDecoration(
                gradient: mine ? Brand.auroraGradient : null,
                color: mine ? null : scheme.surface.withValues(alpha: 0.85),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(mine ? 18 : 4),
                  bottomRight: Radius.circular(mine ? 4 : 18),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (message.imageUrl != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(message.imageUrl!, height: 180, fit: BoxFit.cover),
                      ),
                    ),
                  if (message.viaVoice)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.mic_rounded, size: 14, color: Brand.ink),
                          const SizedBox(width: 4),
                          Text('voice', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Brand.ink)),
                        ],
                      ),
                    ),
                  if (message.text.isNotEmpty)
                    SelectableLinkify(
                      text: message.text,
                      style: textStyle,
                      linkStyle: textStyle?.copyWith(
                        color: mine ? Brand.ink : Brand.aurora,
                        decoration: TextDecoration.underline,
                      ),
                      onOpen: (link) => openInAppTab(link.url),
                    ),
                ],
              ),
            ),
            if (message.actions.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final a in message.actions)
                    ActionChip(
                      avatar: Icon(a.type == 'url' ? Icons.open_in_new_rounded : Icons.arrow_forward_rounded, size: 16),
                      label: Text(a.label),
                      onPressed: () => onAction(a),
                    ),
                ],
              ).animate().fadeIn(delay: 200.ms),
            const SizedBox(height: 10),
          ],
        ),
      ),
    ).animate().fadeIn(duration: Brand.motionFast).slideY(begin: 0.1, curve: Curves.easeOutCubic);
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++)
            Container(
                  width: 7,
                  height: 7,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: const BoxDecoration(color: Brand.aurora, shape: BoxShape.circle),
                )
                .animate(onPlay: (c) => c.repeat())
                .moveY(begin: 0, end: -5, delay: (i * 150).ms, duration: 400.ms)
                .then()
                .moveY(end: 0),
        ],
      ),
    ),
  );
}

class _ListeningPanel extends StatelessWidget {
  const _ListeningPanel({required this.partial, required this.level, required this.onStop});
  final String partial;
  final double level;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final scale = 1 + (level.clamp(-2, 10) + 2) / 24;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: GlassCard(
        child: Column(
          children: [
            GestureDetector(
              onTap: onStop,
              child: AnimatedScale(
                scale: scale,
                duration: const Duration(milliseconds: 120),
                child: const AnimatedStepIcon(
                  icon: Icons.mic_rounded,
                  color: Brand.ember,
                  motion: StepIconMotion.wave,
                  size: 64,
                ),
              ),
            ),
            Text(
              partial.isEmpty ? 'Listening… speak naturally' : partial,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text('Tap the mic to finish', style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
      ),
    );
  }
}

class _EmptyCoach extends StatelessWidget {
  const _EmptyCoach({required this.name, required this.onPick});
  final String name;
  final void Function(String) onPick;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      ScreenHeader(
        visual: const AnimatedStepIcon(icon: Icons.forum_rounded, motion: StepIconMotion.orbit, color: Brand.aurora),
        title: 'Hi, I\'m $name',
        description:
            'Talk or type — I know your plan, your check-ins and how your day on the phone is going. '
            'Send a photo, ask for a book, or tell me when an urge hits.',
      ),
      const SizedBox(height: 24),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: [
          for (final (i, s) in _CoachScreenState._suggestions.indexed)
            ActionChip(label: Text(s), onPressed: () => onPick(s)).animate().fadeIn(delay: (80 * i).ms),
        ],
      ),
    ],
  );
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.listening,
    required this.onSend,
    required this.onMic,
    required this.onCamera,
    required this.onGallery,
  });

  final TextEditingController controller;
  final bool sending;
  final bool listening;
  final VoidCallback onSend;
  final VoidCallback onMic;
  final VoidCallback onCamera;
  final VoidCallback onGallery;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.add_circle_outline_rounded),
            onSelected: (v) => v == 'camera' ? onCamera() : onGallery(),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'camera',
                child: ListTile(leading: Icon(Icons.photo_camera_rounded), title: Text('Camera')),
              ),
              PopupMenuItem(
                value: 'gallery',
                child: ListTile(leading: Icon(Icons.photo_library_rounded), title: Text('Photo library')),
              ),
            ],
          ),
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Message your coach', isDense: true),
              onSubmitted: (_) => onSend(),
            ),
          ),
          const SizedBox(width: 6),
          ValueListenableBuilder(
            valueListenable: controller,
            builder: (context, value, _) {
              final hasText = value.text.trim().isNotEmpty;
              return IconButton.filled(
                style: IconButton.styleFrom(
                  backgroundColor: listening ? Brand.ember : Brand.aurora,
                  foregroundColor: Brand.ink,
                  minimumSize: const Size(48, 48),
                ),
                onPressed: sending ? null : (hasText ? onSend : onMic),
                icon: sending
                    ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(hasText ? Icons.arrow_upward_rounded : (listening ? Icons.stop_rounded : Icons.mic_rounded)),
              );
            },
          ),
        ],
      ),
    ),
  );
}
