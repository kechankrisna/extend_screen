import 'dart:async';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:extend_screen/extend_screen.dart';

/// Sub-window application — runs as a completely independent Flutter engine
/// (separate OS process on desktop). Has no shared state with the main window.
class SubWindowApp extends StatelessWidget {
  const SubWindowApp({
    super.key,
    required this.windowId,
    required this.argument,
  });

  final int windowId;
  final Map<String, dynamic> argument;

  @override
  Widget build(BuildContext context) {
    final windowNumber =
        (argument['windowNumber'] as num?)?.toInt() ?? windowId;
    return MaterialApp(
      title: 'Sub Window $windowNumber',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: SubWindowPage(windowNumber: windowNumber),
    );
  }
}

class SubWindowPage extends StatefulWidget {
  const SubWindowPage({
    super.key,
    required this.windowNumber,
  });

  final int windowNumber;

  @override
  State<SubWindowPage> createState() => _SubWindowPageState();
}

class _SubWindowPageState extends State<SubWindowPage> {
  final ValueNotifier<int> _counter = ValueNotifier(0);

  Map<String, dynamic>? _receivedState;
  StreamSubscription<Map<String, dynamic>>? _subscription;

  @override
  void initState() {
    super.initState();
    MultiWindowManager.instance().then((manager) {
      _subscription = manager.receiveStateFromMainDisplay().listen((state) {
        log(  'Window ${widget.windowNumber} received state from main display: $state');
        if (mounted) setState(() => _receivedState = state);
      });
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _counter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text('Sub Window ${widget.windowNumber}'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Independent counter for this window:'),
            const SizedBox(height: 16),
            ValueListenableBuilder<int>(
              valueListenable: _counter,
              builder: (context, value, _) => Text(
                '$value',
                style: Theme.of(context).textTheme.displayLarge,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Window ID: ${widget.windowNumber}',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.grey),
            ),
            const SizedBox(height: 32),
            const Divider(indent: 40, endIndent: 40),
            const SizedBox(height: 16),
            const Text(
              'Message from main window:',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 8),
            if (_receivedState == null)
              const Text(
                '—',
                style: TextStyle(fontSize: 20, color: Colors.grey),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Card(
                  color: Colors.teal.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      _receivedState!.entries
                          .map((e) => '${e.key}: ${e.value}')
                          .join('\n'),
                      style: const TextStyle(fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _counter.value++,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ),
    );
  }
}
