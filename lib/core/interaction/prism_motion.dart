import 'package:flutter/animation.dart';

class PrismMotion {
  const PrismMotion._();

  static const Duration instant = Duration(milliseconds: 0);
  static const Duration press = Duration(milliseconds: 110);
  static const Duration pressRelease = Duration(milliseconds: 90);
  static const Duration quick = Duration(milliseconds: 160);
  static const Duration standard = Duration(milliseconds: 220);

  static const Curve emphasized = Curves.easeOutCubic;
  static const Curve settle = Curves.easeOutQuart;
}
