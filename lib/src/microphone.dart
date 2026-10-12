import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:record/record.dart';

import 'models.dart';
import 'capture_binding.dart';
import 'session.dart';

enum TilawaCaptureState {
  idle,
  starting,
  capturing,
  stopping,
  interrupted,
  failed,
  disposed,
}

/// Optional foreground capture. record converts native hardware input to the
/// requested PCM16 client format; hardware format is not inferred from bytes.
final class TilawaMicrophone with WidgetsBindingObserver {
  TilawaMicrophone._(this.session, this.maxPendingChunks);
  final TilawaSession session;
  final int maxPendingChunks;
  final _recorder = AudioRecorder();
  final _states = StreamController<TilawaCaptureState>.broadcast();
  final _errors = StreamController<TilawaException>.broadcast();
  final _chunks = Queue<Uint8List>();
  Uint8List _remainder = Uint8List(0);
  StreamSubscription<Uint8List>? _audio;
  StreamSubscription<RecordState>? _recordState;
  Future<void>? _draining, _starting, _stopping, _disposing;
  TilawaCaptureState _state = TilawaCaptureState.idle;
  bool _interruptionPending = false;
  bool _discardOnClose = false;
  static const _chunkBytes = 15360; // 480 ms client mono16kPCM16.
  Stream<TilawaCaptureState> get states => _states.stream;
  Stream<TilawaException> get errors => _errors.stream;
  TilawaCaptureState get state => _state;
  int get clientSampleRate => 16000;
  int get clientChannels => 1;
  bool get hardwareFormatVerified => false;

  static Future<TilawaMicrophone> open({
    required TilawaSession session,
    int maxPendingChunks = 4,
  }) async {
    if (maxPendingChunks < 1 ||
        maxPendingChunks > 8 ||
        session.info.config.maxChunkSamples < 7680) {
      throw const TilawaException(
        'invalidInput',
        'Capture needs a 480 ms session chunk limit and 1..8 pending chunks.',
      );
    }
    final capture = TilawaMicrophone._(session, maxPendingChunks);
    if (captureBindings[session] != null) {
      throw const TilawaException(
        'invalidState',
        'Session already has an attached microphone helper.',
      );
    }
    captureBindings[session] = () {
      capture._discardOnClose = true;
      return capture.dispose();
    };
    WidgetsBinding.instance.addObserver(capture);
    return capture;
  }

  void _stateTo(TilawaCaptureState state) {
    _state = state;
    if (!_states.isClosed) _states.add(state);
  }

  Future<void> start() {
    if (_disposing != null || _state == TilawaCaptureState.disposed) {
      return Future.error(
        const TilawaException('disposed', 'Capture is disposed.'),
      );
    }
    if (_starting != null) return _starting!;
    if (_state == TilawaCaptureState.capturing || _stopping != null) {
      return Future.error(
        const TilawaException('invalidState', 'Capture is active or stopping.'),
      );
    }
    _stateTo(TilawaCaptureState.starting);
    _starting = (() async {
      try {
        if (session.snapshot.state != TilawaLifecycle.ready &&
            session.snapshot.state != TilawaLifecycle.accepting) {
          throw const TilawaException(
            'invalidState',
            'Reset recognition before starting capture.',
          );
        }
        if (!await _recorder.hasPermission()) {
          throw const TilawaException(
            'microphonePermissionDenied',
            'Microphone permission denied.',
          );
        }
        if (WidgetsBinding.instance.lifecycleState !=
                AppLifecycleState.resumed ||
            _disposing != null) {
          throw const TilawaException(
            'captureInterrupted',
            'Capture requires the foreground.',
          );
        }
        final stream = await _recorder.startStream(
          const RecordConfig(
            encoder: AudioEncoder.pcm16bits,
            sampleRate: 16000,
            numChannels: 1,
            echoCancel: false,
            noiseSuppress: false,
            autoGain: false,
            audioInterruption: AudioInterruptionMode.pause,
          ),
        );
        if (WidgetsBinding.instance.lifecycleState !=
                AppLifecycleState.resumed ||
            _disposing != null) {
          await _recorder.stop();
          throw const TilawaException(
            'captureInterrupted',
            'Capture interrupted while starting.',
          );
        }
        _remainder = Uint8List(0);
        _chunks.clear();
        _interruptionPending = false;
        _stateTo(TilawaCaptureState.capturing);
        _audio = stream.listen(
          _capture,
          onError: (Object error) => _interrupt('captureDisconnected', error),
          onDone: () {
            if (_state == TilawaCaptureState.capturing) {
              _interrupt('captureDisconnected', null);
            }
          },
        );
        _recordState = _recorder.onStateChanged().listen((state) {
          if (_state == TilawaCaptureState.capturing &&
              state != RecordState.record) {
            _interrupt('audioFocusLoss', null);
          }
        }, onError: (Object error) => _interrupt('captureDisconnected', error));
      } catch (error) {
        _stateTo(TilawaCaptureState.failed);
        throw error is TilawaException
            ? error
            : TilawaException('captureFailed', '$error');
      }
    })().whenComplete(() => _starting = null);
    return _starting!;
  }

