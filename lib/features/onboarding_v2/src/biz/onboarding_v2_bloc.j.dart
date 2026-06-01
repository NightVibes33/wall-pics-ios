import 'package:Prism/core/error/failure.dart';
import 'package:Prism/core/utils/status.dart';
import 'package:Prism/features/ai_wallpaper/domain/entities/ai_style_preset.dart';
import 'package:Prism/features/category_feed/domain/repositories/category_feed_repository.dart';
import 'package:Prism/features/onboarding_v2/src/data/repo/onboarding_v2_repo.dart';
import 'package:Prism/features/onboarding_v2/src/domain/usecases/complete_onboarding_v2_usecase.dart';
import 'package:Prism/features/onboarding_v2/src/domain/usecases/fetch_starter_pack_usecase.dart';
import 'package:Prism/features/onboarding_v2/src/domain/usecases/follow_starter_pack_usecase.dart';
import 'package:Prism/features/onboarding_v2/src/domain/usecases/save_interests_usecase.dart';
import 'package:Prism/features/onboarding_v2/src/utils/onboarding_v2_config.dart';
import 'package:Prism/features/onboarding_v2/src/views/viewmodels/onboarding_creator_vm.j.dart';
import 'package:Prism/features/onboarding_v2/src/views/viewmodels/onboarding_wallpaper_vm.j.dart';
import 'package:bloc/bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:injectable/injectable.dart';

part 'onboarding_v2_bloc.j.freezed.dart';
part 'onboarding_v2_event.dart';
part 'onboarding_v2_state.dart';

@injectable
class OnboardingV2Bloc extends Bloc<OnboardingV2Event, OnboardingV2State> {
  OnboardingV2Bloc(
    FetchStarterPackUseCase _,
    SaveInterestsUseCase __,
    FollowStarterPackUseCase ___,
    this._completeOnboardingUseCase,
    Object? ____,
    CategoryFeedRepository _____,
    OnboardingV2Repository ______,
  ) : super(OnboardingV2State.initial()) {
    on<_Started>(_onStarted);
    on<_AuthCompleted>(_onAuthCompleted);
    on<_AuthLoadingChanged>(_onAuthLoadingChanged);
    on<_InterestToggled>(_onInterestToggled);
    on<_InterestsConfirmed>(_onInterestsConfirmed);
    on<_CreatorFollowToggled>(_onCreatorFollowToggled);
    on<_StarterPackConfirmed>(_onStarterPackConfirmed);
    on<_FirstWallpaperActionRequested>(_onFirstWallpaperActionRequested);
    on<_FirstWallpaperActionCompleted>(_onFirstWallpaperActionCompleted);
    on<_FirstWallpaperStepContinued>(_onFirstWallpaperStepContinued);
    on<_PaywallResultReceived>(_onPaywallResultReceived);
    on<_StepBack>(_onStepBack);
    on<_AiGenerationRequested>(_onAiGenerationRequested);
    on<_AiGenerationCompleted>(_onAiGenerationCompleted);
    on<_AiGenerationStepContinued>(_onAiGenerationStepContinued);
  }

  final CompleteOnboardingV2UseCase _completeOnboardingUseCase;

  Future<void> _onStarted(_Started event, Emitter<OnboardingV2State> emit) async {
    emit(state.copyWith(loadStatus: LoadStatus.success, failure: null, navRequest: null));
  }

  Future<void> _onAuthCompleted(_AuthCompleted event, Emitter<OnboardingV2State> emit) async {
    emit(state.copyWith(isAuthLoading: false, navRequest: null));
    await _finishOnboarding(emit, didPurchase: false);
  }

  void _onAuthLoadingChanged(_AuthLoadingChanged event, Emitter<OnboardingV2State> emit) {
    emit(state.copyWith(isAuthLoading: event.isLoading, navRequest: null));
  }

  void _onInterestToggled(_InterestToggled event, Emitter<OnboardingV2State> emit) {
    final current = state.interestsData.selected;
    final updated = current.contains(event.categoryName)
        ? current.where((c) => c != event.categoryName).toList()
        : [...current, event.categoryName];
    emit(state.copyWith(interestsData: state.interestsData.copyWith(selected: updated), navRequest: null));
  }

