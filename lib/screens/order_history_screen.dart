import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class OrderHistoryScreen extends StatefulWidget {
  const OrderHistoryScreen({super.key});

  @override
  State<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends State<OrderHistoryScreen> {
  String _filter = 'all';

  String _statusLabel(String status) {
    switch (status) {
      case 'in_progress':
        return 'Взята в работу';
      case 'accepted':
        return 'В работе';
      case 'completed':
        return 'Завершена';
      case 'cancelled':
        return 'Отменена';
      case 'declined':
        return 'Не договорились';
      default:
        return status;
    }
  }

  Color _statusColor(String status) => switch (status) {
        'completed' => Colors.greenAccent,
        'cancelled' => Colors.redAccent,
        'declined' => Colors.orangeAccent,
        _ => const Color(0xFFF3C622),
      };

  String _logicalStatus(String uid, Map<String, dynamic> data) {
    if (data['status']?.toString() == 'active' &&
        data['lastDriverId']?.toString() == uid) {
      return 'declined';
    }
    return data['status']?.toString() ?? 'unknown';
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(body: Center(child: Text('Войдите в аккаунт')));
    }
    final driverQuery = FirebaseFirestore.instance
        .collection('orders')
        .where('driverId', isEqualTo: uid)
        .limit(100);
    final declinedQuery = FirebaseFirestore.instance
        .collection('orders')
        .where('lastDriverId', isEqualTo: uid)
        .limit(100);

    return Scaffold(
      backgroundColor: const Color(0xFF0B0C0A),
      appBar: AppBar(
        title: const Text('История заявок'),
        backgroundColor: const Color(0xFF0B0C0A),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: driverQuery.snapshots(),
        builder: (context, driverSnapshot) {
          if (driverSnapshot.hasError) return _errorMessage();
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: declinedQuery.snapshots(),
            builder: (context, declinedSnapshot) {
              if (declinedSnapshot.hasError) return _errorMessage();
              if (!driverSnapshot.hasData || !declinedSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator(color: Color(0xFFF3C622)));
              }
              final byId = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
              for (final document in [...driverSnapshot.data!.docs, ...declinedSnapshot.data!.docs]) {
                byId[document.id] = document;
              }
              final docs = byId.values
                  .where((document) => _filter == 'all' || _logicalStatus(uid, document.data()) == _filter)
                  .toList()
                ..sort((a, b) => _timestamp(b.data()).compareTo(_timestamp(a.data())));

              return Column(
                children: [
                  _FilterBar(selected: _filter, onChanged: (value) => setState(() => _filter = value)),
                  Expanded(
                    child: docs.isEmpty
                        ? const _EmptyHistory()
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                            itemCount: docs.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (context, index) => _OrderTile(
                              data: docs[index].data(),
                              uid: uid,
                              status: _logicalStatus(uid, docs[index].data()),
                              statusLabel: _statusLabel(_logicalStatus(uid, docs[index].data())),
                              statusColor: _statusColor(_logicalStatus(uid, docs[index].data())),
                            ),
                          ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _errorMessage() => const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Не удалось загрузить историю. Проверьте интернет.'),
        ),
      );

  DateTime _timestamp(Map<String, dynamic> data) {
    for (final key in ['completedAt', 'declinedAt', 'acceptedAt', 'startedAt', 'createdAt']) {
      final value = data[key];
      if (value is Timestamp) return value.toDate();
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.selected, required this.onChanged});
  final String selected;
  final ValueChanged<String> onChanged;

  static const filters = <(String, String)>[
    ('all', 'Все'),
    ('in_progress', 'Взяты'),
    ('accepted', 'В работе'),
    ('completed', 'Завершены'),
    ('declined', 'Не договорились'),
    ('cancelled', 'Отменены'),
  ];

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 58,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          itemCount: filters.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, index) {
            final (value, label) = filters[index];
            final active = value == selected;
            return ChoiceChip(
              label: Text(label),
              selected: active,
              onSelected: (_) => onChanged(value),
              selectedColor: const Color(0xFFF3C622),
              backgroundColor: const Color(0xFF171914),
              labelStyle: TextStyle(color: active ? Colors.black : Colors.white70, fontWeight: FontWeight.w700),
            );
          },
        ),
      );
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.data, required this.uid, required this.status, required this.statusLabel, required this.statusColor});
  final Map<String, dynamic> data;
  final String uid;
  final String status;
  final String statusLabel;
  final Color statusColor;

  @override
  Widget build(BuildContext context) {
    final type = data['type']?.toString() ?? data['vehicleType']?.toString() ?? 'Спецтехника';
    final address = data['address']?.toString() ?? 'Адрес не указан';
    final started = _date(data['startedAt']);
    final completed = _date(data['completedAt']) ?? _date(data['acceptedAt']);
    final duration = started != null && completed != null ? completed.difference(started) : null;
    return Card(
      color: const Color(0xFF171914),
      child: ListTile(
        contentPadding: const EdgeInsets.all(14),
        leading: CircleAvatar(backgroundColor: const Color(0xFFF3C622), foregroundColor: Colors.black, child: const Icon(Icons.local_shipping_outlined)),
        title: Text(type, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(address, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white60)),
            if (duration != null) ...[
              const SizedBox(height: 5),
              Text('Время работы: ${_formatDuration(duration)}', style: const TextStyle(color: Colors.white38, fontSize: 12)),
            ],
          ]),
        ),
        trailing: Text(statusLabel, textAlign: TextAlign.right, style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.w700)),
      ),
    );
  }

  DateTime? _date(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.tryParse(value?.toString() ?? '');
  }

  static String _formatDuration(Duration duration) {
    final seconds = duration.inSeconds < 0 ? 0 : duration.inSeconds;
    return '${(seconds ~/ 3600).toString().padLeft(2, '0')}:${((seconds % 3600) ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();
  @override
  Widget build(BuildContext context) => const Center(child: Padding(padding: EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.history_rounded, color: Colors.white30, size: 56), SizedBox(height: 14), Text('История пока пуста', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)), SizedBox(height: 6), Text('По выбранному фильтру заявок нет.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white54))])));
}
