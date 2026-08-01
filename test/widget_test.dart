import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'R-AI',
      home: Scaffold(
        appBar: AppBar(title: const Text('R-AI')),
        body: const Center(
          child: Text('Tests go here'),
        ),
      ),
    );
  }
}