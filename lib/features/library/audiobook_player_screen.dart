import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import '../../core/security/secure_content_guard.dart';
import '../../core/services/analytics_service.dart';
import '../../core/theme/brand.dart';
import '../../core/widgets/aurora_background.dart';
import 'book.dart';
import 'book_detail_screen.dart';
import 'library_repository.dart';

/// Immersive audiobook player with synchronized read-along: the line being
/// narrated is highlighted and kept centred; tap any line to jump to it.
/// Playback continues in the background with lock-screen controls.
class AudiobookPlayerScreen extends ConsumerStatefulWidget {
  const AudiobookPlayerScreen({super.key, required this.bookId});
  final String bookId;

  @override
  ConsumerState<AudiobookPlayerScreen> createState() => _AudiobookPlayerScreenState();
}

class _AudiobookPlayerScreenState extends ConsumerState<AudiobookPlayerScreen> {
  final _player = AudioPlayer();
  List<TranscriptLine> _lines = const [];
  List<AudioChapter> _chapters = const [];
  final _keys = <int, GlobalKey>{};
  int _active = -1;
  bool _loading = true;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<PlayerState>? _stateSub;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final access = await resolveAccess(context, ref, widget.bookId);
    if (access == null) return;
    final repo = ref.read(libraryRepositoryProvider);
    final book = ref.read(bookProvider(widget.bookId)).value;
    final lines = await repo.transcript(access);
    _chapters = access.chapters;
    await _player.setAudioSources([
      for (final (i, c) in access.chapters.indexed)
        AudioSource.uri(
          Uri.parse(c.url),
          tag: MediaItem(
            id: '${widget.bookId}-$i',
            title: c.title,
            album: book?.title ?? 'Overcome',
            artist: book?.author,
            artUri: book == null || book.coverUrl.isEmpty ? null : Uri.parse(book.coverUrl),
          ),
        ),
    ]);
    _posSub = _player.positionStream.listen(_onPosition);
    _stateSub = _player.playerStateStream.listen((s) {
      if (s.processingState == ProcessingState.completed) {
        ref.read(analyticsProvider).log(AppEvent.audioComplete, {'bookId': widget.bookId});
      }
    });
    if (!mounted) return;
    setState(() {
      _lines = lines;
      _loading = false;
    });
    ref.read(analyticsProvider).log(AppEvent.readAlongStart, {'bookId': widget.bookId});
  }

  void _onPosition(Duration pos) {
    final chapter = _player.currentIndex ?? 0;
    final ms = pos.inMilliseconds;
    final i = _lines.indexWhere((l) => l.chapter == chapter && ms >= l.startMs && ms < l.endMs);
    if (i == -1 || i == _active) return;
    setState(() => _active = i);
    final ctx = _keys[i]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx, alignment: 0.4, duration: Brand.motion, curve: Curves.easeOutCubic);
    }
  }

  Future<void> _seekToLine(int i) async {
    final l = _lines[i];
    await _player.seek(Duration(milliseconds: l.startMs), index: l.chapter);
    if (!_player.playing) _play();
  }

  void _play() {
    _player.play();
    ref.read(analyticsProvider).log(AppEvent.audioPlay, {'bookId': widget.bookId, 'chapter': _player.currentIndex});
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _stateSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final book = ref.watch(bookProvider(widget.bookId)).value;
    final accent = book?.color ?? Brand.aurora;
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: StreamBuilder<int?>(
          stream: _player.currentIndexStream,
          builder: (_, s) => Text(
            _chapters.isEmpty ? (book?.title ?? '') : _chapters[(s.data ?? 0).clamp(0, _chapters.length - 1)].title,
          ),
        ),
      ),
      body: AuroraBackground(
        accent: accent,
        child: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    StreamBuilder<bool>(
                      stream: _player.playingStream,
                      builder: (_, s) => _Waveform(playing: s.data ?? false, color: accent),
                    ),
                    Expanded(
                      child: SecureContentGuard(
                        watermark: user?.uid.substring(0, 8) ?? '',
                        onCaptureAttempt: (k) => ref.read(analyticsProvider).log(AppEvent.captureAttempt, {
                          'bookId': widget.bookId,
                          'kind': k,
                        }),
                        child: _lines.isEmpty
                            ? const Center(child: Text('Transcript not available for this title.'))
                            : SingleChildScrollView(
                                padding: const EdgeInsets.fromLTRB(24, 24, 24, 160),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [for (var i = 0; i < _lines.length; i++) _line(i, accent)],
                                ),
                              ),
                      ),
                    ),
                    _Controls(player: _player, accent: accent, onPlay: _play),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _line(int i, Color accent) {
    final active = i == _active;
    final past = i < _active;
    final style = Theme.of(context).textTheme.titleLarge!;
    final showChapter = i == 0 || _lines[i - 1].chapter != _lines[i].chapter;
    return Column(
      key: _keys.putIfAbsent(i, GlobalKey.new),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showChapter && _lines[i].chapter < _chapters.length)
          Padding(
            padding: const EdgeInsets.only(top: 24, bottom: 8),
            child: Text(
              _chapters[_lines[i].chapter].title.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: accent, letterSpacing: 2),
            ),
          ),
        GestureDetector(
          onTap: () => _seekToLine(i),
          child: AnimatedContainer(
            duration: Brand.motion,
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: active ? accent.withValues(alpha: 0.16) : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: Border(left: BorderSide(color: active ? accent : Colors.transparent, width: 3)),
            ),
            child: AnimatedDefaultTextStyle(
              duration: Brand.motion,
              style: style.copyWith(
                fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                color: style.color?.withValues(alpha: active ? 1 : (past ? 0.4 : 0.7)),
                height: 1.45,
              ),
              child: Text(_lines[i].text),
            ),
          ),
        ),
      ],
    );
  }
}

