import 'package:Prism/logger/logger.dart';

final RegExp _invalidTopicCharacters = RegExp(r'[^A-Za-z0-9\-_.~%]');

String? followersTopicFromEmail(String email) {
  final String localPart = email.trim().split('@').first.trim();
  if (localPart.isEmpty) {
    return null;
  }
  final String sanitizedLocalPart = localPart.replaceAll(_invalidTopicCharacters, '');
  if (sanitizedLocalPart.isEmpty) {
    return null;
  }
  return sanitizedLocalPart;
}

Future<bool> subscribeToTopicSafely(String topic, {required String sourceTag}) async {
  final String normalizedTopic = topic.trim();
  if (normalizedTopic.isEmpty) {
    return false;
  }
  logger.d(
    'Push topic subscriptions are disabled in this build.',
    tag: 'Push',
    fields: <String, Object?>{'topic': normalizedTopic, 'sourceTag': sourceTag},
  );
  return false;
}

Future<void> unsubscribeFromTopicSafely(String topic, {required String sourceTag}) async {
  final String normalizedTopic = topic.trim();
  if (normalizedTopic.isEmpty) {
    return;
  }
  logger.d(
    'Push topic unsubscriptions are disabled in this build.',
    tag: 'Push',
    fields: <String, Object?>{'topic': normalizedTopic, 'sourceTag': sourceTag},
  );
}
