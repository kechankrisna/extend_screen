import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'package:extend_screen/extend_screen.dart';

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Extendscreen Example',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MainWindowPage(),
    );
  }
}

class MainWindowPage extends StatefulWidget {
  const MainWindowPage({super.key});

  @override
  State<MainWindowPage> createState() => _MainWindowPageState();
}

class _MainWindowPageState extends State<MainWindowPage> {
  MultiWindowManager? _manager;
  bool _supported = false;
  bool _loading = true;

  // ── Desktop state ──────────────────────────────────────────────────────────
  final ValueNotifier<int> _counter = ValueNotifier(0);

  // ── Android POS state ──────────────────────────────────────────────────────
  final ValueNotifier<List<Map<String, dynamic>>> _items = ValueNotifier([]);
  final ValueNotifier<double> _total = ValueNotifier(0.0);

  /// 100 ms debounce: rapid taps are batched into one MethodChannel call.
  Timer? _debounce;

  int _productIndex = 0;

  static const _dummyProducts = [
    {'name': 'Coffee', 'price': 3.50},
    {'name': 'Sandwich', 'price': 6.75},
    {'name': 'Juice', 'price': 2.99},
    {'name': 'Cake Slice', 'price': 4.25},
    {'name': 'Water', 'price': 1.50},
  ];

  @override
  void initState() {
    super.initState();
    MultiWindowManager.instance().then((m) async {
      _manager = m;
      final supported = await m.isSupported();
      if (mounted) {
        setState(() {
          _supported = supported;
          _loading = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _counter.dispose();
    _items.dispose();
    _total.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // ── Android helpers ────────────────────────────────────────────────────────

  void _syncSubDisplay() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 100), () {
      _manager?.sendStateToSubDisplay(
        OrderSummaryState(
          items: List<Map<String, dynamic>>.from(_items.value),
          total: _total.value,
        ),
      );
    });
  }

  void _addItem() {
    final product = _dummyProducts[_productIndex % _dummyProducts.length];
    _productIndex++;

    final updated = List<Map<String, dynamic>>.from(_items.value);
    final existingIndex =
        updated.indexWhere((i) => i['name'] == product['name']);

    if (existingIndex >= 0) {
      updated[existingIndex] = {
        'name': product['name'],
        'qty': (updated[existingIndex]['qty'] as int) + 1,
        'price': product['price'],
      };
    } else {
      updated.add({
        'name': product['name'] as String,
        'qty': 1,
        'price': (product['price'] as num).toDouble(),
      });
    }

    _items.value = updated;
    _total.value = updated.fold(
      0.0,
      (sum, i) => sum + (i['price'] as double) * (i['qty'] as int),
    );
    _syncSubDisplay();
  }

  void _sendPayment() {
    _manager?.sendStateToSubDisplay(PaymentPromptState(total: _total.value));
  }

  void _newOrder() {
    _debounce?.cancel();
    _items.value = [];
    _total.value = 0.0;
    _productIndex = 0;
    _manager?.sendStateToSubDisplay(const IdleState());
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_supported) {
      return const _UnsupportedBanner();
    }
    if (!kIsWeb && Platform.isAndroid) {
      return _buildAndroidPOS(context);
    }
    return _buildDesktop(context);
  }

  // ── Desktop layout ─────────────────────────────────────────────────────────

  Widget _buildDesktop(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Extendscreen Example — Main Window'),
        actions: [
          TextButton.icon(
            onPressed: () => _manager?.closeAll(),
            icon: const Icon(Icons.close),
            label: const Text('Close All'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Main window counter\n(independent from sub-windows):',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ValueListenableBuilder<int>(
              valueListenable: _counter,
              builder: (context, value, _) => Text(
                '$value',
                style: Theme.of(context).textTheme.displayLarge,
              ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () => _manager?.openSubWindow({}),
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open Sub Window (full screen)'),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => _manager?.openSubWindow(
                {},
                size: const SubWindowSize.centered(width: 640, height: 480),
              ),
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open Sub Window (640 × 480 centred)'),
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

  // ── Android POS layout ─────────────────────────────────────────────────────

  Widget _buildAndroidPOS(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('POS — Cashier Screen'),
      ),
      body: Column(
        children: [
          Expanded(
            child: ValueListenableBuilder<List<Map<String, dynamic>>>(
              valueListenable: _items,
              builder: (context, items, _) {
                if (items.isEmpty) {
                  return const Center(
                    child: Text(
                      'No items yet.\nTap "Add Item" to start an order.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 18, color: Colors.grey),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  separatorBuilder: (context, index) => const Divider(),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final price =
                        (item['price'] as double) * (item['qty'] as int);
                    return ListTile(
                      title: Text(item['name'] as String),
                      subtitle: Text('Qty: ${item['qty']}'),
                      trailing: Text(
                        '\$${price.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          ValueListenableBuilder<double>(
            valueListenable: _total,
            builder: (context, total, _) => ColoredBox(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Total',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '\$${total.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _addItem,
                    icon: const Icon(Icons.add_shopping_cart),
                    label: const Text('Add Item'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: Colors.green.shade700),
                    onPressed: _sendPayment,
                    icon: const Icon(Icons.payment),
                    label: const Text('Payment'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _newOrder,
                    icon: const Icon(Icons.refresh),
                    label: const Text('New Order'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Unsupported platform banner ────────────────────────────────────────────────

class _UnsupportedBanner extends StatelessWidget {
  const _UnsupportedBanner();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.desktop_access_disabled,
                size: 64,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 24),
              Text(
                'Multi-window not supported on this platform.',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              const Text(
                'Run on Windows, macOS, Linux, or an Android device with a '
                'secondary display connected.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
