import 'package:flutter/material.dart';

// false = Black Buttons
// true  = White Buttons
final ValueNotifier<bool> useWhiteButtons = ValueNotifier(false);

void setWindowTheme({required bool whiteButtons}) {
  // 🛑 FIX: Schedule the update to happen AFTER the build phase.
  // This prevents the "setState() called during build" error.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (useWhiteButtons.value != whiteButtons) {
      useWhiteButtons.value = whiteButtons;
    }
  });
}