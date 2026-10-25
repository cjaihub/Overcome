import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../core/security/secure_content_guard.dart';
import '../../core/services/analytics_service.dart';
import '../../core/theme/brand.dart';
import '../../core/widgets/animated_step_icon.dart';
import '../../core/widgets/aurora_background.dart';
import '../../core/widgets/common.dart';
import '../settings/settings_controller.dart';
import 'book_detail_screen.dart';
import 'library_repository.dart';

enum NarratorPersona {
  storyteller('Storyteller', Icons.auto_stories_rounded, Brand.iris, 0.46, 0.95),
  teacher('Teacher', Icons.school_rounded, Brand.aurora, 0.5, 1.0),
  motivator('Motivator', Icons.local_fire_department_rounded, Brand.ember, 0.54, 1.08);

  const NarratorPersona(this.label, this.icon, this.color, this.rate, this.pitch);
  final String label;
  final IconData icon;
  final Color color;
  final double rate;
  final double pitch;
}

/// Premium AI mode: the book's passage is re-voiced by Claude in the chosen
/// persona (faithful to the source, never adding claims), then spoken on
/// device with word-by-word highlighting.
class AiNarratorScreen extends ConsumerStatefulWidget {
  const AiNarratorScreen({super.key, required this.bookId});
  final String bookId;

  @override
  ConsumerState<AiNarratorScreen> createState() => _AiNarratorScreenState();
}

class _AiNarratorScreenState extends ConsumerState<AiNarratorScreen> {
  final _tts = FlutterTts();
  late NarratorPersona _persona =
      NarratorPersona.values.asNameMap()[ref.read(settingsProvider).narrator] ?? NarratorPersona.teacher;
  List<String> _sections = const [];
  int _section = 0;
  String _script = '';
  int _wordStart = 0;
  int _wordEnd = 0;
  bool _busy = false;
  bool _speaking = false;
  bool _continuous = true;

  @override
  void initState() {
    super.initState();
    _tts
      ..setProgressHandler(
        (text, start, end, word) => setState(() {
          _wordStart = start;
          _wordEnd = end;
        }),
      )
      ..setCompletionHandler(() {
        setState(() => _speaking = false);
        if (_continuous && _section < _sections.length - 1) {
          setState(() => _section++);
          _narrate();
        }
      })
      ..setCancelHandler(() => setState(() => _speaking = false));
    _load();
  }

  Future<void> _load() async {
    final access = await resolveAccess(context, ref, widget.bookId);
    if (access == null) return;
    final lines = await ref.read(libraryRepositoryProvider).transcript(access);
    final sections = <String>[];
    final buf = StringBuffer();
    var count = 0;
    int? chapter;
    for (final l in lines) {
      if ((chapter != null && l.chapter != chapter) || count >= 8) {
        sections.add(buf.toString().trim());
        buf.clear();
        count = 0;
      }
      chapter = l.chapter;
      buf.write('${l.text} ');
      count++;
    }
    if (buf.isNotEmpty) sections.add(buf.toString().trim());
    if (mounted) setState(() => _sections = sections);
  }

  Future<void> _narrate() async {
    if (_sections.isEmpty) return;
    setState(() {
      _busy = true;
      _script = '';
      _wordStart = _wordEnd = 0;
    });
    try {
      final script = await ref
          .read(libraryRepositoryProvider)
          .narrate(bookId: widget.bookId, passage: _sections[_section], persona: _persona.name);
      final speed = ref.read(settingsProvider).voiceSpeed;
      await _tts.setSpeechRate((_persona.rate * speed).clamp(0.1, 1.0));
      await _tts.setPitch(_persona.pitch);
      await _tts.awaitSpeakCompletion(false);
      setState(() {
        _script = script;
        _speaking = true;
      });
      ref.read(analyticsProvider).log(AppEvent.aiNarration, {'bookId': widget.bookId, 'persona': _persona.name});
      await _tts.speak(script);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _jump(int by) => setState(() {
    _section += by;
    _script = '';
  });

  Future<void> _stop() async {
    _continuous = false;
    await _tts.stop();
    setState(() => _speaking = false);
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final style = text.titleLarge!.copyWith(height: 1.5, fontWeight: FontWeight.w400);
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(title: const Text('AI narrator')),
      body: AuroraBackground(
        accent: _persona.color,
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 8),
              AnimatedStepIcon(
                icon: _persona.icon,
                color: _persona.color,
                motion: _speaking ? StepIconMotion.wave : StepIconMotion.breathe,
                size: 80,
              ),
              const SizedBox(height: 8),
              SegmentedButton<NarratorPersona>(
                segments: [
                  for (final p in NarratorPersona.values)
                    ButtonSegment(value: p, label: Text(p.label), icon: Icon(p.icon, size: 18)),
                ],
                selected: {_persona},
                onSelectionChanged: (s) {
                  setState(() => _persona = s.first);
                  ref.read(settingsProvider.notifier).setNarrator(s.first.name);
                },
              ),
              const SizedBox(height: 12),
              if (_sections.isNotEmpty) Text('Passage ${_section + 1} of ${_sections.length}', style: text.labelMedium),
              Expanded(
                child: SecureContentGuard(
                  watermark: widget.bookId,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: _busy
                        ? Column(
                            children: [
                              const SizedBox(height: 40),
                              Text(
                                'Your ${_persona.label.toLowerCase()} is preparing…',
                                style: text.titleMedium,
                              ).animate(onPlay: (c) => c.repeat(reverse: true)).fade(begin: 0.4),
                            ],
                          )
                        : _script.isEmpty
                        ? Text(
                            _sections.isEmpty ? 'Loading passages…' : _sections[_section],
                            style: style.copyWith(color: style.color?.withValues(alpha: 0.6)),
                          )
                        : RichText(
                            text: TextSpan(
                              style: style,
                              children: [
                                TextSpan(text: _script.substring(0, _wordStart)),
                                TextSpan(
                                  text: _script.substring(_wordStart, _wordEnd.clamp(_wordStart, _script.length)),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                    background: Paint()..color = _persona.color.withValues(alpha: 0.85),
                                  ),
                                ),
                                TextSpan(
                                  text: _script.substring(_wordEnd.clamp(_wordStart, _script.length)),
                                  style: TextStyle(color: style.color?.withValues(alpha: 0.65)),
                                ),
                              ],
                            ),
                          ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _section > 0 && !_busy ? () => _jump(-1) : null,
                      icon: const Icon(Icons.skip_previous_rounded),
                    ),
                    Expanded(
                      child: GradientButton(
                        label: _speaking ? 'Stop' : 'Narrate',
                        icon: _speaking ? Icons.stop_rounded : Icons.play_arrow_rounded,
                        loading: _busy,
                        gradient: Brand.gradientFor(
                          Brand.accents.entries.firstWhere((e) => e.value == _persona.color).key,
                        ),
                        onPressed: _sections.isEmpty
                            ? null
                            : () {
                                if (_speaking) {
                                  _stop();
                                } else {
                                  _continuous = true;
                                  _narrate();
                                }
                              },
                      ),
                    ),
                    IconButton(
                      onPressed: _section < _sections.length - 1 && !_busy ? () => _jump(1) : null,
                      icon: const Icon(Icons.skip_next_rounded),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
