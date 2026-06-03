import 'dart:async';

import 'package:Prism/auth/apple_auth.dart';
import 'package:Prism/auth/google_auth.dart';

final GoogleAuth globalGoogleAuth = GoogleAuth();
final AppleAuth globalAppleAuth = AppleAuth();

final Completer<void> authBootstrapCompleter = Completer<void>();
bool authBootstrapCompleted = false;

void completeAuthBootstrap() {
  if (authBootstrapCompleted) {
    return;
  }
  authBootstrapCompleted = true;
  if (!authBootstrapCompleter.isCompleted) {
    authBootstrapCompleter.complete();
  }
}

Future<void> waitForAuthBootstrap({Duration timeout = const Duration(milliseconds: 900)}) async {
  if (authBootstrapCompleted) {
    return;
  }
  try {
    await authBootstrapCompleter.future.timeout(timeout);
  } catch (_) {
    // Keep startup moving if auth reconciliation stalls.
  }
}
