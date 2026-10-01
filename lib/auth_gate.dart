import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'screens/login_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFF0B0C0A),
            body: Center(child: CircularProgressIndicator(color: Color(0xFFF3C622))),
          );
        }

        if (snapshot.data == null) return const LoginScreen();

        return const Scaffold(
          backgroundColor: Color(0xFF0B0C0A),
          body: Center(
            child: Text('Радар заявок', style: TextStyle(color: Colors.white, fontSize: 22)),
          ),
        );
      },
    );
  }
}