class _Waveform extends StatefulWidget {
  const _Waveform({required this.playing, required this.color});
  final bool playing;
  final Color color;

  @override
  State<_Waveform> createState() => _WaveformState();
}

class _WaveformState extends State<_Waveform> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 72,
    child: AnimatedBuilder(
      animation: _c,
      builder: (context, _) => CustomPaint(
        size: const Size(double.infinity, 72),
        painter: _WavePainter(_c.value, widget.playing ? 1 : 0.15, widget.color),
      ),
    ),
  );
}

class _WavePainter extends CustomPainter {
  _WavePainter(this.t, this.amp, this.color);
  final double t;
  final double amp;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const bars = 48;
    final w = size.width / bars;
    for (var i = 0; i < bars; i++) {
      final phase = t * 2 * math.pi + i * 0.45;
      final h = (0.15 + amp * (0.5 + 0.5 * math.sin(phase) * math.cos(phase * 0.37 + i))) * size.height;
      final x = i * w + w / 2;
      canvas.drawLine(
        Offset(x, size.height / 2 - h / 2),
        Offset(x, size.height / 2 + h / 2),
        Paint()
          ..strokeWidth = w * 0.5
          ..strokeCap = StrokeCap.round
          ..color = Color.lerp(color, Brand.iris, i / bars)!.withValues(alpha: 0.85),
      );
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) => true;
}

class _Controls extends StatelessWidget {
  const _Controls({required this.player, required this.accent, required this.onPlay});
  final AudioPlayer player;
  final Color accent;
  final VoidCallback onPlay;

  String _fmt(Duration d) =>
      '${d.inHours > 0 ? '${d.inHours}:' : ''}${(d.inMinutes % 60).toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(Brand.radiusLg)),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        StreamBuilder<Duration>(
          stream: player.positionStream,
          builder: (context, s) {
            final pos = s.data ?? Duration.zero;
            final dur = player.duration ?? Duration.zero;
            return Column(
              children: [
                Slider(
                  value: pos.inMilliseconds.clamp(0, math.max(1, dur.inMilliseconds)).toDouble(),
                  max: math.max(1, dur.inMilliseconds).toDouble(),
                  activeColor: accent,
                  onChanged: (v) => player.seek(Duration(milliseconds: v.round())),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_fmt(pos), style: Theme.of(context).textTheme.labelSmall),
                    Text('-${_fmt(dur - pos)}', style: Theme.of(context).textTheme.labelSmall),
                  ],
                ),
              ],
            );
          },
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            StreamBuilder<double>(
              stream: player.speedStream,
              builder: (_, s) => TextButton(
                onPressed: () {
                  const speeds = [0.8, 1.0, 1.25, 1.5, 2.0];
                  final i = speeds.indexOf(s.data ?? 1.0);
                  player.setSpeed(speeds[(i + 1) % speeds.length]);
                },
                child: Text('${s.data ?? 1}×'),
              ),
            ),
            IconButton(
              iconSize: 32,
              onPressed: () => player.seek(player.position - const Duration(seconds: 15)),
              icon: const Icon(Icons.replay_10_rounded),
            ),
            StreamBuilder<bool>(
              stream: player.playingStream,
              builder: (_, s) => GestureDetector(
                onTap: () => (s.data ?? false) ? player.pause() : onPlay(),
                child: AnimatedContainer(
                  duration: Brand.motionFast,
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [accent, Brand.iris]),
                    boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.5), blurRadius: 24)],
                  ),
                  child: AnimatedSwitcher(
                    duration: Brand.motionFast,
                    child: Icon(
                      (s.data ?? false) ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      key: ValueKey(s.data),
                      size: 40,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
            IconButton(
              iconSize: 32,
              onPressed: () => player.seek(player.position + const Duration(seconds: 30)),
              icon: const Icon(Icons.forward_30_rounded),
            ),
            IconButton(onPressed: player.hasNext ? player.seekToNext : null, icon: const Icon(Icons.skip_next_rounded)),
          ],
        ),
      ],
    ),
  );
}
