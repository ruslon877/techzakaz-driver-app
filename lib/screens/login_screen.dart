import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final _auth = FirebaseAuth.instance;

  String? _verificationId;
  String? _errorMessage;
  bool _isLoading = false;
  bool _codeSent = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  String _normalizePhone(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('8')) return '+7${digits.substring(1)}';
    if (digits.startsWith('7')) return '+$digits';
    return '+7$digits';
  }

  Future<void> _sendCode() async {
    final phone = _normalizePhone(_phoneController.text);
    if (phone.length < 12) {
      setState(() => _errorMessage = 'Введите полный номер телефона.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    await _auth.verifyPhoneNumber(
      phoneNumber: phone,
      verificationCompleted: (credential) async {
        await _auth.signInWithCredential(credential);
      },
      verificationFailed: (error) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _errorMessage = _friendlyAuthError(error);
        });
      },
      codeSent: (verificationId, _) {
        if (!mounted) return;
        setState(() {
          _verificationId = verificationId;
          _codeSent = true;
          _isLoading = false;
          _errorMessage = null;
        });
      },
      codeAutoRetrievalTimeout: (verificationId) {
        _verificationId = verificationId;
      },
    );
  }

  Future<void> _confirmCode() async {
    final verificationId = _verificationId;
    final code = _codeController.text.trim();
    if (verificationId == null || code.length < 6) {
      setState(() => _errorMessage = 'Введите 6-значный код из SMS.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: code,
      );
      await _auth.signInWithCredential(credential);
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = _friendlyAuthError(error);
      });
    }
  }

  String _friendlyAuthError(FirebaseAuthException error) {
    switch (error.code) {
      case 'invalid-phone-number':
        return 'Проверьте формат номера телефона.';
      case 'too-many-requests':
        return 'Слишком много попыток. Попробуйте позже.';
      case 'invalid-verification-code':
        return 'Неверный код подтверждения.';
      case 'quota-exceeded':
        return 'Лимит SMS исчерпан. Используйте тестовый номер Firebase.';
      default:
        return error.message ?? 'Не удалось выполнить вход. Попробуйте ещё раз.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF0B0C0A),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3C622),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: const Icon(Icons.construction, color: Color(0xFF11120E), size: 28),
                  ),
                  const SizedBox(height: 28),
                  Text('ТехЗаказ', style: theme.textTheme.headlineMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text('Кабинет водителя спецтехники', style: theme.textTheme.bodyLarge?.copyWith(color: Colors.white60)),
                  const SizedBox(height: 44),
                  Text(_codeSent ? 'Введите код из SMS' : 'Вход по номеру телефона', style: theme.textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text(_codeSent ? 'Мы отправили 6-значный код на ваш номер.' : 'Номер нужен для доступа к активным заявкам.', style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white54)),
                  const SizedBox(height: 24),
                  if (!_codeSent)
                    TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      style: const TextStyle(color: Colors.white),
                      decoration: _inputDecoration('Номер телефона', Icons.phone_outlined),
                    )
                  else
                    TextField(
                      controller: _codeController,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      autofocus: true,
                      style: const TextStyle(color: Colors.white, letterSpacing: 8, fontSize: 20),
                      decoration: _inputDecoration('Код подтверждения', Icons.lock_outline).copyWith(counterText: ''),
                    ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(_errorMessage!, style: const TextStyle(color: Color(0xFFFF7D6E))),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: FilledButton(
                      onPressed: _isLoading ? null : (_codeSent ? _confirmCode : _sendCode),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFF3C622),
                        foregroundColor: const Color(0xFF11120E),
                        disabledBackgroundColor: const Color(0xFF665713),
                      ),
                      child: _isLoading
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF11120E)))
                          : Text(_codeSent ? 'Войти' : 'Получить код', style: const TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ),
                  if (_codeSent) ...[
                    const SizedBox(height: 12),
                    Center(
                      child: TextButton(
                        onPressed: _isLoading ? null : () => setState(() {
                          _codeSent = false;
                          _verificationId = null;
                          _codeController.clear();
                          _errorMessage = null;
                        }),
                        child: const Text('Изменить номер'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 34),
                  Text('Для разработки можно использовать тестовые номера, добавленные в Firebase Console → Authentication → Sign-in method → Phone.', style: theme.textTheme.bodySmall?.copyWith(color: Colors.white38, height: 1.4)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white54),
      prefixIcon: Icon(icon, color: const Color(0xFFF3C622)),
      filled: true,
      fillColor: const Color(0xFF171914),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF3B3D34))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFF3C622), width: 2)),
    );
  }
}
