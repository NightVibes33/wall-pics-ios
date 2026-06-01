part of 'review_batch_bloc.dart';

enum ReviewBatchStatus { initial, loading, loaded, batchComplete, error }

class ReviewBatchState {
  final ReviewBatchStatus status;
  final List<RemoteStoreDocument> walls;
  final List<RemoteStoreDocument> skippedStack;
  final List<UndoableAction> undoStack;
  final int currentIndex;
  final int totalPending;
  final String? errorMessage;

  const ReviewBatchState({
    this.status = ReviewBatchStatus.initial,
    this.walls = const [],
    this.skippedStack = const [],
    this.undoStack = const [],
    this.currentIndex = 0,
    this.totalPending = 0,
    this.errorMessage,
  });

  bool get canUndo => undoStack.isNotEmpty;
  bool get hasMoreWalls => currentIndex < walls.length;
  int get remainingInBatch => walls.length - currentIndex;
  RemoteStoreDocument? get currentWall => hasMoreWalls ? walls[currentIndex] : null;

  ReviewBatchState copyWith({
    ReviewBatchStatus? status,
    List<RemoteStoreDocument>? walls,
    List<RemoteStoreDocument>? skippedStack,
    List<UndoableAction>? undoStack,
    int? currentIndex,
    int? totalPending,
    String? errorMessage,
  }) {
    return ReviewBatchState(
      status: status ?? this.status,
      walls: walls ?? this.walls,
      skippedStack: skippedStack ?? this.skippedStack,
      undoStack: undoStack ?? this.undoStack,
      currentIndex: currentIndex ?? this.currentIndex,
      totalPending: totalPending ?? this.totalPending,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReviewBatchState &&
          runtimeType == other.runtimeType &&
          status == other.status &&
          currentIndex == other.currentIndex &&
          totalPending == other.totalPending;

  @override
  int get hashCode => status.hashCode ^ currentIndex.hashCode ^ totalPending.hashCode;
}
