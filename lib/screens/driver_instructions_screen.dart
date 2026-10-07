import 'package:flutter/material.dart';

class DriverInstructionsScreen extends StatelessWidget {
  const DriverInstructionsScreen({super.key});

  static const _yellow = Color(0xFFF3C622);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0C0A),
      appBar: AppBar(
        title: const Text('Как работать'),
        backgroundColor: const Color(0xFF0B0C0A),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
          children: const [
            Text(
              'Инструкция водителя',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 8),
            Text(
              'Коротко о том, как получать и выполнять заказы в ТехЗаказе.',
              style: TextStyle(color: Colors.white60, height: 1.4),
            ),
            SizedBox(height: 22),
            _InstructionStep(
              number: '01',
              icon: Icons.radar_rounded,
              title: 'Включите радар',
              text: 'Откройте радар, включите «На линии» и разрешите геолокацию. Выберите подходящий радиус поиска. Подходящие заявки появятся на карте и в списке.',
            ),
            _InstructionStep(
              number: '02',
              icon: Icons.assignment_outlined,
              title: 'Откройте заявку',
              text: 'Нажмите на маркер или уведомление. Пока вы не нажали «Взять в работу», заявку видят другие водители — они тоже могут связаться с клиентом. Просмотр карточки ничего не списывает.',
            ),
            _ImportantNotice(),
            _InstructionStep(
              number: '03',
              icon: Icons.check_circle_outline,
              title: 'Возьмите заказ',
              text: 'Нажимайте «Взять в работу» только после решения выполнить заказ. В этот момент заявка закрепляется за вами, исчезает с радаров остальных водителей, и они больше не смогут связаться с клиентом по этой заявке. Также списывается одна бесплатная заявка (если нет подписки) и увеличивается дневной счётчик.',
            ),
            _InstructionStep(
              number: '04',
              icon: Icons.navigation_outlined,
              title: 'Постройте маршрут',
              text: 'В карточке заказа доступны 2GIS, Яндекс.Навигатор и Google Maps. Выберите установленное приложение — маршрут построится по координатам объекта.',
            ),
            _InstructionStep(
              number: '05',
              icon: Icons.flag_outlined,
              title: 'Завершите заказ',
              text: 'После нажатия «Выехал на заказ» радар приостанавливается на 60 минут: новые заявки и push-уведомления не поступают. После истечения времени заказ завершится автоматически, а радар снова станет доступен. Если с клиентом не договорились, используйте кнопку «Не договорились».',
            ),
            _InstructionStep(
              number: '06',
              icon: Icons.speed_outlined,
              title: 'Лимиты',
              text: 'Можно взять не более 5 заказов в сутки по времени Алматы. Лимит считается только при нажатии «Взять в работу», а не при просмотре карточки. После регистрации доступно 20 бесплатных взятий; далее нужен активный тариф.',
            ),
            SizedBox(height: 12),
            _TipCard(),
          ],
        ),
      ),
    );
  }
}

class _InstructionStep extends StatelessWidget {
  const _InstructionStep({
    required this.number,
    required this.icon,
    required this.title,
    required this.text,
  });

  final String number;
  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF171914),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF292B25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Text(number, style: const TextStyle(color: _DriverInstructionsColors.yellow, fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              Icon(icon, color: _DriverInstructionsColors.yellow, size: 25),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(text, style: const TextStyle(color: Colors.white60, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ImportantNotice extends StatelessWidget {
  const _ImportantNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF3C622).withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF3C622), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF3C622).withValues(alpha: 0.12),
            blurRadius: 14,
            spreadRadius: 1,
          ),
        ],
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.priority_high_rounded, color: Color(0xFFF3C622), size: 27),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ВАЖНО: заявка закрепляется после взятия',
                  style: TextStyle(
                    color: Color(0xFFF3C622),
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 7),
                Text(
                  'До нажатия «Взять в работу» заявку видят все подходящие водители и могут связываться с клиентом. После взятия заявка исчезает с радаров остальных водителей и закрепляется только за вами.',
                  style: TextStyle(color: Colors.white, height: 1.4, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TipCard extends StatelessWidget {
  const _TipCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF3C622).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF3C622).withValues(alpha: 0.3)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lightbulb_outline_rounded, color: Color(0xFFF3C622)),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Совет: держите уведомления и геолокацию включёнными, чтобы не пропустить подходящий заказ.',
              style: TextStyle(color: Colors.white70, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _DriverInstructionsColors {
  static const yellow = Color(0xFFF3C622);
}
