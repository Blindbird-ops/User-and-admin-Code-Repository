// register_screen.dart
import 'package:flutter/material.dart';
import 'multi_step_registration_form.dart'; // Import the new multi-step form

class RegisterScreen extends StatelessWidget {
  const RegisterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: MultiStepRegistrationForm(), // Use the new multi-step form here
    );
  }
}