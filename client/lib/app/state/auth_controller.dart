import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/user_model.dart';
import '../../services/auth_service.dart';

enum AuthStage { signedOut, twoFactorRequired, signedIn }

class AuthState {
  const AuthState({
    required this.stage,
    this.user,
    this.pendingUser,
    this.pendingUserId,
    this.pendingTwoFactorToken,
    this.isLoading = false,
    this.error,
  });

  final AuthStage stage;
  final User? user;
  final User? pendingUser;
  final String? pendingUserId;
  final String? pendingTwoFactorToken;
  final bool isLoading;
  final String? error;

  bool get isAuthenticated => stage == AuthStage.signedIn && user != null;

  AuthState copyWith({
    AuthStage? stage,
    User? user,
    User? pendingUser,
    String? pendingUserId,
    String? pendingTwoFactorToken,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return AuthState(
      stage: stage ?? this.stage,
      user: user ?? this.user,
      pendingUser: pendingUser ?? this.pendingUser,
      pendingUserId: pendingUserId ?? this.pendingUserId,
      pendingTwoFactorToken:
          pendingTwoFactorToken ?? this.pendingTwoFactorToken,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }

  static const signedOut = AuthState(
    stage: AuthStage.signedOut,
    isLoading: false,
  );
}

class AuthController extends StateNotifier<AuthState> {
  AuthController(this._authService)
    : super(const AuthState(stage: AuthStage.signedOut, isLoading: true)) {
    _bootstrap();
  }

  final AuthService _authService;

  Future<void> _bootstrap() async {
    final result = await _authService.restoreSession();
    if (result.success && result.user != null) {
      state = AuthState(
        stage: AuthStage.signedIn,
        user: result.user,
        isLoading: false,
      );
      return;
    }
    state = AuthState.signedOut.copyWith(isLoading: false);
  }

  Future<void> login(String userId, String password) async {
    state = state.copyWith(isLoading: true, clearError: true);
    final result = await _authService.login(userId.trim(), password);
    if (!result.success) {
      state = AuthState.signedOut.copyWith(
        isLoading: false,
        error: result.message,
      );
      return;
    }

    if (result.requiresTwoFactor) {
      state = AuthState(
        stage: AuthStage.twoFactorRequired,
        pendingTwoFactorToken: result.tempToken,
        isLoading: false,
      );
      return;
    }

    if (result.user == null) {
      state = AuthState.signedOut.copyWith(
        isLoading: false,
        error: 'Login failed. Please try again.',
      );
      return;
    }

    state = AuthState(
      stage: AuthStage.signedIn,
      user: result.user,
      isLoading: false,
    );
  }

  Future<void> register({
    required String username,
    required String fullName,
    required String email,
    required String password,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);
    final result = await _authService.register(
      username: username,
      fullName: fullName,
      email: email,
      password: password,
    );

    if (!result.success) {
      state = state.copyWith(isLoading: false, error: result.message);
      return;
    }

    if (result.user != null) {
      state = AuthState(
        stage: AuthStage.signedIn,
        user: result.user,
        isLoading: false,
      );
      return;
    }

    state = AuthState(
      stage: AuthStage.twoFactorRequired,
      pendingUserId: result.pendingUserId,
      isLoading: false,
      error: null,
    );
  }

  Future<void> verifyTwoFactorCode(String code) async {
    state = state.copyWith(isLoading: true, clearError: true);

    if (state.pendingTwoFactorToken != null &&
        state.pendingTwoFactorToken!.isNotEmpty) {
      final result = await _authService.completeTwoFactor(
        tempToken: state.pendingTwoFactorToken!,
        code: code.trim(),
      );
      if (!result.success || result.user == null) {
        state = state.copyWith(isLoading: false, error: result.message);
        return;
      }
      state = AuthState(
        stage: AuthStage.signedIn,
        user: result.user,
        isLoading: false,
      );
      return;
    }

    if (state.pendingUserId == null || state.pendingUserId!.isEmpty) {
      state = AuthState.signedOut.copyWith(
        isLoading: false,
        error: 'No pending authentication.',
      );
      return;
    }

    final result = await _authService.verifyEmail(
      userId: state.pendingUserId!,
      code: code.trim(),
    );
    if (!result.success || result.user == null) {
      state = state.copyWith(isLoading: false, error: result.message);
      return;
    }
    state = AuthState(
      stage: AuthStage.signedIn,
      user: result.user,
      isLoading: false,
    );
  }

  Future<void> logout() async {
    await _authService.logout();
    state = AuthState.signedOut;
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }
}

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

final authControllerProvider = StateNotifierProvider<AuthController, AuthState>(
  (ref) {
    return AuthController(ref.watch(authServiceProvider));
  },
);
