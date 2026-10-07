import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../config/service_cities.dart';

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
  String _cityId = 'almaty';
  Uint8List? _photoBytes;
  String? _photoName;
  String? _existingPhotoUrl;
  String? _error;
  bool _saving = false;
  bool _acceptedRules = false;

  bool get _isEditing => widget.profile != null;

  @override
  void initState() {
    super.initState();
    final profile = widget.profile;
    _nameController.text = profile?['name']?.toString() ?? '';
    _plateController.text = profile?['licensePlate']?.toString() ?? '';
    _category = profile?['equipmentCategory']?.toString();
    _equipmentType = profile?['equipmentType']?.toString();
    final savedCityId = profile?['cityId']?.toString();
    if (savedCityId != null && serviceCitiesById.containsKey(savedCityId)) {
      _cityId = savedCityId;
    }
    _existingPhotoUrl = profile?['vehiclePhotoUrl']?.toString();
    if (_category == null || !equipmentCatalog.containsKey(_category)) {
      final type = _equipmentType;
      String? matchingCategory;
      if (type != null) {
        for (final entry in equipmentCatalog.entries) {
          if (entry.value.contains(type)) {
            matchingCategory = entry.key;
            break;
          }
        }
      }
      _category = matchingCategory;
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

  String _normalizePlate(String value) =>
      value.replaceAll(RegExp(r'\s+'), '').toUpperCase();

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_acceptedRules) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Согласитесь с Правилами сервиса, чтобы продолжить.')),
      );
      return;
    }
    if (_photoBytes == null && (_existingPhotoUrl == null || _existingPhotoUrl!.isEmpty)) {
      setState(() => _error = 'Добавьте фотографию спецтехники.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final normalizedPlate = _normalizePlate(_plateController.text);
      final availability = await FirebaseFunctions.instance
          .httpsCallable('checkLicensePlateAvailability')
          .call({'licensePlate': normalizedPlate});
      if (availability.data is Map && availability.data['available'] != true) {
        throw StateError('Техника с таким госномером уже зарегистрирована в системе');
      }
      final firestore = FirebaseFirestore.instance;
      final plateRef = firestore.collection('plateRegistry').doc(normalizedPlate);
      final oldPlate = _normalizePlate(widget.profile?['licensePlate']?.toString() ?? '');
      final oldPlateRef = oldPlate.isEmpty || oldPlate == normalizedPlate
          ? null
          : firestore.collection('plateRegistry').doc(oldPlate);
      await firestore.runTransaction((transaction) async {
        final plateSnapshot = await transaction.get(plateRef);
        final oldPlateSnapshot = oldPlateRef == null
            ? null
            : await transaction.get(oldPlateRef);
        final reservedBy = plateSnapshot.data()?['driverId']?.toString();
        if (reservedBy != null && reservedBy != widget.user.uid) {
          throw StateError('Техника с таким госномером уже зарегистрирована в системе');
        }
        transaction.set(plateRef, {
          'driverId': widget.user.uid,
          'licensePlate': normalizedPlate,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        if (oldPlateRef != null && oldPlateSnapshot?.data()?['driverId'] == widget.user.uid) {
          transaction.delete(oldPlateRef);
        }
      });
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
        'cityId': _cityId,
        'cityName': serviceCityById(_cityId).name,
        'licensePlate': normalizedPlate,
        'licensePlateNormalized': normalizedPlate,
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
    } on StateError catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error.message;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message ?? 'Госномер уже зарегистрирован')),
        );
      }
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

  void _showServiceRules() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF171914),
        title: const Text('Правила сервиса ТехЗаказ'),
        content: const SingleChildScrollView(
          child: Text(
            '1. Указывайте достоверные данные о себе и технике.\n\n'
            '2. Принимайте только те заказы, которые можете выполнить.\n\n'
            '3. Не передавайте клиентские контакты третьим лицам.\n\n'
            '4. За нарушения доступ к заказам может быть ограничен.\n\n'
            '5. В спорных ситуациях обратитесь в службу поддержки.',
            style: TextStyle(color: Colors.white70, height: 1.5),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Понятно'),
          ),
        ],
      ),
    );
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
              Text(
                _isEditing ? 'Исправьте данные профиля' : 'Заполните данные для проверки',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
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
                initialValue: _cityId,
                decoration: _decoration(
                  'Город работы',
                  Icons.location_city_outlined,
                ).copyWith(
                  helperText: 'Сейчас доступен только Алматы. Новые города появятся позже.',
                  helperStyle: const TextStyle(color: Colors.white54),
                ),
                items: serviceCities
                    .map(
                      (city) => DropdownMenuItem(
                        value: city.id,
                        child: Text(city.name),
                      ),
                    )
                    .toList(),
                onChanged: _saving
                    ? null
                    : (value) {
                        if (value != null) setState(() => _cityId = value);
                      },
                validator: (value) => value == null ? 'Выберите город' : null,
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
              Container(
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3C622).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFFF3C622).withValues(alpha: 0.25),
                  ),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded, color: Color(0xFFF3C622), size: 22),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'На фото должен чётко читаться госномер. Фотографируйте технику при хорошем освещении.',
                        style: TextStyle(color: Colors.white70, height: 1.35),
                      ),
                    ),
                  ],
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
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Checkbox(
                    value: _acceptedRules,
                    activeColor: const Color(0xFFF3C622),
                    checkColor: const Color(0xFF11120E),
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _acceptedRules = value ?? false),
                  ),
                  Expanded(
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text('Я согласен с '),
                        TextButton(
                          onPressed: _showServiceRules,
                          child: const Text('Правила сервиса'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              SizedBox(
                height: 56,
                child: FilledButton(
                  onPressed: _saving || !_acceptedRules ? null : _saveProfile,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFF3C622),
                    foregroundColor: const Color(0xFF11120E),
                  ),
                  child: _saving
                      ? const CircularProgressIndicator(
                          color: Color(0xFF11120E),
                        )
                      : Text(
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
