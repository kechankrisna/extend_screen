import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:extend_screen/extend_screen.dart';

/// Dart entry point for the secondary-display Flutter engine on Android.
///
/// The `@pragma('vm:entry-point')` annotation prevents tree-shaking from
/// removing this function, which is invoked by [ExtendScreenPlugin.kt] via
/// [DartExecutor.DartEntrypoint].
///
/// This runs in a completely separate [FlutterEngine] from the main app —
/// its own widget tree, state, and lifecycle.
@pragma('vm:entry-point')
void subScreenMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SubScreenApp());
}

class SubScreenApp extends StatefulWidget {
  const SubScreenApp({super.key});

  @override
  State<SubScreenApp> createState() => _SubScreenAppState();
}

class _SubScreenAppState extends State<SubScreenApp> {
  static const _channel = MethodChannel('sub_screen_commands');

  SubDisplayState _state = const IdleState();

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'updateState') {
        setState(() {
          _state = SubDisplayState.fromJson(
            Map<String, dynamic>.from(call.arguments as Map),
          );
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: switch (_state) {
        IdleState() => const IdleScreen(),
        OrderSummaryState s =>
          OrderSummaryScreen(items: s.items, total: s.total),
        PaymentPromptState s => PaymentPromptScreen(total: s.total),
      },
    );
  }
}

// ─── Sub-screen UI widgets ────────────────────────────────────────────────────

class IdleScreen extends StatelessWidget {
  const IdleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF1A237E),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.store, size: 80, color: Colors.white),
            SizedBox(height: 24),
            Text(
              'Welcome',
              style: TextStyle(
                color: Colors.white,
                fontSize: 48,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Please wait for the cashier',
              style: TextStyle(color: Colors.white70, fontSize: 20),
            ),
          ],
        ),
      ),
    );
  }
}

class OrderSummaryScreen extends StatelessWidget {
  const OrderSummaryScreen({
    super.key,
    required this.items,
    required this.total,
  });

  final List<Map<String, dynamic>> items;
  final double total;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Order'),
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (context, index) => const Divider(),
              itemBuilder: (context, index) {
                final item = items[index];
                final name = item['name'] as String? ?? '';
                final qty = item['qty'] as int? ?? 1;
                final price = (item['price'] as num?)?.toDouble() ?? 0.0;
                return ListTile(
                  title: Text(name),
                  subtitle: Text('Qty: $qty'),
                  trailing: Text(
                    '\$${(price * qty).toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                );
              },
            ),
          ),
          ColoredBox(
            color: const Color(0xFF1565C0),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Total',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '\$${total.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PaymentPromptScreen extends StatelessWidget {
  const PaymentPromptScreen({super.key, required this.total});

  final double total;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1B5E20),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.payment, size: 80, color: Colors.white),
            const SizedBox(height: 24),
            const Text(
              'Total Due',
              style: TextStyle(color: Colors.white70, fontSize: 24),
            ),
            const SizedBox(height: 8),
            Text(
              '\$${total.toStringAsFixed(2)}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 64,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              'Please proceed to payment',
              style: TextStyle(color: Colors.white70, fontSize: 20),
            ),
          ],
        ),
      ),
    );
  }
}
