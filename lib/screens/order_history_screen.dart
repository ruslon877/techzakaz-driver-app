import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class OrderHistoryScreen extends StatelessWidget {
  const OrderHistoryScreen({super.key});

  String _statusLabel(String status) {
    switch (status) {
      case 'accepted':
        return 'В работе';
      case 'completed':
        return 'Завершён';
      case 'cancelled':
        return 'Отменён';
      case 'active':
        return 'Возвращён на радар';
      default:
        return status;
    }
  }

  Color _statusColor(String status) => switch (status) {
        'completed' => Colors.greenAccent,
        'cancelled' => Colors.redAccent,
        'active' => Colors.orangeAccent,
        _ => const Color(0xFFF3C622),
      };

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Scaffold(body: Center(child: Text('Войдите в аккаунт')));
    final query = FirebaseFirestore.instance.collection('orders').where('driverId', isEqualTo: uid).limit(100);
    return Scaffold(
      backgroundColor: const Color(0xFF0B0C0A),
      appBar: AppBar(title: const Text('История заявок'), backgroundColor: const Color(0xFF0B0C0A)),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: query.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Не удалось загрузить историю. Проверьте интернет.')));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Color(0xFFF3C622)));
          final docs = [...snapshot.data!.docs]..sort((a, b) => _timestamp(b.data()).compareTo(_timestamp(a.data())));
          if (docs.isEmpty) return const _EmptyHistory();
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final data = docs[index].data();
              final status = data['status']?.toString() ?? 'unknown';
              final type = data['type']?.toString() ?? data['vehicleType']?.toString() ?? 'Спецтехника';
              final address = data['address']?.toString() ?? 'Адрес не указан';
              return Card(
                color: const Color(0xFF171914),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(14),
                  leading: CircleAvatar(backgroundColor: const Color(0xFFF3C622), foregroundColor: Colors.black, child: const Icon(Icons.local_shipping_outlined)),
                  title: Text(type, style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Padding(padding: const EdgeInsets.only(top: 6), child: Text(address, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white60))),
                  trailing: Text(_statusLabel(status), textAlign: TextAlign.right, style: TextStyle(color: _statusColor(status), fontSize: 12, fontWeight: FontWeight.w700)),
                ),
              );
            },
          );
        },
      ),
    );
  }

  DateTime _timestamp(Map<String, dynamic> data) {
    for (final key in ['completedAt', 'acceptedAt', 'startedAt', 'createdAt']) {
      final value = data[key];
      if (value is Timestamp) return value.toDate();
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();
  @override
  Widget build(BuildContext context) => const Center(child: Padding(padding: EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.history_rounded, color: Colors.white30, size: 56), SizedBox(height: 14), Text('История пока пуста', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)), SizedBox(height: 6), Text('Взятые и завершённые заявки появятся здесь.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white54))])));
}
