import 'package:flutter/material.dart';

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

  @override
  void dispose() {
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
