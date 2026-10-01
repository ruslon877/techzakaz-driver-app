import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import 'screens/login_screen.dart';
import 'screens/radar_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  final _firebaseAuth = FirebaseAuth.instance;
  final _localAuth = LocalAuthentication();

  StreamSubscription<User?>? _authSubscription;
  User? _user;
  bool _isBiometricUnlocked = false;
  bool _isAuthenticating = false;
  String? _biometricError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authSubscription = _firebaseAuth.authStateChanges().listen(_handleUserChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _user != null && !_isAuthenticating) {
      _isBiometricUnlocked = false;
      _biometricError = null;
      _authenticateBiometrically();
    }
  }

  void _handleUserChanged(User? user) {
    if (!mounted) return;
    setState(() {
      _user = user;
      _isBiometricUnlocked = user == null;
      _biometricError = null;
    });
    if (user != null) _authenticateBiometrically();
  }

  Future<void> _authenticateBiometrically() async {
    final user = _user;
    if (user == null || _isAuthenticating || _isBiometricUnlocked) return;

    _isAuthenticating = true;
    if (mounted) setState(() {});

    try {
      final canCheckBiometrics = await _localAuth.canCheckBiometrics;
      final enrolledBiometrics = canCheckBiometrics ? await _localAuth.getAvailableBiometrics() : <BiometricType>[];

      // No scanner or no enrolled fingerprint/Face ID: Firebase session is enough.
      if (!canCheckBiometrics || enrolledBiometrics.isEmpty) {
        _unlock();
        return;
      }

      final didAuthenticate = await _localAuth.authenticate(
        localizedReason: 'Подтвердите личность, чтобы открыть радар заявок',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );

      if (didAuthenticate) {
        _unlock();
      } else {
        _keepLocked('Биометрия не подтверждена. Повторите сканирование, чтобы открыть радар.');
      }
    } on LocalAuthException catch (error) {
      switch (error.code) {
        case LocalAuthExceptionCode.noBiometricHardware:
        case LocalAuthExceptionCode.noBiometricsEnrolled:
        case LocalAuthExceptionCode.noCredentialsSet:
          _unlock();
        default:
          _keepLocked('Не удалось подтвердить личность. Попробуйте ещё раз.');
      }
    } catch (_) {
      _keepLocked('Биометрическая проверка временно недоступна.');
    } finally {
      _isAuthenticating = false;
      if (mounted) setState(() {});
    }
  }

  void _unlock() {
    if (!mounted) return;
    setState(() {
      _isBiometricUnlocked = true;
      _biometricError = null;
    });
  }

  void _keepLocked(String message) {
    if (!mounted) return;
    setState(() {
      _isBiometricUnlocked = false;
      _biometricError = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_user == null) return const LoginScreen();
    if (!_isBiometricUnlocked) return _BiometricLockScreen(error: _biometricError, isLoading: _isAuthenticating, onRetry: _authenticateBiometrically, onSignOut: _firebaseAuth.signOut);
    return const RadarScreen();
  }
}

class _BiometricLockScreen extends StatelessWidget {
  const _BiometricLockScreen({required this.error, required this.isLoading, required this.onRetry, required this.onSignOut});

  final String? error;
  final bool isLoading;
  final VoidCallback onRetry;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0C0A),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(color: const Color(0xFFF3C622), borderRadius: BorderRadius.circular(28)),
                  child: const Icon(Icons.fingerprint, color: Color(0xFF11120E), size: 52),
                ),
                const SizedBox(height: 28),
                const Text('Подтвердите вход', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                Text(error ?? 'Используйте отпечаток пальца или Face ID, чтобы открыть радар.', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60, height: 1.4)),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton.icon(
                    onPressed: isLoading ? null : onRetry,
                    icon: isLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF11120E))) : const Icon(Icons.fingerprint),
                    label: Text(isLoading ? 'Проверяем…' : 'Разблокировать'),
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFFF3C622), foregroundColor: const Color(0xFF11120E)),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(onPressed: onSignOut, child: const Text('Выйти из аккаунта')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
