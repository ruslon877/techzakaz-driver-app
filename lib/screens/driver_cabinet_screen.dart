import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'order_history_screen.dart';

class DriverCabinetScreen extends StatelessWidget {
  const DriverCabinetScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Scaffold(body: Center(child: Text('Войдите в аккаунт')));
    final ref = FirebaseFirestore.instance.collection('drivers').doc(user.uid);
    return Scaffold(
      backgroundColor: const Color(0xFF0B0C0A),
      appBar: AppBar(title: const Text('Кабинет'), backgroundColor: const Color(0xFF0B0C0A)),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: ref.snapshots(),
        builder: (context, snapshot) {
          final data = snapshot.data?.data() ?? {};
          final name = data['name']?.toString() ?? 'Водитель';
          final type = data['equipmentType']?.toString() ?? 'Тип не указан';
          final plate = data['licensePlate']?.toString() ?? 'Не указан';
          final verified = data['isVerified'] == true;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: const Color(0xFF171914), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFF303229))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const CircleAvatar(radius: 30, backgroundColor: Color(0xFFF3C622), child: Icon(Icons.person, color: Colors.black, size: 32)),
                  const SizedBox(height: 16),
                  Text(name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text(type, style: const TextStyle(color: Color(0xFFF3C622), fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('Госномер: $plate', style: const TextStyle(color: Colors.white60)),
                  const SizedBox(height: 16),
                  Chip(
                    avatar: Icon(verified ? Icons.verified : Icons.hourglass_top, size: 18, color: verified ? Colors.greenAccent : const Color(0xFFF3C622)),
                    label: Text(verified ? 'Профиль подтверждён' : 'Профиль на проверке'),
                    backgroundColor: const Color(0xFF25271F),
                  ),
                ]),
              ),
              const SizedBox(height: 18),
              const Text('Ваша работа', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              _CabinetTile(icon: Icons.history_rounded, title: 'История заявок', subtitle: 'Взятые и выполненные заказы', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OrderHistoryScreen()))),
              _CabinetTile(icon: Icons.help_outline_rounded, title: 'Инструкция', subtitle: 'Как принимать и завершать заказы', onTap: () => _showInstructions(context)),
            ],
          );
        },
      ),
    );
  }

  void _showInstructions(BuildContext context) => showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF171914),
          title: const Text('Как работать'),
          content: const Text('Будьте на линии, открывайте подходящие заявки на карте, связывайтесь с клиентом и берите заказ только после согласования.', style: TextStyle(color: Colors.white70, height: 1.5)),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Понятно'))],
        ),
      );
}

class _CabinetTile extends StatelessWidget {
  const _CabinetTile({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
        color: const Color(0xFF171914),
        child: ListTile(leading: Icon(icon, color: const Color(0xFFF3C622)), title: Text(title), subtitle: Text(subtitle, style: const TextStyle(color: Colors.white54)), trailing: const Icon(Icons.chevron_right), onTap: onTap),
      );
}
