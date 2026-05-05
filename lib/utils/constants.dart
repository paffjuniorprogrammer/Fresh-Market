class AppConstants {
  static const String supabaseUrl = 'https://qhpfppsdjmibucurucui.supabase.co';
  static const String supabaseAnonKey =
      'sb_publishable_EmsYOaccLHFQg2FEFFn5qw_xxqUd1bo';
  static const String defaultBusinessName = 'Fresh Market';

  // Update these coordinates to your actual Fresh Market shop location.
  static const double freshMarketLatitude = -1.4995;
  static const double freshMarketLongitude = 29.6348;
  static const double baseDeliveryFee = 500;
  static const double deliveryDistanceThresholdKm = 4;
  static const double deliveryExtraKmFee = 200;
  static const double deliveryOrderThreshold = 20000;
  static const double deliveryExtraOrderPercent = 0.20;

  static const String ordersTable = 'orders';
  static const String shopsTable = 'shops';
  static const String productsTable = 'products';
  static const String categoriesTable = 'categories';
  static const String usersTable = 'users';
  static const String locationsTable = 'locations';
  static const String adminTokensTable = 'admin_tokens';
  static const String clientTokensTable = 'client_tokens';
  static const String businessProfileTable = 'business_profile';
  static const String debtsView = 'outstanding_debts';
  static const String clientSummariesView = 'client_summaries';
  static const String productsBucket = 'products';
  static const String authRecoveryRedirectUrl = 'freshmarket://reset-password';
  static const String authConfirmationRedirectUrl =
      'freshmarket://auth-confirmation';
  @Deprecated('Use authRecoveryRedirectUrl or authConfirmationRedirectUrl.')
  static const String authRedirectUrl = authRecoveryRedirectUrl;
  static const String ensureCurrentUserProfileRpc =
      'ensure_current_user_profile';

  static const String recordOrderPaymentRpc = 'record_order_payment';
  static const String recordOrderPaymentFunction = 'record-order-payment';
  static const String cancelOrderRpc = 'cancel_order';
  static const String placeOrderRpc = 'place_order';
  static const String notifyAdminOrderFunction = 'notify-admin-new-order';
  static const String notifyClientEventFunction = 'notify-client-event';
}
