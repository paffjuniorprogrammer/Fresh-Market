import 'package:supabase_flutter/supabase_flutter.dart';

const _categoriesTable = 'categories';
const _productsTable = 'products';
const _customersTable = 'customers';
const _ordersTable = 'orders';
const _debtsView = 'outstanding_debts';
const _clientSummariesView = 'client_summaries';
const _productsBucket = 'products';
const _placeOrderRpc = 'place_order';
const _recordOrderPaymentRpc = 'record_order_payment';
const _cancelOrderRpc = 'cancel_order';
const _backendSetupScriptPath = 'supabase/schema.sql';

const _schemaResources = <String>[
  _categoriesTable,
  _productsTable,
  _customersTable,
  _ordersTable,
  _debtsView,
  _clientSummariesView,
  _placeOrderRpc,
  _recordOrderPaymentRpc,
  _cancelOrderRpc,
];

bool isMissingSchemaError(Object error) {
  final message = error.toString().toLowerCase();
  if (error is PostgrestException) {
    final details = '${error.details ?? ''}'.toLowerCase();
    final postgrestMessage = error.message.toLowerCase();
    return error.code == 'PGRST205' ||
        error.code == 'PGRST202' ||
        error.code == '42P01' ||
        details.contains('schema cache') ||
        postgrestMessage.contains('schema cache') ||
        _schemaResources.any(
          (resource) =>
              details.contains(resource) ||
              postgrestMessage.contains(resource) ||
              message.contains(resource),
        );
  }
  return _schemaResources.any(message.contains);
}

bool isMissingProductsBucketError(Object error) {
  final message = error.toString().toLowerCase();
  return message.contains(_productsBucket) &&
      (message.contains('bucket') || message.contains('not found'));
}

String friendlyDataError(Object error, {required String fallbackMessage}) {
  if (isMissingSchemaError(error)) {
    return 'Supabase is connected, but the full app schema is not installed '
        'yet. Run the SQL in `$_backendSetupScriptPath` inside the Supabase '
        'SQL editor, then restart the app.';
  }
  if (isMissingProductsBucketError(error)) {
    return 'The `$_productsBucket` storage bucket is missing. Run the SQL in '
        '`$_backendSetupScriptPath` to create the bucket and policies, then '
        'try again.';
  }
  return fallbackMessage;
}

String friendlyAuthErrorMessage(
  Object error, {
  String fallbackMessage = 'Authentication failed.',
}) {
  final message = error.toString().toLowerCase();

  if (message.contains('rate limit') || message.contains('too many requests')) {
    return 'Too many email requests were sent. Wait a few minutes and try again.';
  }

  if (message.contains('email') && message.contains('confirm')) {
    return 'Your email is not confirmed yet. Confirm your email first, then log in. If you did not get the email, resend it from the confirmation screen.';
  }

  if (message.contains('weak password') ||
      message.contains('password should be')) {
    return 'Your password is too weak. Use at least 8 characters, one uppercase letter, one lowercase letter, and one number.';
  }

  if (message.contains('username is already taken') ||
      message.contains('users_name_normalized_unique_idx')) {
    return 'That username is already taken. Choose a different one.';
  }

  if (message.contains('phone number is already linked') ||
      message.contains('users_phone_normalized_unique_idx') ||
      message.contains('users_phone_key')) {
    return 'That phone number is already linked to another account.';
  }

  if (message.contains('email address is already linked') ||
      message.contains('user already registered') ||
      message.contains('already registered') ||
      message.contains('users_email_normalized_unique_idx')) {
    return 'That email address already has an account.';
  }

  return fallbackMessage.isEmpty
      ? 'Something went wrong. Please try again.'
      : fallbackMessage;
}

String friendlyAccountIdentityErrorMessage(
  Object error, {
  String fallbackMessage = 'Something went wrong. Please try again.',
}) {
  return friendlyAuthErrorMessage(
    error,
    fallbackMessage: fallbackMessage,
  );
}

bool isEmailNotConfirmedAuthError(Object error) {
  final message = error.toString().toLowerCase();
  return message.contains('email') &&
      (message.contains('confirm') ||
          message.contains('not confirmed') ||
          message.contains('unconfirmed'));
}
