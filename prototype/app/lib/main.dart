import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'local_runtime_server.dart';
import 'probe_client.dart';

void main() => runApp(
  MaterialApp(
    theme: ThemeData(
      useMaterial3: true,
      fontFamily: 'Roboto',
      colorSchemeSeed: Colors.teal,
    ),
    home: const ProbeScreen(),
  ),
);

class ProbeScreen extends StatefulWidget {
  const ProbeScreen({super.key});

  @override
  State<ProbeScreen> createState() => _ProbeScreenState();
}

class _ProbeScreenState extends State<ProbeScreen> with WidgetsBindingObserver {
  final _server = LocalRuntimeServer();
  final _client = ProbeClient();
  final _recorder = AudioRecorder();
  final _log = <String>[];
  final _chunks = Queue<Uint8List>();
  StreamSubscription<Map<String, dynamic>>? _events;
  StreamSubscription<Uint8List>? _audio;
  Uint8List _remainder = Uint8List(0);
  Future<void>? _draining;
  String _status = 'Preparing local assets...';
  String _position = 'No recognition yet';
  bool _attached = false;
  bool _ready = false;
  bool _busy = true;
  bool _recording = false;
  bool _closingMic = false;
  static const _diagnostics = MethodChannel(
    'dev.qiyam.tilawa_bridge_probe/diagnostics',
  );
  final _captureClock = Stopwatch();
  Timer? _micDeadline;
  Timer? _micReport;
  StreamSubscription<RecordState>? _recorderState;
  int _capturedBytes = 0;
  int _fedBytes = 0;
  int _queueHighWater = 0;
  int _feedCalls = 0;
  int _feedMicros = 0;
  int _maxFeedMicros = 0;
  int _overruns = 0;
  int _micMatches = 0;
  int _micProgress = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _events = _client.messages.listen(_message);
    unawaited(_start());
  }

  void _record(String text) {
    debugPrint('TILAWA_PROBE $text');
    if (!mounted) return;
    setState(() {
      _log.add(text);
      if (_log.length > 80) _log.removeAt(0);
    });
  }

  Future<void> _start() async {
    try {
      await _server.start();
      if (!mounted) {
        await _server.dispose();
        return;
      }
      await _client.attach(_server.origin);
      if (mounted) setState(() => _attached = true);
    } catch (error) {
      _failure(error);
    }
  }

  void _message(Map<String, dynamic> message) {
    if (message['kind'] == 'bridge_ready') {
      unawaited(_initialize());
    } else if (message['kind'] == 'runtime_error') {
      _failure(message['error']);
    } else if (message['kind'] == 'event') {
      final event = Map<String, dynamic>.from(message['event'] as Map);
      if (_recording || _closingMic) {
        if (event['type'] == 'verse_match') _micMatches++;
        if (event['type'] == 'word_progress') _micProgress++;
      }
      if (event['type'] == 'word_progress') {
        if (mounted) {
          setState(
            () => _position =
                '${event['surah']}:${event['ayah']} word index ${event['word_index']} / ${event['total_words']}',
          );
        }
      }
      // Do not print microphone transcripts or recognition payloads in logs.
      if (!_recording && !_closingMic) _record(jsonEncode(message));
    }
  }

  Future<void> _initialize() async {
    try {
      final result = await _client.call('initialize');
      _record('initialize ${jsonEncode(result)}');
      if (!mounted) return;
      setState(() {
        _ready = true;
        _busy = false;
        _status = 'Ready. All inference assets are local.';
      });
      if (const bool.fromEnvironment('PROBE_AUTORUN')) {
        unawaited(_run(_autorun));
      }
    } catch (error) {
      _failure(error);
    }
  }

  void _failure(Object? error) {
    _record('ERROR $error');
    if (mounted) {
      setState(() {
        _status = 'Error: $error';
        _busy = false;
      });
    }
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (_busy || _recording) return;
    setState(() => _busy = true);
    try {
      await operation();
    } catch (error) {
      _failure(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sample(String id, {bool paced = false}) async {
    setState(
      () =>
          _status = 'Recognizing $id${paced ? ' at real-time cadence' : ''}...',
    );
    final result = await _client.call('sample', {'id': id, 'paced': paced});
    _record('sample ${jsonEncode(result)}');
    if (mounted) setState(() => _status = 'Sample finished. See evidence log.');
  }

  Future<void> _autorun() async {
    await _sample('ref_112001');
    await _sample('multi_113_001_005');
    _record('silence ${jsonEncode(await _client.call('silence'))}');
    await _sample('multi_113_001_005', paced: true);
    _record('dispose ${jsonEncode(await _client.call('dispose'))}');
    _record('reinitialize ${jsonEncode(await _client.call('initialize'))}');
    await _sample('ref_112001');
    const cycles = int.fromEnvironment('PROBE_CYCLES');
    if (cycles < 0 || cycles > 10) {
      throw StateError('PROBE_CYCLES must be 0..10');
    }
    for (var cycle = 1; cycle <= cycles; cycle++) {
      _record('cycle $cycle before ${jsonEncode(await _nativeSnapshot())}');
      await _client.call('dispose');
      _record('cycle $cycle released ${jsonEncode(await _nativeSnapshot())}');
      _record(
        'cycle $cycle initialize ${jsonEncode(await _client.call('initialize'))}',
      );
      await _sample('ref_112001');
      _record('cycle $cycle after ${jsonEncode(await _nativeSnapshot())}');
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    _record('AUTORUN_COMPLETE');
  }

  Future<Object?> _nativeSnapshot() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return {'available': false};
    }
    return _diagnostics.invokeMethod<Object?>('snapshot');
  }

  Map<String, Object> _micMetrics() => {
    'captureElapsedMs': _captureClock.elapsedMilliseconds,
    'capturedBytes': _capturedBytes,
    'capturedSecondsAt16k': _capturedBytes / 32000,
    'fedBytes': _fedBytes,
    'pendingChunks': _chunks.length,
    'remainderBytes': _remainder.length,
    'queueHighWater': _queueHighWater,
    'feedCalls': _feedCalls,
    'meanFeedMs': _feedCalls == 0 ? 0 : _feedMicros / _feedCalls / 1000,
    'maxFeedMs': _maxFeedMicros / 1000,
    'overruns': _overruns,
    'verseMatches': _micMatches,
    'wordProgress': _micProgress,
  };

  Future<void> _reportMic() async {
    try {
      final native = await _nativeSnapshot();
      if (_recording && !_closingMic) {
        _record(
          'microphone_metrics ${jsonEncode(_micMetrics())} native ${jsonEncode(native)}',
        );
      }
    } catch (error) {
      _record('diagnostics_unavailable $error');
    }
  }

  Future<void> _feedMic(Uint8List bytes) async {
    final clock = Stopwatch()..start();
    await _client.call('feed', {'pcm16': base64Encode(bytes)});
    final elapsed = clock.elapsedMicroseconds;
    _feedCalls++;
    _fedBytes += bytes.length;
    _feedMicros += elapsed;
    if (elapsed > _maxFeedMicros) _maxFeedMicros = elapsed;
  }

  Future<void> _startMic() async {
    await _run(() async {
      if (!await _recorder.hasPermission()) {
        throw StateError('Microphone permission denied');
      }
      await _client.call('reset');
      _remainder = Uint8List(0);
      _chunks.clear();
      _capturedBytes = _fedBytes = _queueHighWater = _feedCalls = 0;
      _feedMicros = _maxFeedMicros = _overruns = _micMatches = _micProgress = 0;
      _captureClock.reset();
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          echoCancel: false,
          noiseSuppress: false,
          autoGain: false,
        ),
      );
      if (!mounted ||
          WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        await _recorder.stop();
        return;
      }
      _captureClock.start();
      setState(() {
        _recording = true;
        _status = 'Listening locally: requested mono 16 kHz PCM16';
      });
      _audio = stream.listen(
        _capture,
        onError: (Object error) {
          _failure(error);
          unawaited(_stopMic());
        },
      );
      _recorderState = _recorder.onStateChanged().listen((state) {
        if (_recording && !_closingMic && state != RecordState.record) {
          _record('microphone_interruption $state');
          unawaited(_stopMic());
        }
      });
      _micReport = Timer.periodic(
        const Duration(seconds: 30),
        (_) => unawaited(_reportMic()),
      );
      const seconds = int.fromEnvironment('PROBE_MIC_SECONDS');
      if (seconds > 0) {
        _micDeadline = Timer(
          Duration(seconds: seconds),
          () => unawaited(_stopMic()),
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await _reportMic();
    });
  }

  void _capture(Uint8List data) {
    if (!_recording || _closingMic) return;
    _capturedBytes += data.length;
    final combined = Uint8List(_remainder.length + data.length)
      ..setRange(0, _remainder.length, _remainder)
      ..setRange(_remainder.length, _remainder.length + data.length, data);
    const chunkBytes = 15360;
    var offset = 0;
    while (combined.length - offset >= chunkBytes) {
      if (_chunks.length >= 4) {
        _overruns++;
        _failure(
          'Audio overrun: four pending 480 ms chunks. Capture is stopping.',
        );
        unawaited(_stopMic());
        return;
      }
      _chunks.add(Uint8List.sublistView(combined, offset, offset + chunkBytes));
      if (_chunks.length > _queueHighWater) _queueHighWater = _chunks.length;
      offset += chunkBytes;
    }
    _remainder = Uint8List.fromList(combined.sublist(offset));
    _beginDrain();
  }

  void _beginDrain() {
    if (_draining != null) return;
    _draining = _drain()
        .catchError((Object error) {
          _failure(error);
          _chunks.clear();
          unawaited(_stopMic());
        })
        .whenComplete(() {
          _draining = null;
          if (_chunks.isNotEmpty) _beginDrain();
        });
  }

  Future<void> _drain() async {
    while (_chunks.isNotEmpty) {
      await _feedMic(_chunks.removeFirst());
    }
  }

  Future<void> _stopMic() async {
    if (!_recording || _closingMic) return;
    _closingMic = true;
    _micDeadline?.cancel();
    _micReport?.cancel();
    _captureClock.stop();
    try {
      await _recorder.stop();
      await _audio?.cancel();
      _audio = null;
      await _recorderState?.cancel();
      _recorderState = null;
      await _draining;
      if (_remainder.length.isOdd) {
        throw StateError('Capture ended with an incomplete PCM16 sample');
      }
      if (_remainder.isNotEmpty) {
        await _feedMic(_remainder);
        _remainder = Uint8List(0);
      }
      final flush = Stopwatch()..start();
      final result = await _client.call('stop');
      // Keep recited references/transcripts out of persistent device diagnostics.
      _record(
        'microphone_stop ${jsonEncode({..._micMetrics(), 'flushMs': flush.elapsedMilliseconds, 'processedSamples': result['samples'], 'inferenceCalls': result['inferenceCalls'], 'inferenceMs': result['inferenceMs']})}',
      );
      if (mounted) {
        setState(() => _status = 'Microphone stopped and audio flushed.');
      }
    } catch (error) {
      _failure(error);
    } finally {
      _chunks.clear();
      _remainder = Uint8List(0);
      _closingMic = false;
      if (mounted) setState(() => _recording = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _recording) {
      _record('microphone_lifecycle $state');
      unawaited(_stopMic());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _micDeadline?.cancel();
    _micReport?.cancel();
    unawaited(_recorderState?.cancel());
    unawaited(_audio?.cancel());
    unawaited(_events?.cancel());
    unawaited(_recorder.dispose());
    unawaited(_client.close());
    unawaited(_server.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tilawa: Phase 1 Probe')),
      body: SafeArea(
        child: Column(
          children: [
            if (_busy) const LinearProgressIndicator(),
            Padding(padding: const EdgeInsets.all(12), child: Text(_status)),
            Text(_position),
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  onPressed: _ready && !_busy && !_recording
                      ? () => _run(() => _sample('ref_112001'))
                      : null,
                  child: const Text('Single ayah'),
                ),
                FilledButton(
                  onPressed: _ready && !_busy && !_recording
                      ? () => _run(() => _sample('multi_113_001_005'))
                      : null,
                  child: const Text('Multi ayah'),
                ),
                OutlinedButton(
                  onPressed: _ready && !_busy && !_recording
                      ? () => _run(_autorun)
                      : null,
                  child: const Text('Run probes'),
                ),
                OutlinedButton(
                  onPressed: _ready && !_busy
                      ? (_recording ? _stopMic : _startMic)
                      : null,
                  child: Text(_recording ? 'Stop mic' : 'Start mic'),
                ),
              ],
            ),
            if (_attached)
              SizedBox(
                height: 48,
                child: WebViewWidget(controller: _client.controller),
              ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                reverse: true,
                itemCount: _log.length,
                itemBuilder: (context, index) => Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 3,
                  ),
                  child: Text(
                    _log[_log.length - 1 - index],
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
