import 'package:flutter/material.dart';

import 'recitation_demo.dart';

void main() => runApp(const TilawaExample());

class TilawaExample extends StatelessWidget {
  const TilawaExample({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Tilawa example',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff166534)),
      useMaterial3: true,
      fontFamily: 'Roboto',
    ),
    darkTheme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff166534),
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
      fontFamily: 'Roboto',
    ),
    home: const RecitationDemo(),
  );
}
