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
  const ProfileSetupScreen({super.key, required this.user, this.profile});

  final User user;
  final Map<String, dynamic>? profile;

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
  String? _existingPhotoUrl;
  String? _error;
  bool _saving = false;

  bool get _isEditing => widget.profile != null;

  @override
  void initState() {
    super.initState();
    final profile = widget.profile;
    _nameController.text = profile?['name']?.toString() ?? '';
    _plateController.text = profile?['licensePlate']?.toString() ?? '';
    _category = profile?['equipmentCategory']?.toString();
    _equipmentType = profile?['equipmentType']?.toString();
    _existingPhotoUrl = profile?['vehiclePhotoUrl']?.toString();
    if (_category == null || !equipmentCatalog.containsKey(_category)) {
      final type = _equipmentType;
      final matchingCategory = type == null
          ? null
          : equipmentCatalog.entries
              .where((entry) => entry.value.contains(type))
              .map((entry) => entry.key)
              .firstWhere((value) => true, orElse: () => '');
      _category = matchingCategory == null || matchingCategory.isEmpty
          ? null
          : matchingCategory;
    }
  }

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
    if (_photoBytes == null && (_existingPhotoUrl == null || _existingPhotoUrl!.isEmpty)) {
      setState(() => _error = 'Добавьте фотографию спецтехники.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      var photoUrl = _existingPhotoUrl;
      if (_photoBytes != null) {
        final ref = FirebaseStorage.instance.ref().child(
          'vehicles/${widget.user.uid}.jpg',
        );
        await ref.putData(
          _photoBytes!,
          SettableMetadata(contentType: 'image/jpeg'),
        );
        photoUrl = await ref.getDownloadURL();
      }
      final profileData = <String, dynamic>{
        'driverId': widget.user.uid,
        'name': _nameController.text.trim(),
        'phone': widget.user.phoneNumber,
        'equipmentCategory': _category,
        'equipmentType': _equipmentType,
        'vehicleType': _equipmentType,
        'licensePlate': _plateController.text.trim().toUpperCase(),
        'vehiclePhotoUrl': photoUrl,
        'verificationStatus': 'pending',
        'isOnline': false,
      };
      if (!_isEditing) {
        profileData.addAll({
          'freeOrdersLeft': 20,
          'subscriptionEndsAt': null,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      await FirebaseFirestore.instance
          .collection('drivers')
          .doc(widget.user.uid)
          .set(profileData, SetOptions(merge: true));
      if (_isEditing && mounted) Navigator.of(context).pop();
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
                _isEditing ? 'Исправьте данные профиля' : 'Заполните данные для проверки',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Text(
                _isEditing
                    ? 'Обновите данные и повторно отправьте анкету на модерацию.'
                    : 'После модерации вы получите доступ к заявкам рядом с вами.',
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
                  child: _photoBytes != null
                      ? Image.memory(
                          _photoBytes!,
                          fit: BoxFit.cover,
                          width: double.infinity,
                        )
                      : (_existingPhotoUrl != null && _existingPhotoUrl!.isNotEmpty)
                          ? Image.network(
                              _existingPhotoUrl!,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.broken_image_outlined,
                                color: Color(0xFFF3C622),
                                size: 38,
                              ),
                            )
                          : const Column(
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
                          _isEditing ? 'Повторно отправить на проверку' : 'Отправить на проверку',
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
