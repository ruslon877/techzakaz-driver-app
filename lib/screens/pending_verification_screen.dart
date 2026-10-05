import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class PendingVerificationScreen extends StatefulWidget {
  const PendingVerificationScreen({super.key, this.profile});

  final Map<String, dynamic>? profile;

  @override
  State<PendingVerificationScreen> createState() =>
      _PendingVerificationScreenState();
}

class _PendingVerificationScreenState extends State<PendingVerificationScreen> {
  static const _yellow = Color(0xFFF3C622);
  static const _supportPhone = '+77073443446';
  bool _refreshing = false;

  String get _driverName => widget.profile?['name']?.toString().trim() ?? '';
  String get _equipmentType =>
      widget.profile?['equipmentType']?.toString().trim() ?? '';
  bool get _isRejected =>
      widget.profile?['verificationStatus']?.toString().toLowerCase() ==
      'rejected';

  Future<void> _refreshStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showStatusMessage('Сессия завершилась. Войдите в аккаунт снова.');
      return;
    }
    setState(() => _refreshing = true);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('drivers')
          .doc(user.uid)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      if (snapshot.data()?['isVerified'] == true) {
        _showStatusMessage('Профиль подтверждён. Открываем радар...');
        // AuthGate слушает этот документ и автоматически откроет RadarScreen.
      } else {
        _showStatusMessage(
          'Проверка ещё не завершена. Мы сообщим, когда доступ будет открыт.',
        );
      }
    } on TimeoutException {
      _showStatusMessage(
        'Сервер долго не отвечает. Проверьте интернет и повторите попытку.',
      );
    } on FirebaseException catch (error) {
      final message = switch (error.code) {
        'permission-denied' =>
          'Нет доступа к профилю. Выйдите и войдите в аккаунт снова.',
        'unauthenticated' => 'Сессия завершилась. Войдите в аккаунт снова.',
        'unavailable' || 'deadline-exceeded' || 'network-request-failed' =>
          'Сервис временно недоступен. Проверьте интернет и повторите попытку.',
        _ => 'Не удалось обновить статус. Повторите попытку позже.',
      };
      _showStatusMessage(message);
    } catch (_) {
      _showStatusMessage('Не удалось обновить статус. Проверьте интернет.');
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  void _showStatusMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _callSupport() async {
    final uri = Uri(scheme: 'tel', path: _supportPhone);
    if (!await launchUrl(uri)) _showContactError();
  }

  Future<void> _openWhatsApp() async {
    final uri = Uri.parse('https://wa.me/${_supportPhone.substring(1)}');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _showContactError();
    }
  }

  void _showContactError() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Не удалось открыть приложение для связи.')),
    );
  }

  Future<void> _signOut() => FirebaseAuth.instance.signOut();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0C0A),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: _yellow.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: _yellow.withValues(alpha: 0.35)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.hourglass_top_rounded, color: _yellow, size: 38),
                        SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            _isRejected ? 'Профиль требует уточнения' : 'Профиль на проверке',
                            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    _isRejected
                        ? 'Нужна дополнительная информация'
                        : (_driverName.isEmpty ? 'Спасибо за регистрацию!' : 'Спасибо, $_driverName!'),
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    _isRejected
                        ? 'Мы не смогли подтвердить профиль по текущим данным. Свяжитесь со службой поддержки — специалист подскажет, что нужно исправить и как повторно пройти проверку.'
                        : 'Ваша регистрация принята. Мы проверяем данные водителя и спецтехники, чтобы подключить вас к базе сотрудничества.',
                    style: TextStyle(color: Colors.white70, height: 1.5, fontSize: 16),
                  ),
                  const SizedBox(height: 18),
                  _InfoCard(
                    icon: Icons.schedule_rounded,
                    title: _isRejected ? 'Что делать дальше' : 'Ожидаемый срок',
                    text: _isRejected
                        ? 'Позвоните или напишите в WhatsApp. Не создавайте новый профиль — поддержка поможет обновить данные.'
                        : 'Обычно проверка занимает до 24 часов. После подтверждения доступ к заказам откроется автоматически.',
                  ),
                  if (_equipmentType.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _InfoCard(
                      icon: Icons.local_shipping_outlined,
                      title: 'Заявленная техника',
                      text: _equipmentType,
                    ),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 54,
                    child: ElevatedButton.icon(
                      onPressed: _refreshing ? null : _refreshStatus,
                      icon: _refreshing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                            )
                          : const Icon(Icons.refresh_rounded),
                      label: Text(_refreshing ? 'Проверяем статус...' : 'Обновить статус'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _yellow,
                        foregroundColor: Colors.black,
                        disabledBackgroundColor: _yellow.withValues(alpha: 0.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _callSupport,
                    icon: const Icon(Icons.phone_outlined),
                    label: const Text('Позвонить в службу поддержки'),
                    style: _outlineStyle(),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _openWhatsApp,
                    icon: const Icon(Icons.chat_outlined),
                    label: const Text('Написать в WhatsApp'),
                    style: _outlineStyle(),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Служба поддержки: +7 707 344 3446',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                  const SizedBox(height: 24),
                  TextButton.icon(
                    onPressed: _signOut,
                    icon: const Icon(Icons.logout, size: 18),
                    label: const Text('Выйти из аккаунта'),
                    style: TextButton.styleFrom(foregroundColor: Colors.white60),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  ButtonStyle _outlineStyle() => OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: Color(0xFF3B3D34)),
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      );
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.icon, required this.title, required this.text});

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFF171914),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF292B25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFFF3C622), size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(text, style: const TextStyle(color: Colors.white60, height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