  void _capture(Uint8List bytes) {
    if (_state != TilawaCaptureState.capturing ||
        _interruptionPending ||
        _discardOnClose) {
      return;
    }
    if (bytes.length + _remainder.length + _chunks.length * _chunkBytes >
        maxPendingChunks * _chunkBytes) {
      _interrupt(
        'audioOverrun',
        const TilawaException(
          'audioOverrun',
          'Capture queue overflow; input continuity interrupted.',
        ),
      );
      return;
    }
    final joined = Uint8List(_remainder.length + bytes.length)
      ..setRange(0, _remainder.length, _remainder)
      ..setRange(_remainder.length, _remainder.length + bytes.length, bytes);
    var offset = 0;
    while (joined.length - offset >= _chunkBytes) {
      _chunks.add(
        Uint8List.fromList(joined.sublist(offset, offset + _chunkBytes)),
      );
      offset += _chunkBytes;
    }
    _remainder = Uint8List.fromList(joined.sublist(offset));
    _beginDrain();
  }

  Float32List _pcm(Uint8List bytes) {
    if (bytes.length.isOdd) {
      throw const TilawaException(
        'invalidAudio',
        'Incomplete PCM16 sample at capture end.',
      );
    }
    final view = ByteData.sublistView(bytes);
    return Float32List.fromList(
      List.generate(
        bytes.length ~/ 2,
        (i) => view.getInt16(i * 2, Endian.little) / 32768,
      ),
    );
  }

  void _beginDrain() {
    if (_draining != null) return;
    _draining =
        (() async {
              while (_chunks.isNotEmpty) {
                if (_discardOnClose) {
                  _chunks.clear();
                  return;
                }
                await session.feed(_pcm(_chunks.removeFirst()));
              }
            })()
            .catchError((Object error) {
              _chunks.clear();
              _remainder = Uint8List(0);
              if (!_discardOnClose) _interrupt('audioOverrun', error);
            })
            .whenComplete(() {
              _draining = null;
              if (_chunks.isNotEmpty) _beginDrain();
            });
  }

  Future<void> stopCapture() {
    if (_stopping != null) return _stopping!;
    _stopping = (() async {
      if (_starting != null) {
        try {
          await _starting;
        } catch (_) {
          /* Start failure already delivered. */
        }
      }
      if (_state != TilawaCaptureState.capturing) return;
      _stateTo(TilawaCaptureState.stopping);
      await _recorder.stop();
      await _audio?.cancel();
      await _recordState?.cancel();
      _audio = null;
      _recordState = null;
      await _draining;
      if (_remainder.isNotEmpty && !_discardOnClose) {
        await session.feed(_pcm(_remainder));
      }
      _remainder = Uint8List(0);
      _stateTo(TilawaCaptureState.idle);
    })().whenComplete(() => _stopping = null);
    return _stopping!;
  }

  void _interrupt(String reason, Object? error) {
    if (_interruptionPending || _state == TilawaCaptureState.disposed) return;
    _interruptionPending = true;
    unawaited(
      (() async {
        try {
          if (error != null && !_errors.isClosed) {
            _errors.add(
              error is TilawaException
                  ? error
                  : TilawaException('captureFailed', '$error'),
            );
          }
          try {
            await stopCapture();
          } catch (stopError) {
            if (!_errors.isClosed) {
              _errors.add(
                stopError is TilawaException
                    ? stopError
                    : TilawaException('captureFailed', '$stopError'),
              );
            }
          }
          await session.interrupt(TilawaInterruption(reason));
          if (_disposing == null) _stateTo(TilawaCaptureState.interrupted);
        } catch (failure) {
          if (!_errors.isClosed) {
            _errors.add(
              failure is TilawaException
                  ? failure
                  : TilawaException('captureFailed', '$failure'),
            );
          }
          if (_disposing == null) _stateTo(TilawaCaptureState.failed);
        }
      })(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed &&
        _state == TilawaCaptureState.capturing) {
      _interrupt('background', null);
    }
  }

  Future<void> dispose() {
    if (_disposing != null) return _disposing!;
    _disposing = (() async {
      captureBindings[session] = null;
      WidgetsBinding.instance.removeObserver(this);
      try {
        await stopCapture();
      } finally {
        await _audio?.cancel();
        await _recordState?.cancel();
        await _recorder.dispose();
        _chunks.clear();
        _remainder = Uint8List(0);
        _stateTo(TilawaCaptureState.disposed);
        unawaited(_states.close());
        unawaited(_errors.close());
      }
    })();
    return _disposing!;
  }
}
