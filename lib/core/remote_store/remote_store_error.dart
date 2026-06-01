class RemoteStoreError implements Exception {
  RemoteStoreError({required this.message, this.code, this.original});

  final String message;
  final String? code;
  final Object? original;

  @override
  String toString() => 'RemoteStoreError(code: $code, message: $message)';
}

RemoteStoreError mapRemoteStoreError(Object error) {
  if (error is RemoteStoreError) {
    return error;
  }
  return RemoteStoreError(message: error.toString(), original: error);
}
