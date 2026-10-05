import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'screens/login_screen.dart';
import 'screens/pending_verification_screen.dart';
import 'screens/profile_setup_screen.dart';
import 'screens/radar_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _AuthLoadingScreen();
        }

        final user = snapshot.data;
        if (user == null) return const LoginScreen();

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('drivers')
              .doc(user.uid)
              .snapshots(),
          builder: (context, profileSnapshot) {
            if (profileSnapshot.connectionState == ConnectionState.waiting) {
              return const _AuthLoadingScreen();
            }
            if (profileSnapshot.hasError) {
              return _ProfileLoadError(error: profileSnapshot.error);
            }

            final profile = profileSnapshot.data;
            if (profile == null || !profile.exists) {
              return ProfileSetupScreen(user: user);
            }
            final profileData = profile.data();
            final verificationStatus =
                profileData?['verificationStatus']?.toString().toLowerCase();
            return verificationStatus == 'approved'
                ? const RadarScreen()
                : PendingVerificationScreen(profile: profileData);
          },
        );
      },
    );
  }
}

class _AuthLoadingScreen extends StatelessWidget {
  const _AuthLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF0B0C0A),
      body: Center(child: CircularProgressIndicator(color: Color(0xFFF3C622))),
    );
  }
}

class _ProfileLoadError extends StatelessWidget {
  const _ProfileLoadError({this.error});

  final Object? error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0C0A),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Не удалось загрузить профиль. Проверьте интернет и попробуйте снова.\n\n$error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        ),
      ),
    );
  }
}
