import 'package:Prism/core/interaction/prism_motion.dart';
import 'package:flutter/material.dart';

class PrismTapScale extends StatefulWidget {
  const PrismTapScale({
    required this.child,
    this.enabled = true,
    this.pressedScale = 0.96,
    this.transformOrigin = Alignment.center,
    super.key,
  });

  final Widget child;
  final bool enabled;
  final double pressedScale;
  final Alignment transformOrigin;

  @override
  State<PrismTapScale> createState() => _PrismTapScaleState();
}

class _PrismTapScaleState extends State<PrismTapScale> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: PrismMotion.press,
      reverseDuration: PrismMotion.pressRelease,
    );
    _scale = Tween<double>(
      begin: 1,
      end: widget.pressedScale,
    ).animate(CurvedAnimation(parent: _controller, curve: PrismMotion.emphasized, reverseCurve: PrismMotion.emphasized));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _setPressed(bool pressed) {
    if (!mounted || !widget.enabled || MediaQuery.disableAnimationsOf(context)) {
      return;
    }
    if (pressed) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: AnimatedBuilder(
        animation: _scale,
        builder: (context, child) {
          final scale = reduceMotion ? 1.0 : _scale.value;
          return Transform.scale(
            scale: scale,
            alignment: widget.transformOrigin,
            filterQuality: FilterQuality.low,
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}
