import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../screens/driver_cabinet_screen.dart';
import '../screens/order_history_screen.dart';

class DriverDrawer extends StatelessWidget {
  const DriverDrawer({super.key, this.onInstructions});

  final VoidCallback? onInstructions;
  static const yellow = Color(0xFFF3C622);
  static const supportPhone = '+77073443446';

  Future<void> _supportCall(BuildContext context) async {
    final ok = await launchUrl(
      Uri(scheme: 'tel', path: supportPhone),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось открыть звонилку')),
      );
    }
  }

  Future<void> _supportWhatsApp(BuildContext context) async {
    final ok = await launchUrl(
      Uri.parse('https://wa.me/${supportPhone.substring(1)}'),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось открыть WhatsApp')),
      );
    }
  }

  void _openInstructions(BuildContext context) {
    Navigator.pop(context);
    if (onInstructions != null) {
      onInstructions!();
      return;
    }
    showDialog<void>(context: context, builder: (_) => const _InstructionsDialog());
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Drawer(
      backgroundColor: const Color(0xFF11120E),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 12, 20),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: yellow,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.construction, color: Colors.black, size: 28),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('ТехЗаказ', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                        Text('ТЯЖЁЛАЯ ТЕХНИКА · ЛЁГКИЙ ЗАКАЗ', style: TextStyle(color: yellow, fontSize: 8, letterSpacing: .7)),
                      ],
                    ),
                  ),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                ],
              ),
            ),
            const Divider(color: Color(0xFF292B25), height: 1),
            _SectionLabel('НАВИГАЦИЯ'),
            _DrawerItem(
              icon: Icons.radar_rounded,
              title: 'Радар заявок',
              onTap: () => Navigator.pop(context),
            ),
            _DrawerItem(
              icon: Icons.person_outline_rounded,
              title: 'Кабинет',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const DriverCabinetScreen()));
              },
            ),
            _DrawerItem(
              icon: Icons.history_rounded,
              title: 'История заявок',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const OrderHistoryScreen()));
              },
            ),
            _DrawerItem(
              icon: Icons.menu_book_outlined,
              title: 'Как брать заказы',
              onTap: () => _openInstructions(context),
            ),
            _SectionLabel('ПОДДЕРЖКА'),
            _DrawerItem(
              icon: Icons.phone_outlined,
              title: 'Позвонить в поддержку',
              subtitle: '+7 707 344 3446',
              onTap: () => _supportCall(context),
            ),
            _DrawerItem(
              icon: Icons.chat_outlined,
              title: 'Поддержка в WhatsApp',
              onTap: () => _supportWhatsApp(context),
            ),
            const Spacer(),
            if (user != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => FirebaseAuth.instance.signOut(),
                    icon: const Icon(Icons.logout_outlined),
                    label: const Text('Выйти из аккаунта'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white60,
                      side: const BorderSide(color: Color(0xFF3B3D34)),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(text, style: const TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.4)),
        ),
      );
}

class _DrawerItem extends StatelessWidget {
  const _DrawerItem({required this.icon, required this.title, required this.onTap, this.subtitle});
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 2),
        leading: Icon(icon, color: DriverDrawer.yellow, size: 25),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: subtitle == null ? null : Text(subtitle!, style: const TextStyle(color: Colors.white38, fontSize: 12)),
        onTap: onTap,
      );
}

class _InstructionsDialog extends StatelessWidget {
  const _InstructionsDialog();
  @override
  Widget build(BuildContext context) => AlertDialog(
        backgroundColor: const Color(0xFF171914),
        title: const Text('Как брать заказы'),
        content: const SingleChildScrollView(
          child: Text(
            '1. Включите статус «На линии».\n\n2. На карте появятся подходящие заявки рядом с вами.\n\n3. Откройте заявку, проверьте адрес и позвоните клиенту.\n\n4. Нажмите «Взять в работу».\n\n5. После подтверждения выезда радар будет приостановлен на время текущего заказа.',
            style: TextStyle(color: Colors.white70, height: 1.5),
          ),
        ),
        actions: [TextButton(onPressed: Navigator.of(context).pop, child: const Text('Понятно'))],
      );
}
