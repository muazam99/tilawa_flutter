// Native inference with the pinned matching core, owned by a worker isolate.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:quickjs_engine/quickjs_engine.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import '../adapter.dart';
import '../models.dart';
import 'numeric_kernels.dart';

final class NativeCoreAdapter implements TilawaEngineAdapter {
  NativeCoreAdapter(this.sink);
  final TilawaObservationSink sink;
  JavascriptRuntime? js;
  OrtSession? ort;
  List<Map<String, dynamic>> inputs = [];
  Map<String, OrtValue> states = {};
  final ownedTensors = <OrtValue>{};
  Timer? pump;
  Future<void> nativeWork = Future.value();
  final pending = <int, Completer<Map<String, Object?>>>{};
  int nextOperation = 0;

  bool closed = false;
  @override
  String get id => 'native-ort-quickjs';
  @override
  String get version => 'ort-1.24.2-quickjs-ng0140-dart-f32-callback-v3';
  @override
  TilawaCapabilities get capabilities => TilawaCapabilities(
    observations: {
      'verse_candidate',
      'verse_match',
      'word_progress',
      'raw_transcript',
      'final_sequence',
      'debug',
    },
  );
  Future<void> initializeFiles(
    Map<String, File> files,
    TilawaRecognitionConfig config,
    String bridgeSource, {
    int intraOpNumThreads = 1,
    bool useArena = false,
    bool matching = true,
  }) async {
    final io =
        jsonDecode(await files['io.json']!.readAsString())
            as Map<String, dynamic>;
    inputs = (io['inputs'] as List)
        .map((x) => Map<String, dynamic>.from(x as Map))
        .toList();
    ort = await OnnxRuntime().createSession(
      files['model.onnx']!.path,
      options: OrtSessionOptions(
        intraOpNumThreads: intraOpNumThreads,
        interOpNumThreads: 1,
        providers: [OrtProvider.CPU],
        useArena: useArena,
      ),
    );
    await resetStates();
    if (!matching) return;
    js = QuickJsRuntime2(stackSize: 1024 * 1024);
    installPinnedNumericKernels(js!);
    js!.onMessage('nativeProbe', (dynamic message) {
      final data = Map<String, dynamic>.from(message as Map);
      if (data['kind'] == 'event') {
        if (!closed) sink(Map<String, Object?>.from(data['event'] as Map));
      } else if (data['kind'] == 'reply') {
        final reply = pending.remove(data['id']);
        if (reply != null) {
          if (data['error'] != null) {
            reply.completeError(
              TilawaException('inferenceFailed', '${data['error']}'),
            );
          } else {
            reply.complete(Map<String, Object?>.from(data['result'] as Map));
          }
        }
      } else if (data['kind'] == 'infer') {
        nativeWork = nativeWork.then((_) => infer(data)).catchError((
          Object error,
        ) {
          if (!closed) {
            final failure = TilawaException(
              'inferenceFailed',
              'Native tensor cleanup: $error',
            );
            for (final operation in pending.values) {
              operation.completeError(failure);
            }
            pending.clear();
            sink({'type': '_runtime_failure', 'message': failure.message});
          }
        });
      }
    });
    final loaded = js!.evaluate(bridgeSource);
    if (loaded.isError) {
      throw StateError('Native JS load: ${loaded.stringResult}');
    }
    pump = Timer.periodic(const Duration(milliseconds: 2), (_) {
      if (!closed) js?.executePendingJob();
    });
    await call('initialize', {
      'corpus': jsonDecode(await files['corpus.json']!.readAsString()),
      'io': io,
      'minWordFraction': config.minWordFraction,
      'enableFallback': config.enableFallback,
      'fallbackMaxDistance': config.fallbackMaxDistance,
      'stayOnSurah': config.stayOnSurah,
      'tailSeconds': config.tailDuration.inMicroseconds / 1000000,
      'debug': config.diagnostics,
    });
  }

  Future<void> resetStates() async {
    final old = states;
    states = {};
    await Future.wait(old.values.map(releaseTensor));
    await Future.wait(
      inputs.where((x) => x['name'] != 'x').map((input) async {
        final dims = (input['dims'] as List).cast<int>();
        final count = dims.fold<int>(1, (n, d) => n * d);
        final tensor = await OrtValue.fromList(
          input['dtype'] == 'int64' ? Int64List(count) : Float32List(count),
          dims,
        );
        ownedTensors.add(tensor);
        // Publish ownership immediately so partial initialization can clean up.
        states[input['name'] as String] = tensor;
      }),
    );
  }

  Future<void> releaseTensor(OrtValue tensor) async {
    await tensor.dispose();
    ownedTensors.remove(tensor);
  }

