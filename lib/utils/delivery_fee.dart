import 'package:potato_app/models/business_profile.dart';
import 'package:potato_app/utils/constants.dart';

double calculateDeliveryFee({
  required double distanceKm,
  required double orderAmount,
  BusinessProfile? profile,
}) {
  final baseFee = profile?.deliveryBaseFee ?? AppConstants.baseDeliveryFee;
  final threshold =
      profile?.deliveryDistanceThresholdKm ??
      AppConstants.deliveryDistanceThresholdKm;
  final extraKmFee =
      profile?.deliveryExtraKmFee ?? AppConstants.deliveryExtraKmFee;
  final orderThreshold =
      profile?.deliveryOrderThreshold ?? AppConstants.deliveryOrderThreshold;
  final extraOrderPercent =
      profile?.deliveryExtraOrderPercent ??
      AppConstants.deliveryExtraOrderPercent;

  double fee = baseFee;

  if (distanceKm > threshold) {
    final extraKm = distanceKm - threshold;
    fee += extraKm * extraKmFee;
  }

  if (orderAmount > orderThreshold) {
    final extra = orderAmount - orderThreshold;
    fee += extra * extraOrderPercent;
  }

  return fee;
}
