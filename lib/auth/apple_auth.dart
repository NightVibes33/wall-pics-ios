import 'package:Prism/analytics/analytics_service.dart';
import 'package:Prism/core/analytics/events/events.dart';
import 'package:Prism/logger/logger.dart';

class AppleAuth {
  static const String signInCancelledResult = 'signInWithApple canceled';

  Future<String> signInWithApple() async {
    await analytics.track(
      const AuthLoginResultEvent(
        method: AuthMethodValue.apple,
        result: EventResultValue.cancelled,
        reason: AnalyticsReasonValue.unknown,
        sourceContext: 'apple_auth_removed',
      ),
    );
    logger.w('Apple sign-in is disabled in this backend-free build.', tag: 'AppleAuth');
    return signInCancelledResult;
  }
}
