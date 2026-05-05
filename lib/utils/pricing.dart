double calculateSellingPrice({
  required double purchasePrice,
  required double profitPercent,
}) {
  if (purchasePrice <= 0) return 0;
  final percent = profitPercent < 0 ? 0 : profitPercent;
  return purchasePrice + (purchasePrice * (percent / 100));
}
