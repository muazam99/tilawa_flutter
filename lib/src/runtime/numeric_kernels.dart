// Numeric acceleration of the pinned Tracker.feedOne recurrence.
// The upstream tracker keeps cursor/history/rollback/event behavior.
// Recurrences derived from Tilawa's MIT-licensed tracker.ts/alignment.ts;
// retained upstream copyright/license: assets/runtime/TILAWA_LICENSE.
import 'dart:typed_data';
import 'package:quickjs_engine/quickjs_engine.dart';

const nativeNumericKernelVersion = 'dart-f32-callback-v3';

// These callbacks receive only owned numeric copies, never JSRef values.
// The package's generic Dart-function wrapper recursively walks every byte
// looking for JSRef arguments. Avoid that unrelated traversal here.
final class _NumericFunction extends JSInvokable {
  _NumericFunction(this.function);
  final Function function;
  @override
  dynamic invoke(List args, [dynamic thisVal]) =>
      Function.apply(function, args);
  @override
  void destroy() {}
}

void installPinnedNumericKernels(JavascriptRuntime runtime) {
  final setter = runtime.evaluate('(key,value)=>{globalThis[key]=value}');
  (setter.rawResult as JSInvokable).invoke([
    'nativeTrackerKernel',
    _NumericFunction((
      Uint8List refBytes,
      Uint8List startBytes,
      Uint8List ayahBytes,
      Uint8List extraBytes,
      Uint8List costBytes,
    ) {
      final ref = refBytes;
      final starts = Int32List.view(startBytes.buffer);
      final ayahs = Int32List.view(ayahBytes.buffer);
      final extra = Float32List.view(extraBytes.buffer);
      final matrix = Float32List.view(costBytes.buffer);
      return _NumericFunction((
        Uint8List previousBytes,
        int hid,
        int cursorAyah,
        int cursorPos,
        num jumpCost,
        num repeatCost,
      ) {
        final prev = Float32List.view(previousBytes.buffer);
        final next = Float32List(ref.length + 1);
        var minimum = prev[0];
        for (var m = 1; m < prev.length; m++) {
          if (prev[m] < minimum) minimum = prev[m];
        }
        final jump = minimum + jumpCost;
        final repeat = minimum + repeatCost;
        next[0] = prev[0] + 1;
        if (starts[0] == 0) {
          final r = ayahs[0] == cursorAyah ? repeat : jump + extra[0];
          if (r < next[0]) next[0] = r;
        }
        final costRow = hid * 52;
        for (var m = 1; m <= ref.length; m++) {
          // Preserve float32 store before comparing insertion/deletion.
          next[m] = prev[m - 1] + matrix[costRow + ref[m - 1]];
          final insertion = prev[m] + 1;
          final deletion = next[m - 1] + 1;
          if (insertion < next[m]) next[m] = insertion;
          if (deletion < next[m]) next[m] = deletion;
        }
        for (var i = 0; i < starts.length; i++) {
          final m = starts[i];
          final restart = m <= cursorPos && ayahs[i] == cursorAyah
              ? repeat
              : jump + extra[i];
          if (restart < next[m]) {
            next[m] = restart;
            for (
              var j = m + 1;
              j <= ref.length && next[j - 1] + 1 < next[j];
              j++
            ) {
              next[j] = next[j - 1] + 1;
            }
          }
        }
        var bestCell = 0;
        var bestCost = next[0];
        var bestDistance = cursorPos.abs();
        for (var m = 1; m <= ref.length; m++) {
          final cost = next[m];
          final distance = (m - cursorPos).abs();
          if (cost < bestCost ||
              (cost == bestCost && distance < bestDistance)) {
            bestCost = cost;
            bestCell = m;
            bestDistance = distance;
          }
        }
        return [Uint8List.view(next.buffer), bestCell, bestCost];
      });
    }),
  ]);
  (setter.rawResult as JSInvokable).invoke([
    'nativeAlignGlobal',
    _NumericFunction((
      Uint8List heard,
      Uint8List reference,
      Uint8List costBytes,
      int from,
    ) {
      final costs = Float32List.view(costBytes.buffer);
      final n = heard.length, m = reference.length;
      final assign = Int32List(n)..fillRange(0, n, -1);
      if (n == 0 || m == 0) return Uint8List.view(assign.buffer);
      final columns = m + 1;
      var previous = Float32List(columns);
      var current = Float32List(columns);
      final trace = Uint8List((n + 1) * columns);
      for (var j = 0; j <= m; j++) {
        previous[j] = j.toDouble();
      }
      for (var i = 1; i <= n; i++) {
        current[0] = i.toDouble();
        final row = i * columns;
        final costRow = heard[i - 1] * 52;
        for (var j = 1; j <= m; j++) {
          current[j] = previous[j - 1] + costs[costRow + reference[j - 1]];
          var direction = 0;
          final up = previous[j] + 1, left = current[j - 1] + 1;
          if (up < current[j]) {
            current[j] = up;
            direction = 1;
          }
          if (left < current[j]) {
            current[j] = left;
            direction = 2;
          }
          trace[row + j] = direction;
        }
        final temporary = previous;
        previous = current;
        current = temporary;
      }
      var i = n, j = m;
      while (i > 0 || j > 0) {
        if (i == 0) {
          j--;
        } else if (j == 0) {
          i--;
        } else {
          final direction = trace[i * columns + j];
          if (direction == 0) {
            assign[i - 1] = from + j - 1;
            i--;
            j--;
          } else if (direction == 1) {
            i--;
          } else {
            j--;
          }
        }
      }
      return Uint8List.view(assign.buffer);
    }),
  ]);
  (setter.rawResult as JSInvokable).free();
}
