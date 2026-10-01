import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const TechZakazDriverApp());
}

class TechZakazDriverApp extends StatelessWidget {
  const TechZakazDriverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ТехЗаказ Водитель',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFF3C622)),
        useMaterial3: true,
      ),
      home: const Scaffold(
        body: Center(child: Text('ТехЗаказ Водитель')),
      ),
    );
  }
}