  Future<void> infer(
    Map<String, dynamic> data, {
    void Function(Map<String, Object?>? value, String? error)? deliver,
  }) async {
    OrtValue? x;
    Map<String, OrtValue> outputs = {};
    try {
      x = await OrtValue.fromList(
        Float32List.fromList(
          (data['x'] as List).map((n) => (n as num).toDouble()).toList(),
        ),
        (data['dims'] as List).cast<int>(),
      );
      ownedTensors.add(x);

      outputs = await ort!.run({'x': x, ...states});
      ownedTensors.addAll(outputs.values);

      final logits = outputs['log_probs']!;
      final values = await logits.asFlattenedList();
      final next = <String, OrtValue>{};
      final descriptions = <Map<String, Object?>>[];
      for (final input in inputs.where((x) => x['name'] != 'x')) {
        final name = input['name'] as String;
        final value = outputs['new_$name']!;
        next[name] = value;
        descriptions.add({
          'name': name,
          'type': input['dtype'],
          'dims': value.shape,
          if (name == 'processed_lens')
            'processedLens': '${(await value.asFlattenedList()).first}',
        });
      }
      final old = states;
      states = next;

      await Future.wait(
        [
          ...old.values,
          ...outputs.entries
              .where((x) => !next.values.contains(x.value))
              .map((x) => x.value),
        ].map(releaseTensor),
      );

      outputs = {};
      if (!closed) {
        final result = <String, Object?>{
          'logProbs': values,
          'logDims': logits.shape,
          'states': descriptions,
        };
        if (deliver != null) {
          deliver(result, null);
        } else {
          js!.evaluate(
            'nativeDeliver(${data['id']},${jsonEncode(result)},null)',
          );
        }
      }
    } catch (error) {
      for (final value in outputs.values) {
        if (!states.values.contains(value) && ownedTensors.contains(value)) {
          await releaseTensor(value);
        }
      }
      if (!closed) {
        if (deliver != null) {
          deliver(null, '$error');
        } else {
          js?.evaluate(
            'nativeDeliver(${data['id']},null,${jsonEncode('$error')})',
          );
        }
      }
    } finally {
      if (x != null) await releaseTensor(x);
    }
  }

  Future<Map<String, Object?>> call(
    String method, [
    Map<String, Object?> data = const {},
  ]) async {
    if (closed) {
      throw const TilawaException('disposed', 'Native runtime disposed');
    }
    final id = ++nextOperation;
    final completion = Completer<Map<String, Object?>>();
    pending[id] = completion;
    try {
      final evaluated = js!.evaluate(
        'nativeOperation(${jsonEncode(method)},${jsonEncode(data)}).then('
        'result=>sendMessage("nativeProbe",JSON.stringify({kind:"reply",id:$id,result})),'
        'error=>sendMessage("nativeProbe",JSON.stringify({kind:"reply",id:$id,error:String(error)})))',
      );
      if (evaluated.isError) throw StateError(evaluated.stringResult);
      // The facade bounds caller waits. Never report an operation finished while
      // its native inference still owns tensors; cleanup must await real work.
      return await completion.future;
    } finally {
      pending.remove(id);
    }
  }

  TilawaEngineSnapshot snapshot(Map<String, Object?> value) =>
      TilawaEngineSnapshot(
        consumedSamples: value['samples'] as int,
        trackingState: value['state'] == 'tracking'
            ? TilawaTrackingState.tracking
            : value['state'] == 'searching'
            ? TilawaTrackingState.searching
            : TilawaTrackingState.unknown,
        transcript: value['transcript'] as String,
        score: (value['score'] as num?)?.toDouble(),
        sequence: (value['sequence'] as List?)?.map(
          (x) => TilawaSequenceVerse(
            TilawaAyahRef(x['surah'] as int, x['ayah'] as int),
            (x['confidence'] as num).toDouble(),
          ),
        ),
      );
  @override
  Future<TilawaEngineSnapshot> feed(Float32List pcm) async =>
      snapshot(await call('feed', {'pcm': pcm.toList()}));
  @override
  Future<TilawaEngineSnapshot> stop() async => snapshot(await call('stop'));

  @override
  Future<TilawaEngineSnapshot> reset() async {
    await resetStates();

    return snapshot(await call('reset'));
  }

  @override
  Future<int> describeAyah(TilawaAyahRef ayah) async =>
      (await call('wordCount', {
            'surah': ayah.surah,
            'ayah': ayah.ayah,
          }))['words']
          as int;
  @override
  Future<void> dispose() async {
    if (closed) return;
    await nativeWork;
    closed = true;
    pump?.cancel();
    for (final operation in pending.values) {
      operation.completeError(
        const TilawaException('disposed', 'Native runtime disposed'),
      );
    }
    pending.clear();
    final runtime = js;
    js = null;
    if (runtime != null) {
      JavascriptRuntime.channelFunctionsRegistered.remove(
        runtime.getEngineInstanceId(),
      );
      runtime.dispose();
    }
    await Future.wait(ownedTensors.toList().map(releaseTensor));
    states.clear();
    await ort?.close();
    ort = null;
  }
}
