// Private interactive consumer of the new public microphone helper.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tilawa_flutter/microphone.dart';
import 'package:tilawa_flutter/tilawa_flutter.dart';

class MicrophoneProbe extends StatefulWidget {
  const MicrophoneProbe({super.key, required this.assets});
  final TilawaPreparedAssets assets;
  @override
  State<MicrophoneProbe> createState() => _MicrophoneProbeState();
}

class _MicrophoneProbeState extends State<MicrophoneProbe> {
  TilawaSession? _session;
  TilawaMicrophone? _microphone;
  final _subscriptions = <StreamSubscription<dynamic>>[];
  final _lines = <String>[];
  bool _busy = false;
  int _matches = 0, _progress = 0;

  void _log(String message) {
    debugPrint('TILAWA_SDK MIC $message');
    if (mounted) setState(() => _lines.add(message));
  }

  @override
  void initState() {
    super.initState();
    unawaited(_action(_open));
  }

  Future<void> _action(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await operation();
    } catch (error, stack) {
      _log('ERROR $error');
      debugPrint('$stack');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open() async {
    _session = await TilawaSession.open(assets: widget.assets);
    _subscriptions.add(
      _session!.events.listen((event) {
        if (event is TilawaVerseMatched) _matches++;
        if (event is TilawaWordProgress) _progress++;
        if (event is TilawaSessionEnded) {
          _log(
            'ENDED reason=${event.result.endReason.name} '
            'finalization=${event.result.finalization.name} '
            'samples=${event.result.processedSamples} '
            'matches=$_matches progress=$_progress',
          );
        }
        if (event is TilawaFailure) _log('FAILURE ${event.error}');
      }),
    );
    await _attach();
    _log('READY noAutomaticCapture=true');
  }

  Future<void> _attach() async {
    _microphone = await TilawaMicrophone.open(session: _session!);
    _subscriptions.add(
      _microphone!.states.listen((state) {
        _log('STATE ${state.name}');
      }),
    );
    _subscriptions.add(
      _microphone!.errors.listen((error) {
        _log('CAPTURE_ERROR $error');
      }),
    );
  }

  Future<void> _reset() async {
    await _microphone?.stopCapture();
    await _session!.reset();
    _matches = _progress = 0;
    _log('RESET ready=${_session!.snapshot.state.name}');
  }

  Future<void> _start() async {
    await _microphone!.start();
    _log(
      'STARTED clientRate=${_microphone!.clientSampleRate} '
      'channels=${_microphone!.clientChannels} '
      'hardwareVerified=${_microphone!.hardwareFormatVerified}',
    );
  }

  Future<void> _stop() async {
    await _microphone!.stopCapture();
    final result = await _session!.stop();
    final again = await _session!.stop();
    _log(
      'STOP samples=${result.processedSamples} '
      'verses=${result.engineSequence?.length} canonical=${identical(result, again)}',
    );
  }

  Future<void> _disposeSession() async {
    final helper = _microphone!;
    await _session!.dispose();
    if (helper.state != TilawaCaptureState.disposed) {
      throw StateError('Session did not dispose attached microphone');
    }
    _log('SESSION_DISPOSE helperDisposed=true');
  }

  Future<void> _recreate() async {
    await _session?.dispose();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    _matches = _progress = 0;
    await _open();
  }

  Future<void> _lifecycle() async {
    await _reset();
    await _start();
    await Future<void>.delayed(const Duration(seconds: 5));
    await _stop();
    await _microphone!.dispose();
    _log('HELPER_DISPOSE state=${_microphone!.state.name}');
    await _session!.reset();
    await _attach();
    await _start();
    await Future<void>.delayed(const Duration(seconds: 3));
    await _disposeSession();
    _log('LIFECYCLE_COMPLETE');
  }

  @override
  void dispose() {
    unawaited(_session?.dispose());
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('SDK microphone helper')),
    body: Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(8),
          child: Text(
            'Foreground-only, local recognition. Start requests permission. '
            'Recite, then Stop. Reset before another run.',
          ),
        ),
        Wrap(
          spacing: 8,
          children: [
            for (final control in <(String, Future<void> Function())>[
              ('Start', _start),
              ('Stop', _stop),
              ('Reset', _reset),
              ('Lifecycle check', _lifecycle),
              ('Dispose session', _disposeSession),
              ('Recreate', _recreate),
            ])
              ElevatedButton(
                onPressed: _busy ? null : () => _action(control.$2),
                child: Text(control.$1),
              ),
          ],
        ),
        if (_busy) const LinearProgressIndicator(),
        Expanded(
          child: ListView(
            reverse: true,
            children: _lines.reversed
                .map(
                  (line) => Padding(
                    padding: const EdgeInsets.all(6),
                    child: Text(line),
                  ),
                )
                .toList(),
          ),
        ),
      ],
    ),
  );
}
