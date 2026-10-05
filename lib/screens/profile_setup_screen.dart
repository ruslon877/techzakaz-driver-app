import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

const equipmentCatalog = <String, List<String>>{
  'Подъемная техника': [
    'Автокран',
    'Манипулятор (КМУ)',
    'Автовышка',
    'Телескопический погрузчик',
    'Ножничный/Коленчатый подъемник',
  ],
  'Земляные работы': [
    'Экскаватор-погрузчик',
    'Гусеничный экскаватор',
    'Колесный экскаватор',
    'Мини-экскаватор',
    'Фронтальный погрузчик',
    'Мини-погрузчик (Bobcat)',
    'Бульдозер',
    'Ямобур',
    'Бара',
    'Грейферный экскаватор',
  ],
  'Грузоперевозки': [
    'Пикап/Микроавтобус (до 1т)',
    'Газель/Porter',
    'Среднетоннажник (до 5т)',
    'Десятитонник',
    'Длинномер (открытый борт)',
    'Фура/Тент (20т)',
    'Рефрижератор',
    'Изотерм',
    'Грузовик с гидробортом',
    'Лесовоз/Трубовоз',
  ],
  'Эвакуация и спецперевозки': [
    'Эвакуатор лебедочный',
    'Эвакуатор-манипулятор',
    'Грузовой эвакуатор',
    'Трал',
    'Тягач',
  ],
  'Самосвалы и сыпучие': [
    'Самосвал легкий (до 10т)',
    'Самосвал тяжелый (20-40т)',
    'Тонар',
    'Зерновоз',
  ],
  'Коммунальная техника': [
    'Ассенизатор',
    'Илосос',
    'Каналопромывочная',
    'Поливомоечная',
    'Трактор с щеткой',
    'Снегоуборщик',
    'Мусоровоз',
    'Пескоразбрасыватель',
  ],
  'Бетон и стройоборудование': [
    'Миксер',
    'Автобетононасос',
    'Стационарный бетононасос',
    'Компрессор',
    'Передвижной генератор на колесах',
    'Сварочный агрегат (САК)',
    'Виброплита/Вибротрамбовка',
    'Ручной виброкаток',
  ],
  'Дорожная техника': [
    'Каток асфальтный',
    'Каток грунтовый',
    'Автогрейдер',
    'Асфальтоукладчик',
    'Дорожная фреза',
  ],
};

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key, required this.user});

  final User user;

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _plateController = TextEditingController();
  final _picker = ImagePicker();
  String? _category;
  String? _equipmentType;
  Uint8List? _photoBytes;
  String? _photoName;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _plateController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1800,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (mounted) {
      setState(() {
        _photoBytes = bytes;
        _photoName = file.name;
        _error = null;
      });
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    if (_photoBytes == null) {
      setState(() => _error = 'Добавьте фотографию спецтехники.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final ref = FirebaseStorage.instance.ref().child(
        'vehicles/${widget.user.uid}.jpg',
      );
      await ref.putData(
        _photoBytes!,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      final photoUrl = await ref.getDownloadURL();
      await FirebaseFirestore.instance
          .collection('drivers')
          .doc(widget.user.uid)
          .set({
            'driverId': widget.user.uid,
            'name': _nameController.text.trim(),
            'phone': widget.user.phoneNumber,
            'equipmentCategory': _category,
            'equipmentType': _equipmentType,
            'vehicleType': _equipmentType,
            'licensePlate': _plateController.text.trim().toUpperCase(),
            'vehiclePhotoUrl': photoUrl,
            'isVerified': false,
            'verificationStatus': 'pending',
            'isOnline': false,
            'createdAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
    } on FirebaseException catch (error) {
      if (mounted) {
        setState(
          () => _error = error.message ?? 'Не удалось сохранить профиль.',
        );
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Не удалось сохранить профиль.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  InputDecoration _decoration(String label, IconData icon) => InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon, color: const Color(0xFFF3C622)),
    filled: true,
    fillColor: const Color(0xFF171914),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0C0A),
      appBar: AppBar(
        title: const Text('Профиль водителя'),
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            children: [
              const Text(
                'Заполните данные для проверки',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Text(
                'После модерации вы получите доступ к заявкам рядом с вами.',
                style: TextStyle(color: Colors.white60, height: 1.4),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: _decoration('Имя', Icons.person_outline),
                validator: (value) => value == null || value.trim().length < 2
                    ? 'Введите имя'
                    : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _plateController,
                textCapitalization: TextCapitalization.characters,
                decoration: _decoration(
                  'Госномер',
                  Icons.directions_car_outlined,
                ),
                validator: (value) => value == null || value.trim().length < 3
                    ? 'Введите госномер'
                    : null,
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: _decoration(
                  'Категория техники',
                  Icons.category_outlined,
                ),
                items: equipmentCatalog.keys
                    .map(
                      (item) =>
                          DropdownMenuItem(value: item, child: Text(item)),
                    )
                    .toList(),
                onChanged: _saving
                    ? null
                    : (value) => setState(() {
                        _category = value;
                        _equipmentType = null;
                      }),
                validator: (value) =>
                    value == null ? 'Выберите категорию' : null,
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _equipmentType,
                decoration: _decoration(
                  'Конкретный тип техники',
                  Icons.construction_outlined,
                ),
                items:
                    (_category == null
                            ? <String>[]
                            : equipmentCatalog[_category]!)
                        .map(
                          (item) =>
                              DropdownMenuItem(value: item, child: Text(item)),
                        )
                        .toList(),
                onChanged: _category == null || _saving
                    ? null
                    : (value) => setState(() => _equipmentType = value),
                validator: (value) =>
                    value == null ? 'Выберите тип техники' : null,
              ),
              const SizedBox(height: 18),
              InkWell(
                onTap: _saving ? null : _pickPhoto,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  height: 190,
                  decoration: BoxDecoration(
                    color: const Color(0xFF171914),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF3B3D34)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _photoBytes == null
                      ? const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.add_a_photo_outlined,
                              color: Color(0xFFF3C622),
                              size: 38,
                            ),
                            SizedBox(height: 10),
                            Text('Добавить фото спецтехники'),
                            SizedBox(height: 4),
                            Text(
                              'Фото нужно для модерации',
                              style: TextStyle(color: Colors.white54),
                            ),
                          ],
                        )
                      : Image.memory(
                          _photoBytes!,
                          fit: BoxFit.cover,
                          width: double.infinity,
                        ),
                ),
              ),
              if (_photoName != null) ...[
                const SizedBox(height: 8),
                Text(
                  _photoName!,
                  style: const TextStyle(color: Colors.white54),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(_error!, style: const TextStyle(color: Color(0xFFFF7D6E))),
              ],
              const SizedBox(height: 22),
              SizedBox(
                height: 56,
                child: FilledButton(
                  onPressed: _saving ? null : _saveProfile,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFF3C622),
                    foregroundColor: const Color(0xFF11120E),
                  ),
                  child: _saving
                      ? const CircularProgressIndicator(
                          color: Color(0xFF11120E),
                        )
                      : const Text(
                          'Отправить на проверку',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
