import 'package:flutter/material.dart';
import 'screens/reader_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const InfoxApp());
}

class InfoxApp extends StatelessWidget {
  const InfoxApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'InfoX Offline',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF7B4FE0)),
      scaffoldBackgroundColor: const Color(0xFFF7F5FB),
      useMaterial3: true,
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF7B4FE0),
        foregroundColor: Colors.white,
      ),
    ),
    home: const ReaderScreen(),
  );
}
