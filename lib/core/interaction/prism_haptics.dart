import 'package:flutter/services.dart';

enum PrismHapticStyle { none, selection, light, medium, heavy }

class PrismHaptics {
  const PrismHaptics._();

  static void impact(PrismHapticStyle style) {
    switch (style) {
      case PrismHapticStyle.none:
        return;
      case PrismHapticStyle.selection:
        selection();
        return;
      case PrismHapticStyle.light:
        lightImpact();
        return;
      case PrismHapticStyle.medium:
        mediumImpact();
        return;
      case PrismHapticStyle.heavy:
        heavyImpact();
        return;
    }
  }

  static void selection() {
    HapticFeedback.selectionClick();
  }

  static void lightImpact() {
    HapticFeedback.lightImpact();
  }

  static void mediumImpact() {
    HapticFeedback.mediumImpact();
  }

  static void heavyImpact() {
    HapticFeedback.heavyImpact();
  }

  static void success() {
    HapticFeedback.lightImpact();
  }

  static void warning() {
    HapticFeedback.mediumImpact();
  }

  static void failure() {
    HapticFeedback.heavyImpact();
  }
}
