
/// Payload shape for `wall_of_the_day/current` — pointer only; UI loads `walls/{wallDocumentId}`.
class WallOfTheDayRemoteStorePointer {
  const WallOfTheDayRemoteStorePointer({required this.wallDocumentId, required this.featuredAt});

  factory WallOfTheDayRemoteStorePointer.fromMap(Map<String, dynamic> data) {
    final String wallId = data['wallId']?.toString() ?? '';
    final Object? rawDate = data['date'];
    final DateTime featuredAt;
    if (rawDate is DateTime) {
      featuredAt = rawDate;
    } else {
      featuredAt = DateTime.tryParse(rawDate?.toString() ?? '') ?? DateTime.now();
    }
    return WallOfTheDayRemoteStorePointer(wallDocumentId: wallId, featuredAt: featuredAt);
  }

  final String wallDocumentId;
  final DateTime featuredAt;
}
