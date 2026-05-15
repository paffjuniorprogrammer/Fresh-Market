class AppConstants {
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: 'https://qhpfppsdjmibucurucui.supabase.co');
  static const String supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: 'sb_publishable_EmsYOaccLHFQg2FEFFn5qw_xxqUd1bo');
  
  // Firebase Web Configuration
  static const String firebaseApiKey = String.fromEnvironment('FIREBASE_API_KEY', defaultValue: '');
  static const String firebaseProjectId = String.fromEnvironment('FIREBASE_PROJECT_ID', defaultValue: 'potato-dashboard-fcm-777666');
  static const String firebaseMessagingSenderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID', defaultValue: '351902567984');
  static const String firebaseAppId = String.fromEnvironment('FIREBASE_APP_ID', defaultValue: '1:351902567984:web:0b0e474a8c42b4b8e327f5');
  static const String firebaseVapidKey = String.fromEnvironment('FIREBASE_VAPID_KEY', defaultValue: '');

  static const String defaultBusinessName = 'PAFLY';

  // Update these coordinates to your actual PAFLY shop location.
  static const double paflyLatitude = -1.4995;
  static const double paflyLongitude = 29.6348;
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
  static const String authRecoveryRedirectUrl = 'pafly://reset-password';
  static const String authConfirmationRedirectUrl =
      'pafly://auth-confirmation';
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