  Future<void> _onInterestsConfirmed(_InterestsConfirmed event, Emitter<OnboardingV2State> emit) async {
    await _finishOnboarding(emit, didPurchase: false);
  }

  void _onCreatorFollowToggled(_CreatorFollowToggled event, Emitter<OnboardingV2State> emit) {
    final current = state.starterPackData.selectedEmails;
    final updated = current.contains(event.creatorEmail)
        ? current.where((e) => e != event.creatorEmail).toList()
        : [...current, event.creatorEmail];

    final updatedCreators = state.starterPackData.creators
        .map((c) => c.copyWith(isSelected: updated.contains(c.email)))
        .toList();

    emit(
      state.copyWith(
        navRequest: null,
        starterPackData: state.starterPackData.copyWith(selectedEmails: updated, creators: updatedCreators),
      ),
    );
  }

  Future<void> _onStarterPackConfirmed(_StarterPackConfirmed event, Emitter<OnboardingV2State> emit) async {
    await _finishOnboarding(emit, didPurchase: false);
  }

  Future<void> _onFirstWallpaperActionRequested(
    _FirstWallpaperActionRequested event,
    Emitter<OnboardingV2State> emit,
  ) async {
    await _finishOnboarding(emit, didPurchase: false);
  }

  void _onFirstWallpaperActionCompleted(_FirstWallpaperActionCompleted event, Emitter<OnboardingV2State> emit) {
    emit(
      state.copyWith(
        wallpaperData: state.wallpaperData.copyWith(
          status: event.success ? FirstWallpaperStatus.success : FirstWallpaperStatus.failure,
          elapsedMs: event.elapsedMs,
        ),
      ),
    );
  }

  Future<void> _onFirstWallpaperStepContinued(
    _FirstWallpaperStepContinued event,
    Emitter<OnboardingV2State> emit,
  ) async {
    await _finishOnboarding(emit, didPurchase: false);
  }

  Future<void> _onPaywallResultReceived(_PaywallResultReceived event, Emitter<OnboardingV2State> emit) async {
    await _finishOnboarding(emit, didPurchase: event.didPurchase);
  }

  Future<void> _finishOnboarding(Emitter<OnboardingV2State> emit, {required bool didPurchase}) async {
    emit(state.copyWith(actionStatus: ActionStatus.inProgress, failure: null, navRequest: null));
    final result = await _completeOnboardingUseCase(
      CompleteOnboardingParams(didPurchase: didPurchase, totalElapsedMs: 0),
    );
    result.fold(
      onSuccess: (_) => emit(
        state.copyWith(actionStatus: ActionStatus.success, navRequest: OnboardingV2NavRequest.completeOnboarding),
      ),
      onFailure: (failure) => emit(state.copyWith(actionStatus: ActionStatus.failure, failure: failure)),
    );
  }

  void _onStepBack(_StepBack event, Emitter<OnboardingV2State> emit) {
    // auth is terminal — no backward navigation
    if (state.step == OnboardingV2Step.auth) return;

    final OnboardingV2Step? prevStep = switch (state.step) {
      OnboardingV2Step.interests => OnboardingV2Step.auth,
      OnboardingV2Step.starterPack => state.skipInterests ? OnboardingV2Step.auth : OnboardingV2Step.interests,
      OnboardingV2Step.aiGenerate => state.skipInterests ? OnboardingV2Step.auth : OnboardingV2Step.interests,
      OnboardingV2Step.firstWallpaper => OnboardingV2Step.aiGenerate,
      OnboardingV2Step.auth => null,
    };

    if (prevStep != null) {
      emit(state.copyWith(step: prevStep, navRequest: null));
    }
  }

  // AI generation is intentionally disabled in onboarding. Login completion now finishes onboarding.
  Future<void> _onAiGenerationRequested(_AiGenerationRequested event, Emitter<OnboardingV2State> emit) async {
    await _finishOnboarding(emit, didPurchase: false);
  }

  void _onAiGenerationCompleted(_AiGenerationCompleted event, Emitter<OnboardingV2State> emit) {
    emit(state.copyWith(aiData: state.aiData.copyWith(status: AiGenerateStatus.failure)));
  }

  Future<void> _onAiGenerationStepContinued(_AiGenerationStepContinued event, Emitter<OnboardingV2State> emit) async {
    await _finishOnboarding(emit, didPurchase: false);
  }

}
