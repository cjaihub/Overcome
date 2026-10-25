import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// A spoken message plus the acoustic cues used to estimate emotion.
/// Cues are derived on-device from speech rate, loudness and pauses; the
/// coach model combines them with the words to estimate how the user feels.
class VoiceSample {
  const VoiceSample({
    required this.transcript,
    required this.duration,
    required this.wordsPerMinute,
    required this.loudness,
    required this.loudnessVariation,
    required this.pauseRatio,
  });

  final String transcript;
  final Duration duration;
  final double wordsPerMinute;

  /// 0–1, average input level relative to the session's range.
  final double loudness;

  /// 0–1, how much loudness swung (agitation / emphasis).
  final double loudnessVariation;

  /// 0–1, share of the recording that was silence (hesitation / low energy).
  final double pauseRatio;

  Map<String, Object> toMap() => {
    'durationSec': duration.inMilliseconds / 1000,
    'wordsPerMinute': wordsPerMinute.round(),
    'loudness': double.parse(loudness.toStringAsFixed(2)),
    'loudnessVariation': double.parse(loudnessVariation.toStringAsFixed(2)),
    'pauseRatio': double.parse(pauseRatio.toStringAsFixed(2)),
  };

  /// Pure feature extraction (unit-tested).
  static VoiceSample fromLevels(String transcript, Duration duration, List<double> levels) {
    final words = transcript.trim().isEmpty ? 0 : transcript.trim().split(RegExp(r'\s+')).length;
    final minutes = math.max(duration.inMilliseconds, 1) / 60000;
    if (levels.isEmpty) {
      return VoiceSample(
        transcript: transcript,
        duration: duration,
        wordsPerMinute: words / minutes,
        loudness: 0.5,
        loudnessVariation: 0,
        pauseRatio: 0,
      );
    }
    final lo = levels.reduce(math.min);
    final hi = levels.reduce(math.max);
    final range = math.max(hi - lo, 1e-6);
    final norm = [for (final l in levels) (l - lo) / range];
    final mean = norm.reduce((a, b) => a + b) / norm.length;
    final variance = norm.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) / norm.length;
    return VoiceSample(
      transcript: transcript,
      duration: duration,
      wordsPerMinute: words / minutes,
      loudness: mean,
      loudnessVariation: math.min(1, math.sqrt(variance) * 2),
      pauseRatio: norm.where((v) => v < 0.15).length / norm.length,
    );
  }
}

/// One shared speech recognizer for push-to-talk and the wake word.
class VoiceEngine {
  final _stt = SpeechToText();
  bool _ready = false;
  void Function()? _onDone;

  bool get isListening => _stt.isListening;

  Future<bool> init() async {
    if (_ready) return true;
    _ready = await _stt.initialize(
      onStatus: (s) {
        if (s == SpeechToText.doneStatus || s == SpeechToText.notListeningStatus) _onDone?.call();
      },
      onError: (_) => _onDone?.call(),
    );
    return _ready;
  }

  /// Records one utterance; returns null if nothing was understood.
  Future<VoiceSample?> capture({void Function(String partial)? onPartial, void Function(double level)? onLevel}) async {
    if (!await init()) return null;
    await _stt.cancel();
    final levels = <double>[];
    final started = DateTime.now();
    final done = Completer<String>();
    var latest = '';
    _onDone = () {
      if (!done.isCompleted) done.complete(latest);
    };
    await _stt.listen(
      onResult: (SpeechRecognitionResult r) {
        latest = r.recognizedWords;
        onPartial?.call(latest);
        if (r.finalResult && !done.isCompleted) done.complete(latest);
      },
      onSoundLevelChange: (l) {
        levels.add(l);
        onLevel?.call(l);
      },
      listenOptions: SpeechListenOptions(
        listenFor: const Duration(seconds: 60),
        pauseFor: const Duration(seconds: 3),
        partialResults: true,
        listenMode: ListenMode.dictation,
        autoPunctuation: true,
      ),
    );
    final text = await done.future;
    _onDone = null;
    if (text.trim().isEmpty) return null;
    return VoiceSample.fromLevels(text, DateTime.now().difference(started), levels);
  }

  Future<void> stop() => _stt.stop();

  /// Listens in short windows for [phrase]; completes true when heard.
  /// Returns false when a window ends without it (the caller re-arms).
  Future<bool> listenForPhrase(String phrase) async {
    if (!await init()) return false;
    final done = Completer<bool>();
    _onDone = () {
      if (!done.isCompleted) done.complete(false);
    };
    await _stt.listen(
      onResult: (r) {
        if (WakeMatcher.matches(r.recognizedWords, phrase) && !done.isCompleted) {
          done.complete(true);
          _stt.stop();
        }
      },
      listenOptions: SpeechListenOptions(
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 8),
        partialResults: true,
        onDevice: true,
        listenMode: ListenMode.search,
      ),
    );
    final heard = await done.future;
    _onDone = null;
    return heard;
  }
}

/// Fuzzy wake-phrase matching that tolerates recognizer spelling drift
/// ("Amara" heard as "Amarah"), unit-tested.
abstract final class WakeMatcher {
  static String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r"[^a-z0-9\s]"), ' ').trim();

  static bool matches(String heard, String phrase) {
    final target = _norm(phrase).split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final words = _norm(heard).split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (target.isEmpty || words.length < target.length) return false;
    for (var i = 0; i + target.length <= words.length; i++) {
      var ok = true;
      for (var j = 0; j < target.length; j++) {
        final a = words[i + j], b = target[j];
        final tolerance = b.length >= 5 ? 2 : (b.length >= 4 ? 1 : 0);
        if (_distance(a, b) > tolerance) {
          ok = false;
          break;
        }
      }
      if (ok) return true;
    }
    return false;
  }

  static int _distance(String a, String b) {
    var prev = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final cur = [i, ...List.filled(b.length, 0)];
      for (var j = 1; j <= b.length; j++) {
        cur[j] = [prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)].reduce(math.min);
      }
      prev = cur;
    }
    return prev[b.length];
  }
}

final voiceEngineProvider = Provider<VoiceEngine>((_) => VoiceEngine());
