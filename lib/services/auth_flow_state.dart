class AuthFlowState {
  AuthFlowState._();

  static final AuthFlowState instance = AuthFlowState._();

  bool _passwordRecoveryPending = false;
  bool _signupConfirmationPending = false;

  bool get isPasswordRecoveryPending => _passwordRecoveryPending;
  bool get isSignupConfirmationPending => _signupConfirmationPending;

  void markPasswordRecoveryPending() {
    _passwordRecoveryPending = true;
  }

  void clearPasswordRecoveryPending() {
    _passwordRecoveryPending = false;
  }

  void markSignupConfirmationPending() {
    _signupConfirmationPending = true;
  }

  void clearSignupConfirmationPending() {
    _signupConfirmationPending = false;
  }
}
