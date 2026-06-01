import 'package:flutter/widgets.dart';

class NotificationPermissionPromptService {
  NotificationPermissionPromptService._();

  static final NotificationPermissionPromptService instance = NotificationPermissionPromptService._();

  Future<void> maybePromptAfterValueAction(BuildContext context, {required String sourceTag}) async {}
}
