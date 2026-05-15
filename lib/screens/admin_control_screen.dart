import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image/image.dart' as img;

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:potato_app/models/business_profile.dart';
import 'package:potato_app/models/live_location.dart';
import 'package:potato_app/models/shop.dart';
import 'package:potato_app/services/notification_service.dart';
import 'package:potato_app/services/push_notification_service.dart';
import 'package:potato_app/utils/constants.dart';
import 'package:potato_app/widgets/admin_console_widgets.dart';

const _categoriesTable = 'categories';
const _productsTable = 'products';
const _ordersTable = 'orders';
const _locationsTable = 'locations';
const _businessProfileTable = 'business_profile';
const _debtsView = 'outstanding_debts';
const _clientSummariesView = 'client_summaries';
const _productsBucket = 'products';

String _formatKg(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toStringAsFixed(1);
}

String _kgLabel(double value) => '${_formatKg(value)} Kg';
String _formatQuantity(double value, String unit) =>
    unit.toLowerCase() == 'pc' ? value.round().toString() : _formatKg(value);
String _qtyLabel(double value, String unit) {
  if (unit.toLowerCase() == 'pc') {
    return '${_formatQuantity(value, unit)} Pc';
  }
  return _kgLabel(value);
}

String _rateLabel(num value, String unit) =>
    '${_moneyLabel(value)}/${unit.toLowerCase()}';
String _moneyLabel(num value) => '${value.toStringAsFixed(0)} Frw';
String _paymentBalanceLabel(num value) {
  final roundedValue = double.parse(value.toStringAsFixed(2));
  if ((roundedValue - roundedValue.roundToDouble()).abs() < 0.001) {
    return _moneyLabel(roundedValue);
  }
  return '${roundedValue.toStringAsFixed(2)} Frw';
}

double? _parsePaymentAmount(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;

  final cleaned = trimmed.replaceAll(RegExp(r'[^0-9,.-]'), '');
  if (cleaned.isEmpty) return null;

  final commaCount = ','.allMatches(cleaned).length;
  final dotCount = '.'.allMatches(cleaned).length;
  String normalized = cleaned;

  if (commaCount > 0 && dotCount > 0) {
    normalized = cleaned.replaceAll(',', '');
  } else if (commaCount > 0 && dotCount == 0) {
    final lastComma = cleaned.lastIndexOf(',');
    final digitsAfter = cleaned.length - lastComma - 1;
    if (commaCount == 1 && digitsAfter <= 2) {
      normalized = cleaned.replaceAll(',', '.');
    } else {
      normalized = cleaned.replaceAll(',', '');
    }
  }

  return double.tryParse(normalized);
}

String _formatPercent(double value) {
  if (value == value.roundToDouble()) {
    return value.toStringAsFixed(0);
  }
  return value.toStringAsFixed(2);
}

double _sellingPriceForPurchase(double purchasePrice, double profitPercentage) {
  final sellingPrice = purchasePrice * (1 + profitPercentage / 100);
  return double.parse(sellingPrice.toStringAsFixed(2));
}

double _purchasePriceForSelling(double sellingPrice, double profitPercentage) {
  if (profitPercentage <= 0) {
    return double.parse(sellingPrice.toStringAsFixed(2));
  }
  final purchasePrice = sellingPrice / (1 + profitPercentage / 100);
  return double.parse(purchasePrice.toStringAsFixed(2));
}

String _orderDateLabel(DateTime? value) {
  if (value == null) {
    return 'Saved recently';
  }
  final date = value.toLocal();
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  return '${twoDigits(date.day)}/${twoDigits(date.month)}/${date.year} '
      '${twoDigits(date.hour)}:${twoDigits(date.minute)}';
}

Uint8List _compressUploadImage(Uint8List sourceBytes) {
  final decoded = img.decodeImage(sourceBytes);
  if (decoded == null) {
    return sourceBytes;
  }

  img.Image resizeWithin(img.Image image, int maxDimension) {
    if (image.width <= maxDimension && image.height <= maxDimension) {
      return image;
    }
    if (image.width >= image.height) {
      return img.copyResize(
        image,
        width: maxDimension,
        interpolation: img.Interpolation.average,
      );
    }
    return img.copyResize(
      image,
      height: maxDimension,
      interpolation: img.Interpolation.average,
    );
  }

  var maxDimension = 1600;
  var quality = 82;
  Uint8List encodedBytes = sourceBytes;

  while (true) {
    final resized = resizeWithin(decoded, maxDimension);
    encodedBytes = Uint8List.fromList(img.encodeJpg(resized, quality: quality));

    if (encodedBytes.lengthInBytes <= 4 * 1024 * 1024 ||
        (maxDimension <= 900 && quality <= 60)) {
      break;
    }

    if (quality > 60) {
      quality -= 10;
    } else {
      maxDimension -= 200;
      quality = 75;
    }
  }

  return encodedBytes;
}

String _friendlyAdminError(Object error, {required String fallbackMessage}) {
  final message = error.toString().toLowerCase();
  if (message.contains('this order is already fully paid')) {
    return 'This order is already fully paid.';
  }
  if (message.contains('this order is already completed')) {
    return 'This order is already completed and cannot receive additional payments.';
  }
  if (message.contains('cancelled orders cannot receive payments')) {
    return 'Cancelled orders cannot receive payments.';
  }
  if (message.contains('only admins can record payments')) {
    return 'Only admins can record payments.';
  }
  if (message.contains('selected order was not found')) {
    return 'This order could not be found anymore. Refresh and try again.';
  }
  if (message.contains('payment amount must be greater than zero')) {
    return 'Payment amount must be greater than zero.';
  }
  if (message.contains('paid amount cannot exceed the total order price')) {
    return 'Payment amount is higher than the remaining balance.';
  }
  if (message.contains('missing authorization token') ||
      message.contains('you must be signed in')) {
    return 'Please sign in again before recording payments.';
  }
  if (message.contains('payment workflow returned no result')) {
    return 'Payment did not complete successfully. Reload and try again.';
  }
  if (message.contains('schema cache') ||
      message.contains('categories') ||
      message.contains(_businessProfileTable) ||
      message.contains('client_summaries')) {
    return 'Some admin data is out of date or missing. Reload the app after running the latest `supabase/schema.sql`.';
  }
  if (message.contains(_productsBucket) && message.contains('bucket')) {
    return 'Product image storage is not ready yet. Run `supabase/schema.sql` and try again.';
  }
  if (message.contains("type 'null' is not a subtype") ||
      message.contains('format exception') ||
      message.contains('invalid cast')) {
    return 'Some saved records have missing values. Open the affected item and save it again, or clean the old data in Supabase.';
  }
  return '$fallbackMessage\n\nPlease check the saved data and try again.';
}

class _AdminUi {
  static const primary = Color(0xFF2E7D32);
  static const dark = Color(0xFF2F3B45);
}

class _AdminCategory {
  final String id;
  final String name;
  final String imageUrl;
  final double profitPercentage;
  final DateTime? createdAt;

  const _AdminCategory({
    required this.id,
    required this.name,
    required this.imageUrl,
    required this.profitPercentage,
    this.createdAt,
  });

  factory _AdminCategory.fromJson(Map<String, dynamic> json) {
    return _AdminCategory(
      id: '${json['id']}',
      name: '${json['name'] ?? ''}',
      imageUrl: '${json['image_url'] ?? ''}',
      profitPercentage: (json['profit_percentage'] as num?)?.toDouble() ?? 0,
      createdAt: json['created_at'] != null
          ? DateTime.parse('${json['created_at']}')
          : null,
    );
  }
}

class _AdminProduct {
  final String id;
  final String? shopId;
  final String name;
  final String description;
  final String imageUrl;
  final String unit;
  final String? categoryId;
  final double? purchasePrice;
  final double? sellingPrice;
  final double price;
  final double? discountPrice;
  final double? discountThresholdKg;
  final double quantity;
  final bool isAvailable;
  final DateTime? createdAt;

  const _AdminProduct({
    required this.id,
    this.shopId,
    required this.name,
    required this.description,
    required this.imageUrl,
    required this.unit,
    required this.price,
    required this.quantity,
    required this.isAvailable,
    this.categoryId,
    this.purchasePrice,
    this.sellingPrice,
    this.discountPrice,
    this.discountThresholdKg,
    this.createdAt,
  });

  double get displayPrice => sellingPrice ?? price;

  bool get hasDiscount =>
      discountPrice != null &&
      discountThresholdKg != null &&
      discountThresholdKg! > 0 &&
      discountPrice! < displayPrice;

  factory _AdminProduct.fromJson(Map<String, dynamic> json) {
    return _AdminProduct(
      id: '${json['id']}',
      shopId: json['shop_id'] as String?,
      name: '${json['name'] ?? ''}',
      description: '${json['description'] ?? ''}',
      imageUrl: '${json['image_url'] ?? ''}',
      unit: '${json['unit'] ?? 'kg'}',
      categoryId: json['category_id'] as String?,
      purchasePrice: (json['purchase_price'] as num?)?.toDouble(),
      sellingPrice: (json['selling_price'] as num?)?.toDouble(),
      price: (json['price'] as num?)?.toDouble() ?? 0,
      discountPrice: (json['discount_price'] as num?)?.toDouble(),
      discountThresholdKg: (json['discount_threshold_kg'] as num?)?.toDouble(),
      quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
      isAvailable: json['is_available'] as bool? ?? true,
      createdAt: json['created_at'] != null
          ? DateTime.parse('${json['created_at']}')
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'shop_id': shopId,
      'name': name,
      'description': description,
      'image_url': imageUrl,
      'unit': unit,
      'category_id': categoryId,
      'purchase_price': purchasePrice,
      'selling_price': sellingPrice ?? price,
      'price': price,
      'discount_price': discountPrice,
      'discount_threshold_kg': discountThresholdKg,
      'quantity': quantity,
      'is_available': isAvailable,
    };
  }
}

class _AdminOrder {
  final int id;
  final String? shopId;
  final String? shopName;
  final String? clientId;
  final String clientName;
  final String phone;
  final String location;
  final String? deliveryLocationLabel;
  final double? deliveryLatitude;
  final double? deliveryLongitude;
  final DateTime? deliveryPositionUpdatedAt;
  final List<_AdminOrderItem> items;
  final String? productId;
  final String? productName;
  final double? quantityKg;
  final double? pricePerKg;
  final double totalPrice;
  final double deliveryFee;
  final double paidAmount;
  final bool isCredit;
  final String? paymentMethod;
  final String status;
  final String? cancelReason;
  final DateTime? createdAt;
  final double discountAmount;
  final String? promoCodeId;

  const _AdminOrder({
    required this.id,
    this.shopId,
    this.shopName,
    this.clientId,
    required this.clientName,
    required this.phone,
    required this.location,
    this.deliveryLocationLabel,
    this.deliveryLatitude,
    this.deliveryLongitude,
    this.deliveryPositionUpdatedAt,
    required this.items,
    this.productId,
    this.productName,
    this.quantityKg,
    this.pricePerKg,
    required this.totalPrice,
    required this.deliveryFee,
    required this.paidAmount,
    required this.isCredit,
    this.paymentMethod,
    required this.status,
    this.cancelReason,
    this.createdAt,
    this.discountAmount = 0,
    this.promoCodeId,
  });

  /// Balance = after-discount total - amount paid
  double get balance {
    final currentBalance = totalPrice - paidAmount;
    if (currentBalance <= 0) return 0;
    return double.parse(currentBalance.toStringAsFixed(2));
  }

  double get paymentInputMax {
    final currentBalance = balance;
    if (currentBalance <= 0) return 0;
    return currentBalance.ceilToDouble();
  }

  List<_AdminOrderItem> get normalizedItems {
    if (items.isNotEmpty) {
      return items;
    }
    if (productId == null || productName == null) {
      return const [];
    }
    return [
      _AdminOrderItem(
        productId: productId!,
        productName: productName!,
        quantityKg: quantityKg ?? 0,
        pricePerKg: pricePerKg ?? 0,
        unit: 'kg',
      ),
    ];
  }

  String get displayProductName {
    final entries = normalizedItems;
    if (entries.isEmpty) {
      return productName?.trim().isNotEmpty == true
          ? productName!.trim()
          : 'Order';
    }
    if (entries.length == 1) {
      return entries.first.productName;
    }
    return '${entries.first.productName} + ${entries.length - 1} more';
  }

  int get itemsCount => normalizedItems.length;

  factory _AdminOrder.fromJson(Map<String, dynamic> json) {
    final parsedItems = <_AdminOrderItem>[];
    if (json['order_items'] is List) {
      parsedItems.addAll(
        (json['order_items'] as List<dynamic>).map(
          (item) => _AdminOrderItem.fromJson(item as Map<String, dynamic>),
        ),
      );
    }
    final deliveryLatitudeValue = json['delivery_latitude'];
    final deliveryLongitudeValue = json['delivery_longitude'];
    final deliveryPositionUpdatedAtValue = json['delivery_position_updated_at'];
    return _AdminOrder(
      id: json['id'] as int,
      shopId: json['shop_id']?.toString(),
      shopName: (json['shops'] as Map?)?['name']?.toString(),
      clientId: json['client_id']?.toString(),
      clientName: '${json['customer_name'] ?? ''}',
      phone: '${json['phone'] ?? ''}',
      location: '${json['location'] ?? ''}',
      deliveryLocationLabel: json['delivery_location_label']?.toString(),
      deliveryLatitude: deliveryLatitudeValue == null
          ? null
          : (deliveryLatitudeValue as num?)?.toDouble(),
      deliveryLongitude: deliveryLongitudeValue == null
          ? null
          : (deliveryLongitudeValue as num?)?.toDouble(),
      deliveryPositionUpdatedAt: deliveryPositionUpdatedAtValue != null
          ? DateTime.parse('$deliveryPositionUpdatedAtValue')
          : null,
      items: parsedItems,
      productId: json['product_id']?.toString(),
      productName: json['product_name']?.toString(),
      quantityKg: (json['quantity_kg'] as num?)?.toDouble(),
      pricePerKg: (json['price_per_kg'] as num?)?.toDouble(),
      totalPrice: (json['total_price'] as num?)?.toDouble() ?? 0,
      deliveryFee: (json['delivery_fee'] as num?)?.toDouble() ?? 0,
      paidAmount: (json['paid_amount'] as num? ?? 0).toDouble(),
      isCredit: json['is_credit'] as bool? ?? false,
      paymentMethod: json['payment_method']?.toString(),
      status: '${json['status'] ?? 'Pending'}',
      cancelReason: json['cancel_reason']?.toString(),
      createdAt: json['created_at'] != null
          ? DateTime.parse('${json['created_at']}')
          : null,
      discountAmount: (json['discount_amount'] as num?)?.toDouble() ?? 0,
      promoCodeId: json['promo_code_id']?.toString(),
    );
  }
}

class _AdminOrderItem {
  final String productId;
  final String productName;
  final double quantityKg;
  final double pricePerKg;
  final String unit;

  const _AdminOrderItem({
    required this.productId,
    required this.productName,
    required this.quantityKg,
    required this.pricePerKg,
    required this.unit,
  });

  factory _AdminOrderItem.fromJson(Map<String, dynamic> json) {
    final productData = json['products'] as Map<String, dynamic>?;
    return _AdminOrderItem(
      productId: '${json['product_id'] ?? ''}',
      productName: '${json['product_name'] ?? ''}',
      quantityKg: ((json['quantity_kg'] ?? 0) as num?)?.toDouble() ?? 0,
      pricePerKg: ((json['price_per_kg'] ?? 0) as num?)?.toDouble() ?? 0,
      unit:
          json['unit']?.toString() ?? productData?['unit']?.toString() ?? 'kg',
    );
  }
}

class _AdminDebt {
  final String clientName;
  final String phone;
  final String location;
  final String productId;
  final String productName;
  final double quantityKg;
  final double totalAmount;
  final double paid;
  final double balance;

  const _AdminDebt({
    required this.clientName,
    required this.phone,
    required this.location,
    required this.productId,
    required this.productName,
    required this.quantityKg,
    required this.totalAmount,
    required this.paid,
    required this.balance,
  });

  factory _AdminDebt.fromJson(Map<String, dynamic> json) {
    return _AdminDebt(
      clientName: '${json['customer_name'] ?? ''}',
      phone: '${json['phone'] ?? ''}',
      location: '${json['location'] ?? ''}',
      productId: '${json['product_id']}',
      productName: '${json['product_name'] ?? ''}',
      quantityKg: (json['quantity_kg'] as num?)?.toDouble() ?? 0,
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0,
      paid: (json['paid_amount'] as num?)?.toDouble() ?? 0,
      balance: (json['balance'] as num?)?.toDouble() ?? 0,
    );
  }
}

class _ClientSummary {
  final String clientName;
  final String phone;
  final String location;
  final int ordersCount;
  final double totalPaid;
  final double totalDebt;
  final DateTime? lastOrderAt;

  const _ClientSummary({
    required this.clientName,
    required this.phone,
    required this.location,
    required this.ordersCount,
    required this.totalPaid,
    required this.totalDebt,
    this.lastOrderAt,
  });

  factory _ClientSummary.fromJson(Map<String, dynamic> json) {
    return _ClientSummary(
      clientName: '${json['client_name'] ?? json['customer_name'] ?? 'Client'}',
      phone: '${json['phone'] ?? ''}',
      location: '${json['location'] ?? ''}',
      ordersCount: (json['orders_count'] as num? ?? 0).toInt(),
      totalPaid: (json['total_paid'] as num? ?? 0).toDouble(),
      totalDebt: (json['total_debt'] as num? ?? 0).toDouble(),
      lastOrderAt: json['last_order_at'] != null
          ? DateTime.parse('${json['last_order_at']}')
          : null,
    );
  }
}

class _PickedImageData {
  final Uint8List bytes;
  final String fileName;
  final String mimeType;

  const _PickedImageData({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
  });
}

class _TopProductAggregate {
  final _AdminProduct product;
  double quantitySold;
  double totalRevenue;

  _TopProductAggregate({
    required this.product,
    required this.quantitySold,
    required this.totalRevenue,
  });
}

class _AdminPromoCode {
  final String id;
  final String code;
  final String? description;
  final String type;
  final double value;
  final String? freeProductId;
  final double minPurchaseAmount;
  final int maxUsesPerUser;
  final int? totalMaxUses;
  final DateTime? expiryDate;
  final bool isActive;
  final bool isVisibleToAll;
  final DateTime createdAt;

  _AdminPromoCode({
    required this.id,
    required this.code,
    this.description,
    required this.type,
    this.value = 0,
    this.freeProductId,
    this.minPurchaseAmount = 0,
    this.maxUsesPerUser = 1,
    this.totalMaxUses,
    this.expiryDate,
    this.isActive = true,
    this.isVisibleToAll = false,
    required this.createdAt,
  });

  factory _AdminPromoCode.fromJson(Map<String, dynamic> json) {
    return _AdminPromoCode(
      id: '${json['id']}',
      code: '${json['code'] ?? ''}',
      description: json['description'] as String?,
      type: '${json['type'] ?? 'discount_fixed'}',
      value: (json['value'] as num?)?.toDouble() ?? 0,
      freeProductId: json['free_product_id'] as String?,
      minPurchaseAmount: (json['min_purchase_amount'] as num?)?.toDouble() ?? 0,
      maxUsesPerUser: (json['max_uses_per_user'] as num?)?.toInt() ?? 1,
      totalMaxUses: (json['total_max_uses'] as num?)?.toInt(),
      expiryDate: json['expiry_date'] != null
          ? DateTime.parse('${json['expiry_date']}')
          : null,
      isActive: json['is_active'] == true,
      isVisibleToAll: json['is_visible_to_all'] == true,
      createdAt: json['created_at'] != null
          ? DateTime.parse('${json['created_at']}')
          : DateTime.now(),
    );
  }
}

enum _AdminSection {
  dashboard,
  products,
  priceControl,
  categories,
  promotions,
  orders,
  clients,
  debts,
  reports,
  settings,
}

class AdminControlScreen extends StatefulWidget {
  const AdminControlScreen({super.key});

  @override
  State<AdminControlScreen> createState() => _AdminControlScreenState();
}

class _AdminControlScreenState extends State<AdminControlScreen> {
  List<Shop> shops = [];
  List<_AdminCategory> categories = [];
  List<_AdminProduct> products = [];
  List<_AdminOrder> orders = [];
  List<_AdminDebt> debts = [];
  List<_ClientSummary> clients = [];
  List<_AdminPromoCode> promoCodes = [];

  List<LiveLocation> liveLocations = [];
  bool _isLoading = true;
  Object? _loadError;
  _AdminSection _section = _AdminSection.dashboard;
  bool _sidebarCollapsed = false;
  RealtimeChannel? _syncChannel;
  Timer? _adminRefreshDebounce;
  bool _isRefreshingAdminData = false;
  bool _queuedAdminRefresh = false;
  String? _priceControlCategoryId;
  String? _selectedShopId;
  BusinessProfile _businessProfile = BusinessProfile.fallback();

  @override
  void initState() {
    super.initState();
    NotificationService.instance.setupAdminListener();
    _setupRealtimeSync();
    _loadAdminData();
  }

  @override
  void dispose() {
    _adminRefreshDebounce?.cancel();
    _syncChannel?.unsubscribe();
    super.dispose();
  }

  void _scheduleAdminRefresh() {
    _adminRefreshDebounce?.cancel();
    _adminRefreshDebounce = Timer(const Duration(milliseconds: 450), () {
      unawaited(_loadAdminData(showLoading: false));
    });
  }

  void _setupRealtimeSync() {
    _syncChannel = Supabase.instance.client
        .channel('admin-dashboard-sync')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          callback: (_) => _scheduleAdminRefresh(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'products',
          callback: (_) => _scheduleAdminRefresh(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'users',
          callback: (_) => _scheduleAdminRefresh(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'categories',
          callback: (_) => _scheduleAdminRefresh(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'locations',
          callback: (_) => _scheduleAdminRefresh(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: _businessProfileTable,
          callback: (_) => _scheduleAdminRefresh(),
        )
        .subscribe();
  }

  Map<String, _AdminCategory> get _categoryById => {
    for (final category in categories) category.id: category,
  };

  Map<String, Shop> get _shopById => {for (final shop in shops) shop.id: shop};


  String _shopNameForId(String? shopId) {
    if (shopId == null) return 'PAFLY';
    return _shopById[shopId]?.name ?? 'PAFLY';
  }

  List<_AdminProduct> get _visibleProducts {
    final shopId = _selectedShopId;
    if (shopId == null) return products;
    return products.where((product) => product.shopId == shopId).toList();
  }

  List<_AdminOrder> get _visibleOrders {
    final shopId = _selectedShopId;
    if (shopId == null) return orders;
    return orders.where((order) => order.shopId == shopId).toList();
  }

  Map<String, LiveLocation> get _liveLocationByUserId {
    final result = <String, LiveLocation>{};
    for (final location in liveLocations) {
      result.putIfAbsent(location.userId, () => location);
    }
    return result;
  }

  Map<String, LiveLocation> get _liveLocationByPhone {
    final result = <String, LiveLocation>{};
    for (final location in liveLocations) {
      final phone = location.phone.trim();
      if (phone.isEmpty) continue;
      result.putIfAbsent(phone, () => location);
    }
    return result;
  }

  int get _pendingOrdersCount =>
      _visibleOrders.where((item) => item.status == 'Pending').length;
  List<_AdminProduct> get _lowStockProducts => _visibleProducts
      .where((item) => item.quantity > 0 && item.quantity < 50)
      .toList();
  List<_AdminOrder> get _activeOrders =>
      _visibleOrders.where((order) => order.status != 'Cancelled').toList();
  Map<String, _AdminProduct> get _productById => {
    for (final product in products) product.id: product,
  };

  String _unitForOrderItem(_AdminOrderItem item) {
    if (item.unit.trim().isNotEmpty) {
      return item.unit;
    }
    return _unitForProductId(item.productId);
  }

  String _unitForProductId(String productId) =>
      _productById[productId]?.unit ?? 'kg';

  _AdminCategory? get _selectedPriceControlCategory {
    if (categories.isEmpty) {
      return null;
    }
    if (_priceControlCategoryId != null) {
      final selected = _categoryById[_priceControlCategoryId!];
      if (selected != null) {
        return selected;
      }
    }
    return categories.first;
  }

  List<_AdminProduct> get _priceControlProducts {
    final category = _selectedPriceControlCategory;
    if (category == null) {
      return const [];
    }
    return _visibleProducts
        .where((product) => product.categoryId == category.id)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  double _profitPercentageForCategoryId(String? categoryId) {
    if (categoryId == null) {
      return 0;
    }
    return _categoryById[categoryId]?.profitPercentage ?? 0;
  }

  double _sellingPriceForCategoryPurchase(
    double purchasePrice,
    String? categoryId,
  ) {
    return _sellingPriceForPurchase(
      purchasePrice,
      _profitPercentageForCategoryId(categoryId),
    );
  }

  double _initialPurchasePriceForEdit(_AdminProduct product) {
    final currentSelling = product.displayPrice;
    final profit = _profitPercentageForCategoryId(product.categoryId);
    if (product.purchasePrice != null) {
      return product.purchasePrice!;
    }
    return _purchasePriceForSelling(currentSelling, profit);
  }

  Future<int> _syncCategoryProductPrices({
    required String categoryId,
    required double sourceProfitPercentage,
    required double targetProfitPercentage,
  }) async {
    final categoryProducts = products
        .where((product) => product.categoryId == categoryId)
        .toList();
    var updatedCount = 0;

    for (final product in categoryProducts) {
      final effectivePurchase =
          product.purchasePrice ??
          _purchasePriceForSelling(
            product.displayPrice,
            sourceProfitPercentage,
          );
      final newSellingPrice = _sellingPriceForPurchase(
        effectivePurchase,
        targetProfitPercentage,
      );

      await Supabase.instance.client
          .from(_productsTable)
          .update({
            'purchase_price': effectivePurchase,
            'selling_price': newSellingPrice,
            'price': newSellingPrice,
          })
          .eq('id', product.id);
      updatedCount++;
    }

    return updatedCount;
  }

  String _categoryNameFor(_AdminProduct product) {
    final category = product.categoryId == null
        ? null
        : _categoryById[product.categoryId!];
    return category?.name ?? 'Uncategorized';
  }

  double _purchasePriceForProduct(_AdminProduct product) {
    if (product.purchasePrice != null) {
      return product.purchasePrice!;
    }
    final profitPercentage = _profitPercentageForCategoryId(product.categoryId);
    if (profitPercentage <= 0) {
      return product.displayPrice;
    }
    return _purchasePriceForSelling(product.displayPrice, profitPercentage);
  }

  double get _totalPurchaseCost {
    return _activeOrders.fold(0.0, (total, order) {
      var runningTotal = total;
      for (final item in order.normalizedItems) {
        final product = _productById[item.productId];
        if (product == null) continue;
        runningTotal += _purchasePriceForProduct(product) * item.quantityKg;
      }
      return runningTotal;
    });
  }

  double get _totalDeliveryFees {
    return _activeOrders.fold(0.0, (total, order) => total + order.deliveryFee);
  }

  double get _totalProductRevenue {
    return _activeOrders.fold(
      0.0,
      (total, order) => total + (order.totalPrice - order.deliveryFee),
    );
  }

  double get _totalSalesRevenue {
    return _activeOrders.fold(0.0, (total, order) => total + order.totalPrice);
  }

  double get _totalDiscountsGiven {
    return _activeOrders.fold(
      0.0,
      (total, order) => total + order.discountAmount,
    );
  }

  double get _totalGrossProfit => _totalProductRevenue - _totalPurchaseCost;

  LiveLocation? _liveLocationForOrder(_AdminOrder order) {
    final clientId = order.clientId?.trim();
    if (clientId != null && clientId.isNotEmpty) {
      final liveLocation = _liveLocationByUserId[clientId];
      if (liveLocation != null) return liveLocation;
    }

    final phone = order.phone.trim();
    if (phone.isNotEmpty) {
      final liveLocation = _liveLocationByPhone[phone];
      if (liveLocation != null) return liveLocation;
    }

    return null;
  }

  String _relativeAgeLabel(DateTime value) {
    final age = DateTime.now().difference(value.toLocal());
    if (age.inMinutes < 1) return 'just now';
    if (age.inHours < 1) return '${age.inMinutes}m ago';
    if (age.inDays < 1) return '${age.inHours}h ago';
    return '${age.inDays}d ago';
  }

  String _liveLocationLabelForOrder(_AdminOrder order) {
    final liveLocation = _liveLocationForOrder(order);
    if (liveLocation != null) {
      final locationLabel = liveLocation.locationLabel.trim().isNotEmpty
          ? liveLocation.locationLabel.trim()
          : 'Live GPS ${liveLocation.latitude.toStringAsFixed(5)}, ${liveLocation.longitude.toStringAsFixed(5)}';
      return 'Live: $locationLabel (${_relativeAgeLabel(liveLocation.updatedAt)})';
    }

    final deliveryLocation = order.deliveryLocationLabel?.trim();
    if (deliveryLocation != null && deliveryLocation.isNotEmpty) {
      return 'Delivery: $deliveryLocation';
    }

    return 'Location: ${order.location}';
  }

  Uri? _mapsUriForOrder(_AdminOrder order) {
    final liveLocation = _liveLocationForOrder(order);
    if (liveLocation != null) {
      return Uri.https('www.google.com', '/maps/search/', {
        'api': '1',
        'query': '${liveLocation.latitude},${liveLocation.longitude}',
      });
    }

    final deliveryLabel = order.deliveryLocationLabel?.trim();
    if (deliveryLabel != null && deliveryLabel.isNotEmpty) {
      return Uri.https('www.google.com', '/maps/search/', {
        'api': '1',
        'query': deliveryLabel,
      });
    }

    final savedLocation = order.location.trim();
    if (savedLocation.isNotEmpty) {
      return Uri.https('www.google.com', '/maps/search/', {
        'api': '1',
        'query': savedLocation,
      });
    }

    return null;
  }

  Future<void> _openOrderLocationInMaps(_AdminOrder order) async {
    final uri = _mapsUriForOrder(order);
    if (uri == null) {
      _showAdminSnack(
        'No map location is available for this order.',
        isError: true,
      );
      return;
    }

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      _showAdminSnack('Could not open Google Maps.', isError: true);
    }
  }

  Widget _orderLocationLink(_AdminOrder order) {
    final liveLocation = _liveLocationForOrder(order);
    final deliveryLabel = order.deliveryLocationLabel?.trim();
    final label = liveLocation != null
        ? (() {
            final locationLabel = liveLocation.locationLabel.trim().isNotEmpty
                ? liveLocation.locationLabel.trim()
                : 'Live GPS ${liveLocation.latitude.toStringAsFixed(5)}, ${liveLocation.longitude.toStringAsFixed(5)}';
            return 'Live: $locationLabel (${_relativeAgeLabel(liveLocation.updatedAt)})';
          })()
        : deliveryLabel != null && deliveryLabel.isNotEmpty
        ? 'Delivery: $deliveryLabel'
        : 'Location: ${order.location}';

    final uriAvailable = _mapsUriForOrder(order) != null;
    final color = uriAvailable ? _AdminUi.primary : const Color(0xFF617066);
    final decoration = uriAvailable
        ? TextDecoration.underline
        : TextDecoration.none;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: uriAvailable ? () => _openOrderLocationInMaps(order) : null,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                uriAvailable
                    ? Icons.location_on_outlined
                    : Icons.location_city_outlined,
                size: 18,
                color: color,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: color,
                    decoration: decoration,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (uriAvailable) ...[
                const SizedBox(width: 6),
                const Icon(
                  Icons.open_in_new_rounded,
                  size: 16,
                  color: _AdminUi.primary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showAdminSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isError ? Colors.red.shade700 : _AdminUi.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  String? _required(String? value) =>
      (value == null || value.trim().isEmpty) ? 'Required' : null;

  void _signOut() {
    unawaited(Supabase.instance.client.auth.signOut());
  }

  List<AdminSidebarItemData> get _sidebarItems => [
    AdminSidebarItemData(
      label: 'Dashboard',
      icon: Icons.space_dashboard_outlined,
      isActive: _section == _AdminSection.dashboard,
      onTap: () => setState(() => _section = _AdminSection.dashboard),
    ),
    AdminSidebarItemData(
      label: 'Products',
      icon: Icons.inventory_2_outlined,
      isActive: _section == _AdminSection.products,
      onTap: () => setState(() => _section = _AdminSection.products),
    ),
    AdminSidebarItemData(
      label: 'Price Control',
      icon: Icons.price_change_outlined,
      isActive: _section == _AdminSection.priceControl,
      onTap: () => setState(() => _section = _AdminSection.priceControl),
    ),
    AdminSidebarItemData(
      label: 'Categories',
      icon: Icons.category_outlined,
      isActive: _section == _AdminSection.categories,
      onTap: () => setState(() => _section = _AdminSection.categories),
    ),
    AdminSidebarItemData(
      label: 'Promotions',
      icon: Icons.stars_rounded,
      isActive: _section == _AdminSection.promotions,
      onTap: () => setState(() => _section = _AdminSection.promotions),
    ),
    AdminSidebarItemData(
      label: 'Orders',
      icon: Icons.receipt_long_outlined,
      isActive: _section == _AdminSection.orders,
      onTap: () => setState(() => _section = _AdminSection.orders),
    ),
    AdminSidebarItemData(
      label: 'Clients',
      icon: Icons.group_outlined,
      isActive: _section == _AdminSection.clients,
      onTap: () => setState(() => _section = _AdminSection.clients),
    ),
    AdminSidebarItemData(
      label: 'Debts',
      icon: Icons.account_balance_wallet_outlined,
      isActive: _section == _AdminSection.debts,
      onTap: () => setState(() => _section = _AdminSection.debts),
    ),
    AdminSidebarItemData(
      label: 'Reports',
      icon: Icons.print_outlined,
      isActive: _section == _AdminSection.reports,
      onTap: () => setState(() => _section = _AdminSection.reports),
    ),
    AdminSidebarItemData(
      label: 'Settings',
      icon: Icons.settings_outlined,
      isActive: _section == _AdminSection.settings,
      onTap: () => setState(() => _section = _AdminSection.settings),
    ),
  ];

  List<AdminOverviewCardData> get _overviewCards => [
    AdminOverviewCardData(
      eyebrow: 'Purchase cost',
      value: _moneyLabel(_totalPurchaseCost),
      caption: 'Estimated buying cost for ordered products.',
      icon: Icons.shopping_cart_checkout_rounded,
      startColor: const Color(0xFFE8F3E9),
      endColor: const Color(0xFFCFE7D0),
    ),
    AdminOverviewCardData(
      eyebrow: 'Gross profit',
      value: _moneyLabel(_totalGrossProfit),
      caption: 'Product revenue minus purchase cost.',
      icon: Icons.trending_up_rounded,
      startColor: const Color(0xFFE7F4D6),
      endColor: const Color(0xFFC9E8A8),
    ),
    AdminOverviewCardData(
      eyebrow: 'Total sales',
      value: _moneyLabel(_totalSalesRevenue),
      caption: 'Products plus delivery fees from active orders.',
      icon: Icons.payments_rounded,
      startColor: const Color(0xFFF2EFCF),
      endColor: const Color(0xFFE4DB9E),
    ),
    AdminOverviewCardData(
      eyebrow: 'Active Promos',
      value: '${promoCodes.where((p) => p.isActive).length}',
      caption: 'Number of active coupon codes.',
      icon: Icons.stars_rounded,
      startColor: const Color(0xFFFFF2E2),
      endColor: const Color(0xFFFFE082),
    ),
  ];

  List<_AdminOrder> get _dashboardOrders => _visibleOrders
      .where((order) => order.status != 'Cancelled')
      .take(6)
      .toList();

  List<AdminRecentOrderData> get _recentOrdersData => _dashboardOrders
      .map(
        (order) => AdminRecentOrderData(
          customer: order.clientName,
          product: order.displayProductName,
          dateLabel: _orderDateLabel(order.createdAt),
          amountLabel: _moneyLabel(order.totalPrice),
        ),
      )
      .toList();

  List<AdminTopProductData> get _topProductsData {
    final aggregates = <String, _TopProductAggregate>{};

    for (final order in _visibleOrders) {
      if (order.status == 'Cancelled') continue;
      for (final item in order.normalizedItems) {
        final product = _productById[item.productId];
        if (product == null) continue;

        final existing = aggregates[product.id];
        if (existing == null) {
          aggregates[product.id] = _TopProductAggregate(
            product: product,
            quantitySold: item.quantityKg,
            totalRevenue: item.quantityKg * item.pricePerKg,
          );
        } else {
          existing.quantitySold += item.quantityKg;
          existing.totalRevenue += item.quantityKg * item.pricePerKg;
        }
      }
    }

    final sorted = aggregates.values.toList()
      ..sort((left, right) {
        final quantityComparison = right.quantitySold.compareTo(
          left.quantitySold,
        );
        if (quantityComparison != 0) return quantityComparison;
        return right.totalRevenue.compareTo(left.totalRevenue);
      });

    return sorted
        .take(5)
        .map(
          (aggregate) => AdminTopProductData(
            name: aggregate.product.name,
            subtitle: '${_kgLabel(aggregate.quantitySold)} sold',
            priceLabel: _moneyLabel(aggregate.totalRevenue),
            imageUrl: aggregate.product.imageUrl.isEmpty
                ? null
                : aggregate.product.imageUrl,
          ),
        )
        .toList();
  }

  Widget _dashboardShellSection() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final cardWidth = width >= 1400
            ? (width - 32) / 3
            : width >= 900
            ? (width - 16) / 2
            : width;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: _overviewCards
                  .map(
                    (card) => SizedBox(
                      width: cardWidth,
                      child: AdminOverviewCard(data: card),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 18),
            LayoutBuilder(
              builder: (context, innerConstraints) {
                final splitPanels = innerConstraints.maxWidth >= 980;
                final recentPanel = AdminRecentOrdersPanel(
                  orders: _recentOrdersData,
                  onViewAll: () =>
                      setState(() => _section = _AdminSection.orders),
                );
                final topPanel = AdminTopProductsPanel(
                  products: _topProductsData,
                  onViewAll: () =>
                      setState(() => _section = _AdminSection.products),
                );

                if (splitPanels) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: recentPanel),
                      const SizedBox(width: 16),
                      Expanded(child: topPanel),
                    ],
                  );
                }

                return Column(
                  children: [recentPanel, const SizedBox(height: 16), topPanel],
                );
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _loadAdminData({bool showLoading = true}) async {
    if (_isRefreshingAdminData) {
      _queuedAdminRefresh = true;
      return;
    }

    _isRefreshingAdminData = true;
    if (mounted && showLoading) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }

    try {
      // We use individual try-catches to ensure one failing request (like a missing view)
      // doesn't block the entire admin dashboard from loading.
      Future<T?> safeLoad<T>(Future<T> fetcher, String debugLabel) async {
        try {
          return await fetcher;
        } catch (e) {
          debugPrint('Admin Dashboard: Error loading $debugLabel: $e');
          return null;
        }
      }

      final responses = await Future.wait<dynamic>([
        safeLoad(_loadCurrentAdminUser(), 'current user profile'),
        safeLoad(_loadAdminShops(), 'shops list'),
        safeLoad(
          Supabase.instance.client
              .from(_categoriesTable)
              .select()
              .order('name'),
          'categories',
        ),
        safeLoad(
          Supabase.instance.client
              .from(_productsTable)
              .select()
              .order('created_at', ascending: false),
          'products',
        ),
        safeLoad(
          Supabase.instance.client
              .from(_locationsTable)
              .select()
              .order('updated_at', ascending: false),
          'live locations',
        ),
        safeLoad(_loadAdminOrders(), 'orders list'),
        safeLoad(
          Supabase.instance.client
              .from(_debtsView)
              .select()
              .order('balance', ascending: false),
          'outstanding debts',
        ),
        safeLoad(
          Supabase.instance.client
              .from(_clientSummariesView)
              .select()
              .order('total_debt', ascending: false),
          'client summaries',
        ),
        safeLoad(
          Supabase.instance.client
              .from(_businessProfileTable)
              .select()
              .eq('id', 1)
              .maybeSingle(),
          'business profile',
        ),
        safeLoad(
          Supabase.instance.client
              .from('promo_codes')
              .select()
              .order('created_at', ascending: false),
          'promo codes',
        ),
      ]);

      if (!mounted) return;

      setState(() {
        // Response 0: User Profile
        // final userProfile = responses[0] as Map<String, dynamic>?;


        // Response 1: Shops
        if (responses[1] != null) {
          shops = (responses[1] as List<dynamic>)
              .map((item) => Shop.fromJson(item as Map<String, dynamic>))
              .toList();
        }

        // Response 2: Categories
        if (responses[2] != null) {
          categories = (responses[2] as List<dynamic>)
              .map(
                (item) => _AdminCategory.fromJson(item as Map<String, dynamic>),
              )
              .toList();
        }

        // Response 3: Products
        if (responses[3] != null) {
          products = (responses[3] as List<dynamic>)
              .map(
                (item) => _AdminProduct.fromJson(item as Map<String, dynamic>),
              )
              .toList();
        }

        // Response 4: Live Locations
        if (responses[4] != null) {
          liveLocations = (responses[4] as List<dynamic>)
              .map(
                (item) => LiveLocation.fromJson(item as Map<String, dynamic>),
              )
              .toList();
        }

        // Response 5: Orders
        if (responses[5] != null) {
          orders = (responses[5] as List<dynamic>)
              .map((item) => _AdminOrder.fromJson(item as Map<String, dynamic>))
              .toList();
        }

        // Response 6: Debts
        if (responses[6] != null) {
          debts = (responses[6] as List<dynamic>)
              .map((item) => _AdminDebt.fromJson(item as Map<String, dynamic>))
              .toList();
        }

        // Response 7: Clients
        if (responses[7] != null) {
          clients = (responses[7] as List<dynamic>)
              .map(
                (item) => _ClientSummary.fromJson(item as Map<String, dynamic>),
              )
              .toList();
        }

        // Response 8: Business Profile
        _businessProfile = responses[8] == null
            ? BusinessProfile.fallback()
            : BusinessProfile.fromJson(
                Map<String, dynamic>.from(responses[8] as Map),
              );

        // Response 9: Promo Codes
        if (responses.length > 9 && responses[9] != null) {
          promoCodes = (responses[9] as List<dynamic>)
              .map(
                (item) => _AdminPromoCode.fromJson(item as Map<String, dynamic>),
              )
              .toList();
        }

        if (_selectedShopId != null &&
            shops.every((shop) => shop.id != _selectedShopId)) {
          _selectedShopId = null;
        }

        if (categories.isEmpty) {
          _priceControlCategoryId = null;
        } else if (_priceControlCategoryId == null ||
            categories.every(
              (category) => category.id != _priceControlCategoryId,
            )) {
          _priceControlCategoryId = categories.first.id;
        }

        _isLoading = false;
        _loadError = null;
      });
    } catch (error) {
      if (!mounted) return;
      if (showLoading) {
        setState(() {
          _isLoading = false;
          _loadError = error;
        });
      } else {
        _showAdminSnack(
          _friendlyAdminError(
            error,
            fallbackMessage: 'Unable to refresh the latest admin data.',
          ),
        );
      }
    } finally {
      _isRefreshingAdminData = false;
      if (_queuedAdminRefresh && mounted) {
        _queuedAdminRefresh = false;
        _scheduleAdminRefresh();
      }
    }
  }

  Future<List<dynamic>> _loadAdminShops() async {
    try {
      final shops = await Supabase.instance.client
          .from(AppConstants.shopsTable)
          .select()
          .order('name');
      return List<dynamic>.from(shops as List);
    } on PostgrestException catch (error) {
      final details = '${error.message} ${error.details} ${error.hint}'
          .toLowerCase();
      if (error.code == 'PGRST205' ||
          error.code == '42P01' ||
          details.contains('public.shops')) {
        return const [];
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> _loadCurrentAdminUser() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return null;
    final response = await Supabase.instance.client
        .from(AppConstants.usersTable)
        .select('id, role, approval_status')
        .eq('id', userId)
        .maybeSingle();
    return response == null ? null : Map<String, dynamic>.from(response);
  }

  Future<List<dynamic>> _loadAdminOrders() async {
    try {
      final orders = await Supabase.instance.client
          .from(_ordersTable)
          .select('*, shops(name), order_items(*, products(unit))')
          .order('created_at', ascending: false);
      return List<dynamic>.from(orders as List);
    } on PostgrestException catch (error) {
      final details = '${error.message} ${error.details} ${error.hint}'
          .toLowerCase();
      if (!details.contains('shops') && !details.contains('shop_id')) {
        rethrow;
      }
      final orders = await Supabase.instance.client
          .from(_ordersTable)
          .select('*, order_items(*, products(unit))')
          .order('created_at', ascending: false);
      return List<dynamic>.from(orders as List);
    }
  }

  Future<_PickedImageData?> _pickImageData() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) {
      return null;
    }
    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) {
      return null;
    }
    final fileName = file.name.isEmpty
        ? 'product_${DateTime.now().millisecondsSinceEpoch}.png'
        : file.name;
    final lowerName = fileName.toLowerCase();
    final mimeType = switch (true) {
      _ when lowerName.endsWith('.png') => 'image/png',
      _ when lowerName.endsWith('.webp') => 'image/webp',
      _ => 'image/jpeg',
    };
    return _prepareUploadImageData(
      bytes,
      originalFileName: fileName,
      originalMimeType: mimeType,
    );
  }

  Future<_PickedImageData> _prepareUploadImageData(
    Uint8List sourceBytes, {
    required String originalFileName,
    required String originalMimeType,
  }) async {
    final encodedBytes = await compute(_compressUploadImage, sourceBytes);
    final baseName = originalFileName.replaceAll(RegExp(r'\.[^.]+$'), '');

    return _PickedImageData(
      bytes: encodedBytes,
      fileName: '${baseName}_${DateTime.now().millisecondsSinceEpoch}.jpg',
      mimeType: 'image/jpeg',
    );
  }

  Future<String> _uploadProductImage(_PickedImageData data) async {
    final safeName = data.fileName
        .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_')
        .toLowerCase();
    final storagePath =
        'product_${DateTime.now().millisecondsSinceEpoch}_$safeName';
    await Supabase.instance.client.storage
        .from(_productsBucket)
        .uploadBinary(
          storagePath,
          data.bytes,
          fileOptions: FileOptions(contentType: data.mimeType, upsert: true),
        );
    return Supabase.instance.client.storage
        .from(_productsBucket)
        .getPublicUrl(storagePath);
  }

  String? _storageObjectPathFromPublicUrl(String? publicUrl) {
    if (publicUrl == null || publicUrl.isEmpty) return null;
    final uri = Uri.tryParse(publicUrl);
    if (uri == null) return null;
    for (var index = 0; index < uri.pathSegments.length - 1; index++) {
      if (uri.pathSegments[index] == 'public' &&
          uri.pathSegments[index + 1] == _productsBucket) {
        final objectSegments = uri.pathSegments.sublist(index + 2);
        if (objectSegments.isEmpty) return null;
        return objectSegments.join('/');
      }
    }
    return null;
  }

  Future<void> _deleteStoredImageByUrl(String? publicUrl) async {
    final storagePath = _storageObjectPathFromPublicUrl(publicUrl);
    if (storagePath == null) return;

    try {
      await Supabase.instance.client.storage.from(_productsBucket).remove([
        storagePath,
      ]);
    } catch (error) {
      debugPrint('Failed to delete stored image $storagePath: $error');
    }
  }

  InputDecoration _fieldDecoration({
    required String label,
    required IconData icon,
    String? helper,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: _AdminUi.primary),
      helperText: helper,
      filled: true,
      fillColor: const Color(0xFFF5F9F4),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Color(0xFFE0EBE0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: _AdminUi.primary, width: 1.4),
      ),
    );
  }

  String _errorText(Object error) =>
      error.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');

  String _businessGpsLabel(BusinessProfile profile) {
    if (!profile.hasCoordinates) {
      return 'Not set';
    }
    return '${profile.latitude!.toStringAsFixed(5)}, ${profile.longitude!.toStringAsFixed(5)}';
  }

  Future<Position> _getCurrentDevicePosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Turn on location services to capture the business GPS.');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      throw Exception('Location permission was denied.');
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception(
        'Location permission is permanently denied. Enable it from app settings.',
      );
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }

  Future<void> _editBusinessProfile() async {
    final businessName = TextEditingController(
      text: _businessProfile.businessName,
    );
    final phone = TextEditingController(text: _businessProfile.phone);
    final email = TextEditingController(text: _businessProfile.email);
    final location = TextEditingController(text: _businessProfile.location);
    final addressLine = TextEditingController(
      text: _businessProfile.addressLine,
    );
    final momoPayMerchantCode = TextEditingController(
      text: _businessProfile.momoPayMerchantCode,
    );
    final deliveryBaseFee = TextEditingController(
      text: _businessProfile.deliveryBaseFee.toString(),
    );
    final deliveryThreshold = TextEditingController(
      text: _businessProfile.deliveryDistanceThresholdKm.toString(),
    );
    final deliveryExtraKmFee = TextEditingController(
      text: _businessProfile.deliveryExtraKmFee.toString(),
    );
    final deliveryOrderThreshold = TextEditingController(
      text: _businessProfile.deliveryOrderThreshold.toString(),
    );
    final deliveryExtraOrderPercent = TextEditingController(
      text: (_businessProfile.deliveryExtraOrderPercent * 100).toString(),
    );
    final latitude = TextEditingController(
      text: _businessProfile.latitude?.toString() ?? '',
    );
    final longitude = TextEditingController(
      text: _businessProfile.longitude?.toString() ?? '',
    );
    final formKey = GlobalKey<FormState>();
    var isSaving = false;
    var isLocating = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> useCurrentGps() async {
            setDialogState(() => isLocating = true);
            try {
              final position = await _getCurrentDevicePosition();
              if (!dialogContext.mounted) return;
              setDialogState(() {
                latitude.text = position.latitude.toStringAsFixed(6);
                longitude.text = position.longitude.toStringAsFixed(6);
              });
            } catch (error) {
              _showAdminSnack(_errorText(error));
            } finally {
              if (dialogContext.mounted) {
                setDialogState(() => isLocating = false);
              }
            }
          }

          Future<void> saveBusinessProfile() async {
            if (!(formKey.currentState?.validate() ?? false)) return;

            final latitudeText = latitude.text.trim();
            final longitudeText = longitude.text.trim();
            if ((latitudeText.isEmpty && longitudeText.isNotEmpty) ||
                (latitudeText.isNotEmpty && longitudeText.isEmpty)) {
              _showAdminSnack(
                'Enter both latitude and longitude, or leave both empty.',
              );
              return;
            }

            final parsedLatitude = latitudeText.isEmpty
                ? null
                : double.tryParse(latitudeText);
            final parsedLongitude = longitudeText.isEmpty
                ? null
                : double.tryParse(longitudeText);

            if ((latitudeText.isNotEmpty && parsedLatitude == null) ||
                (longitudeText.isNotEmpty && parsedLongitude == null)) {
              _showAdminSnack('Latitude and longitude must be valid numbers.');
              return;
            }
            if (parsedLatitude != null &&
                (parsedLatitude < -90 || parsedLatitude > 90)) {
              _showAdminSnack('Latitude must be between -90 and 90.');
              return;
            }
            if (parsedLongitude != null &&
                (parsedLongitude < -180 || parsedLongitude > 180)) {
              _showAdminSnack('Longitude must be between -180 and 180.');
              return;
            }

            setDialogState(() => isSaving = true);
            try {
              await Supabase.instance.client
                  .from(_businessProfileTable)
                  .upsert({
                    'id': 1,
                    'business_name': businessName.text.trim(),
                    'phone': phone.text.trim(),
                    'email': email.text.trim(),
                    'location': location.text.trim(),
                    'address_line': addressLine.text.trim(),
                    'momo_pay_merchant_code': momoPayMerchantCode.text.trim(),
                    'delivery_base_fee':
                        double.tryParse(deliveryBaseFee.text) ?? 500.0,
                    'delivery_distance_threshold':
                        double.tryParse(deliveryThreshold.text) ?? 4.0,
                    'delivery_extra_km_fee':
                        double.tryParse(deliveryExtraKmFee.text) ?? 200.0,
                    'delivery_order_threshold':
                        double.tryParse(deliveryOrderThreshold.text) ?? 20000.0,
                    'delivery_extra_order_percent':
                        (double.tryParse(deliveryExtraOrderPercent.text) ??
                            20.0) /
                        100,
                    'latitude': parsedLatitude,
                    'longitude': parsedLongitude,
                    'updated_at': DateTime.now().toUtc().toIso8601String(),
                  }, onConflict: 'id');
              if (!mounted || !dialogContext.mounted) return;
              Navigator.pop(dialogContext);
              await _loadAdminData(showLoading: false);
              _showAdminSnack('Business settings saved.');
            } catch (error) {
              if (!mounted) return;
              setDialogState(() => isSaving = false);
              _showAdminSnack(
                _friendlyAdminError(
                  error,
                  fallbackMessage: 'Unable to save business settings.',
                ),
              );
            }
          }

          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            title: const Text('Business Settings'),
            content: SizedBox(
              width: 560,
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        controller: businessName,
                        decoration: _fieldDecoration(
                          label: 'Business name',
                          icon: Icons.business_outlined,
                          helper:
                              'Printed on delivery notes and used as the delivery origin label.',
                        ),
                        validator: (value) {
                          if ((value ?? '').trim().isEmpty) {
                            return 'Business name is required.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: phone,
                        keyboardType: TextInputType.phone,
                        decoration: _fieldDecoration(
                          label: 'Business phone',
                          icon: Icons.call_outlined,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: email,
                        keyboardType: TextInputType.emailAddress,
                        decoration: _fieldDecoration(
                          label: 'Business email',
                          icon: Icons.email_outlined,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: location,
                        decoration: _fieldDecoration(
                          label: 'Business location label',
                          icon: Icons.place_outlined,
                          helper:
                              'This label explains where the business is based.',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: addressLine,
                        maxLines: 2,
                        decoration: _fieldDecoration(
                          label: 'Business address',
                          icon: Icons.location_city_outlined,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: momoPayMerchantCode,
                        keyboardType: TextInputType.number,
                        decoration: _fieldDecoration(
                          label: 'MoMo Pay Merchant Code',
                          icon: Icons.payments_outlined,
                          helper:
                              'Used by the client app MoMo dialer. Leave empty to use the default 775276.',
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Delivery Fee Settings',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: _AdminUi.dark,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: deliveryBaseFee,
                              keyboardType: TextInputType.number,
                              decoration: _fieldDecoration(
                                label: 'Base Fee (Rwf)',
                                icon: Icons.money,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: deliveryThreshold,
                              keyboardType: TextInputType.number,
                              decoration: _fieldDecoration(
                                label: 'Threshold (km)',
                                icon: Icons.route,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: deliveryExtraKmFee,
                        keyboardType: TextInputType.number,
                        decoration: _fieldDecoration(
                          label: 'Extra Per KM Fee (Rwf)',
                          icon: Icons.add_road,
                          helper:
                              'Charged for each KM beyond the threshold distance.',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: deliveryOrderThreshold,
                              keyboardType: TextInputType.number,
                              decoration: _fieldDecoration(
                                label: 'Order Threshold (Rwf)',
                                icon: Icons.price_change_outlined,
                                helper:
                                    'If order total is above this amount, extra delivery logic starts.',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: deliveryExtraOrderPercent,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: _fieldDecoration(
                                label: 'Extra Percentage (%)',
                                icon: Icons.percent_outlined,
                                helper:
                                    'Extra delivery charge percent applied only to the amount above the threshold.',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Business GPS for delivery calculations',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: _AdminUi.dark,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Client delivery distance is measured from this saved point to the client live location.',
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          SizedBox(
                            width: 240,
                            child: TextFormField(
                              controller: latitude,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    signed: true,
                                    decimal: true,
                                  ),
                              decoration: _fieldDecoration(
                                label: 'Latitude',
                                icon: Icons.my_location_outlined,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 240,
                            child: TextFormField(
                              controller: longitude,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    signed: true,
                                    decimal: true,
                                  ),
                              decoration: _fieldDecoration(
                                label: 'Longitude',
                                icon: Icons.explore_outlined,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton.tonalIcon(
                          onPressed: isLocating ? null : useCurrentGps,
                          icon: Icon(
                            isLocating
                                ? Icons.location_searching_outlined
                                : Icons.gps_fixed_outlined,
                          ),
                          label: Text(
                            isLocating ? 'Reading GPS...' : 'Use Current GPS',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: isSaving ? null : saveBusinessProfile,
                child: Text(isSaving ? 'Saving...' : 'Save'),
              ),
            ],
          );
        },
      ),
    );

    businessName.dispose();
    phone.dispose();
    email.dispose();
    location.dispose();
    addressLine.dispose();
    latitude.dispose();
    longitude.dispose();
  }

  Future<void> _toggleShopStatus(Shop shop) async {
    try {
      await Supabase.instance.client
          .from(AppConstants.shopsTable)
          .update({'is_active': !shop.isActive})
          .eq('id', shop.id);
      _scheduleAdminRefresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update shop status: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  Future<void> _editShop([Shop? existing]) async {
    final name = TextEditingController(text: existing?.name ?? '');
    final description = TextEditingController(
      text: existing?.description ?? '',
    );
    final phone = TextEditingController(text: existing?.phone ?? '');
    final location = TextEditingController(text: existing?.location ?? '');
    final addressLine = TextEditingController(
      text: existing?.addressLine ?? '',
    );
    final latitude = TextEditingController(
      text: existing?.latitude?.toString() ?? '',
    );
    final longitude = TextEditingController(
      text: existing?.longitude?.toString() ?? '',
    );
    final momoCode = TextEditingController(
      text: existing?.momoPayMerchantCode ?? '',
    );
    final bankAccount = TextEditingController(
      text: existing?.bankAccount ?? '',
    );
    final deliveryBaseFee = TextEditingController(
      text: (existing?.deliveryBaseFee ?? 500).toStringAsFixed(0),
    );
    final deliveryThreshold = TextEditingController(
      text: (existing?.deliveryDistanceThresholdKm ?? 4).toString(),
    );
    final deliveryExtraKmFee = TextEditingController(
      text: (existing?.deliveryExtraKmFee ?? 200).toStringAsFixed(0),
    );
    final deliveryOrderThreshold = TextEditingController(
      text: (existing?.deliveryOrderThreshold ?? 20000).toStringAsFixed(0),
    );
    final deliveryExtraOrderPercent = TextEditingController(
      text: ((existing?.deliveryExtraOrderPercent ?? 0.20) * 100)
          .toStringAsFixed(0),
    );
    final commission = TextEditingController(
      text: existing?.commissionPercent.toStringAsFixed(0) ?? '0',
    );
    var isActive = existing?.isActive ?? true;
    var isSaving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'New Partner Shop' : 'Edit Shop'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    decoration: _fieldDecoration(
                      label: 'Shop name',
                      icon: Icons.storefront_outlined,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: description,
                    minLines: 2,
                    maxLines: 3,
                    decoration: _fieldDecoration(
                      label: 'Description',
                      icon: Icons.notes_outlined,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: phone,
                    decoration: _fieldDecoration(
                      label: 'Phone',
                      icon: Icons.phone_outlined,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: location,
                    decoration: _fieldDecoration(
                      label: 'Location',
                      icon: Icons.location_on_outlined,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: addressLine,
                    decoration: _fieldDecoration(
                      label: 'Address line',
                      icon: Icons.pin_drop_outlined,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: latitude,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          decoration: _fieldDecoration(
                            label: 'Latitude',
                            icon: Icons.my_location_outlined,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: longitude,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          decoration: _fieldDecoration(
                            label: 'Longitude',
                            icon: Icons.explore_outlined,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: momoCode,
                    decoration: _fieldDecoration(
                      label: 'MoMo merchant code',
                      icon: Icons.payments_outlined,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: bankAccount,
                    decoration: _fieldDecoration(
                      label: 'Bank account',
                      icon: Icons.account_balance_outlined,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: commission,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: _fieldDecoration(
                      label: 'Platform commission %',
                      icon: Icons.percent_outlined,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: deliveryBaseFee,
                          keyboardType: TextInputType.number,
                          decoration: _fieldDecoration(
                            label: 'Base delivery fee',
                            icon: Icons.local_shipping_outlined,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: deliveryThreshold,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: _fieldDecoration(
                            label: 'Distance threshold',
                            icon: Icons.route_outlined,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: deliveryExtraKmFee,
                          keyboardType: TextInputType.number,
                          decoration: _fieldDecoration(
                            label: 'Extra fee per km',
                            icon: Icons.add_road_outlined,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: deliveryOrderThreshold,
                          keyboardType: TextInputType.number,
                          decoration: _fieldDecoration(
                            label: 'Order threshold',
                            icon: Icons.receipt_long_outlined,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: deliveryExtraOrderPercent,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: _fieldDecoration(
                      label: 'Extra percent above threshold',
                      icon: Icons.percent_outlined,
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: isActive,
                    onChanged: isSaving
                        ? null
                        : (value) => setDialogState(() => isActive = value),
                    title: const Text('Active for customers'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      final shopName = name.text.trim();
                      if (shopName.isEmpty) {
                        _showAdminSnack('Shop name is required.');
                        return;
                      }
                      final commissionValue =
                          double.tryParse(commission.text.trim()) ?? 0;
                      final latitudeValue = double.tryParse(
                        latitude.text.trim(),
                      );
                      final longitudeValue = double.tryParse(
                        longitude.text.trim(),
                      );
                      if (commissionValue < 0 || commissionValue > 100) {
                        _showAdminSnack(
                          'Commission must be between 0 and 100.',
                        );
                        return;
                      }
                      if ((latitude.text.trim().isEmpty &&
                              longitude.text.trim().isNotEmpty) ||
                          (latitude.text.trim().isNotEmpty &&
                              longitude.text.trim().isEmpty)) {
                        _showAdminSnack(
                          'Enter both latitude and longitude, or leave both empty.',
                        );
                        return;
                      }

                      setDialogState(() => isSaving = true);
                      final payload = {
                        'name': shopName,
                        'description': description.text.trim(),
                        'phone': phone.text.trim(),
                        'location': location.text.trim(),
                        'address_line': addressLine.text.trim(),
                        'latitude': latitudeValue,
                        'longitude': longitudeValue,
                        'momo_pay_merchant_code': momoCode.text.trim(),
                        'bank_account': bankAccount.text.trim(),
                        'delivery_base_fee':
                            double.tryParse(deliveryBaseFee.text.trim()) ?? 500,
                        'delivery_distance_threshold':
                            double.tryParse(deliveryThreshold.text.trim()) ?? 4,
                        'delivery_extra_km_fee':
                            double.tryParse(deliveryExtraKmFee.text.trim()) ??
                            200,
                        'delivery_order_threshold':
                            double.tryParse(
                              deliveryOrderThreshold.text.trim(),
                            ) ??
                            20000,
                        'delivery_extra_order_percent':
                            (double.tryParse(
                                  deliveryExtraOrderPercent.text.trim(),
                                ) ??
                                20) /
                            100,
                        'commission_percent': commissionValue,
                        'is_active': isActive,
                      };
                      try {
                        if (existing == null) {
                          await Supabase.instance.client
                              .from(AppConstants.shopsTable)
                              .insert(payload);
                        } else {
                          await Supabase.instance.client
                              .from(AppConstants.shopsTable)
                              .update(payload)
                              .eq('id', existing.id);
                        }
                        if (!mounted || !dialogContext.mounted) return;
                        Navigator.pop(dialogContext);
                        await _loadAdminData(showLoading: false);
                        _showAdminSnack(
                          existing == null
                              ? 'Partner shop created.'
                              : 'Shop updated.',
                        );
                      } catch (error) {
                        setDialogState(() => isSaving = false);
                        _showAdminSnack(
                          _friendlyAdminError(
                            error,
                            fallbackMessage: 'Unable to save shop.',
                          ),
                        );
                      }
                    },
              child: Text(isSaving ? 'Saving...' : 'Save'),
            ),
          ],
        ),
      ),
    );

    name.dispose();
    description.dispose();
    phone.dispose();
    location.dispose();
    addressLine.dispose();
    latitude.dispose();
    longitude.dispose();
    momoCode.dispose();
    bankAccount.dispose();
    deliveryBaseFee.dispose();
    deliveryThreshold.dispose();
    deliveryExtraKmFee.dispose();
    deliveryOrderThreshold.dispose();
    deliveryExtraOrderPercent.dispose();
    commission.dispose();
  }

  Widget _imageFallbackBox({double size = 132}) {
    return Container(
      width: size,
      height: size,
      color: const Color(0xFFE8F3E9),
      alignment: Alignment.center,
      child: const Icon(
        Icons.image_outlined,
        color: _AdminUi.primary,
        size: 42,
      ),
    );
  }

  Future<void> _toggleProductAvailability(_AdminProduct product) async {
    try {
      await Supabase.instance.client
          .from(_productsTable)
          .update({'is_available': !product.isAvailable})
          .eq('id', product.id);
      await _loadAdminData(showLoading: false);
    } catch (error) {
      _showAdminSnack(
        _friendlyAdminError(
          error,
          fallbackMessage: 'Unable to update product status.',
        ),
      );
    }
  }

  Future<void> _deleteProduct(_AdminProduct product) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Product'),
        content: Text('Delete "${product.name}" from inventory?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await Supabase.instance.client
          .from(_productsTable)
          .delete()
          .eq('id', product.id);
      await _deleteStoredImageByUrl(product.imageUrl);
      await _loadAdminData(showLoading: false);
      _showAdminSnack('Product deleted.');
    } catch (error) {
      _showAdminSnack(
        _friendlyAdminError(
          error,
          fallbackMessage: 'Unable to delete the product.',
        ),
      );
    }
  }

  Future<void> _updateOrderStatus(_AdminOrder order, String status) async {
    try {
      await Supabase.instance.client
          .from(_ordersTable)
          .update({'status': status})
          .eq('id', order.id);

      // Notify the client about the status update
      unawaited(
        PushNotificationService.instance.notifyClientEvent(
          eventType: 'order_status',
          userId: order.clientId,
          orderId: order.id,
          orderStatus: status,
        ),
      );

      await _loadAdminData(showLoading: false);
      _showAdminSnack('Order #${order.id} marked as $status.');
    } catch (error) {
      _showAdminSnack(
        _friendlyAdminError(
          error,
          fallbackMessage: 'Unable to update order status.',
        ),
      );
    }
  }

  List<_AdminOrder> _matchingOrders({
    required String phone,
    String? productId,
    bool unpaidOnly = false,
  }) {
    return orders.where((order) {
      final phoneMatch = order.phone == phone;
      final productMatch =
          productId == null ||
          order.normalizedItems.any((item) => item.productId == productId) ||
          order.productId == productId;
      final unpaidMatch =
          !unpaidOnly ||
          (order.balance > 0 &&
              order.status != 'Completed' &&
              order.status != 'Cancelled');
      return phoneMatch && productMatch && unpaidMatch;
    }).toList()..sort(
      (a, b) =>
          (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)),
    );
  }

  Future<void> _editCategory([_AdminCategory? existing]) async {
    final name = TextEditingController(text: existing?.name ?? '');
    final profitPercentage = TextEditingController(
      text: existing?.profitPercentage.toStringAsFixed(2) ?? '0',
    );
    bool isSaving = false;
    String? currentImageUrl = (existing?.imageUrl.isNotEmpty ?? false)
        ? existing!.imageUrl
        : null;
    _PickedImageData? pickedImage;
    final formKey = GlobalKey<FormState>();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          existing == null
                              ? 'Create Category'
                              : 'Edit Category',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Upload a cover image and set the profit margin used to calculate product selling prices.',
                          style: TextStyle(color: Color(0xFF617066)),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(18),
                              child: pickedImage != null
                                  ? Image.memory(
                                      pickedImage!.bytes,
                                      width: 132,
                                      height: 132,
                                      fit: BoxFit.cover,
                                    )
                                  : currentImageUrl != null
                                  ? Image.network(
                                      currentImageUrl!,
                                      width: 132,
                                      height: 132,
                                      fit: BoxFit.cover,
                                      cacheWidth: 300,
                                      errorBuilder: (_, _, _) =>
                                          _imageFallbackBox(),
                                    )
                                  : _imageFallbackBox(),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Category Image',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Choose a square image for the category card.',
                                    style: TextStyle(color: Color(0xFF617066)),
                                  ),
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 10,
                                    runSpacing: 10,
                                    children: [
                                      FilledButton.icon(
                                        onPressed: isSaving
                                            ? null
                                            : () async {
                                                final selected =
                                                    await _pickImageData();
                                                if (selected == null) return;
                                                setDialogState(() {
                                                  pickedImage = selected;
                                                });
                                              },
                                        icon: const Icon(Icons.upload_file),
                                        label: const Text('Choose Image'),
                                      ),
                                      if (currentImageUrl != null ||
                                          pickedImage != null)
                                        OutlinedButton.icon(
                                          onPressed: isSaving
                                              ? null
                                              : () {
                                                  setDialogState(() {
                                                    pickedImage = null;
                                                    currentImageUrl = null;
                                                  });
                                                },
                                          icon: const Icon(
                                            Icons.delete_outline,
                                          ),
                                          label: const Text('Remove'),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        TextFormField(
                          controller: name,
                          decoration: _fieldDecoration(
                            label: 'Category name',
                            icon: Icons.category_outlined,
                          ),
                          validator: _required,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: profitPercentage,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: _fieldDecoration(
                            label: 'Profit percentage',
                            icon: Icons.percent_outlined,
                            helper: 'Used to calculate product selling prices.',
                          ),
                          validator: (value) {
                            final parsed = double.tryParse(value ?? '');
                            if (parsed == null || parsed < 0) {
                              return 'Enter a valid profit percentage';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 18),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: isSaving
                                  ? null
                                  : () => Navigator.pop(dialogContext),
                              child: const Text('Cancel'),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: isSaving
                                  ? null
                                  : () async {
                                      if (!(formKey.currentState?.validate() ??
                                          false)) {
                                        return;
                                      }
                                      if (currentImageUrl == null &&
                                          pickedImage == null) {
                                        _showAdminSnack(
                                          'Choose a category image before saving.',
                                        );
                                        return;
                                      }
                                      final previousProfit =
                                          existing?.profitPercentage ?? 0;
                                      final parsedProfit = double.parse(
                                        profitPercentage.text.trim(),
                                      );
                                      setDialogState(() => isSaving = true);
                                      String? uploadedImageUrl;
                                      try {
                                        var imageUrl = currentImageUrl;
                                        if (pickedImage != null) {
                                          uploadedImageUrl =
                                              await _uploadProductImage(
                                                pickedImage!,
                                              );
                                          imageUrl = uploadedImageUrl;
                                        }
                                        final payload = {
                                          'id':
                                              existing?.id ?? const Uuid().v4(),
                                          'name': name.text.trim(),
                                          'image_url': imageUrl ?? '',
                                          'profit_percentage': parsedProfit,
                                        };
                                        if (existing == null) {
                                          await Supabase.instance.client
                                              .from(_categoriesTable)
                                              .insert(payload);
                                        } else {
                                          await Supabase.instance.client
                                              .from(_categoriesTable)
                                              .update(payload)
                                              .eq('id', existing.id);
                                          if (pickedImage != null &&
                                              currentImageUrl != null &&
                                              currentImageUrl != imageUrl) {
                                            await _deleteStoredImageByUrl(
                                              currentImageUrl!,
                                            );
                                          }
                                          if (parsedProfit != previousProfit) {
                                            try {
                                              await _syncCategoryProductPrices(
                                                categoryId: existing.id,
                                                sourceProfitPercentage:
                                                    previousProfit,
                                                targetProfitPercentage:
                                                    parsedProfit,
                                              );
                                            } catch (syncError) {
                                              _showAdminSnack(
                                                _friendlyAdminError(
                                                  syncError,
                                                  fallbackMessage:
                                                      'Category saved, but some product prices could not be synced.',
                                                ),
                                                isError: true,
                                              );
                                            }
                                          }
                                        }
                                        if (!mounted ||
                                            !dialogContext.mounted) {
                                          return;
                                        }
                                        Navigator.pop(dialogContext);
                                        await _loadAdminData(
                                          showLoading: false,
                                        );
                                        _showAdminSnack(
                                          existing == null
                                              ? 'Category added.'
                                              : 'Category updated.',
                                        );
                                      } catch (error) {
                                        if (uploadedImageUrl != null) {
                                          await _deleteStoredImageByUrl(
                                            uploadedImageUrl,
                                          );
                                        }
                                        if (!mounted) return;
                                        setDialogState(() => isSaving = false);
                                        _showAdminSnack(
                                          _friendlyAdminError(
                                            error,
                                            fallbackMessage:
                                                'Unable to save the category.',
                                          ),
                                        );
                                      }
                                    },
                              child: Text(
                                isSaving
                                    ? 'Saving...'
                                    : existing == null
                                    ? 'Create'
                                    : 'Save',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );

    name.dispose();
    profitPercentage.dispose();
  }

  Future<void> _deleteCategory(_AdminCategory category) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Category'),
        content: Text(
          'Delete "${category.name}"? Products in this category will become uncategorized.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await Supabase.instance.client
          .from(_categoriesTable)
          .delete()
          .eq('id', category.id);
      await _deleteStoredImageByUrl(category.imageUrl);
      await _loadAdminData(showLoading: false);
      _showAdminSnack('Category deleted.');
    } catch (error) {
      _showAdminSnack(
        _friendlyAdminError(
          error,
          fallbackMessage: 'Unable to delete the category.',
        ),
      );
    }
  }

  Future<void> _adjustStock(_AdminProduct product) async {
    final amount = TextEditingController();
    bool reduceStock = false;
    final formKey = GlobalKey<FormState>();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text('Adjust Stock for ${product.name}'),
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    value: reduceStock,
                    onChanged: (value) =>
                        setDialogState(() => reduceStock = value),
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      reduceStock ? 'Reduce stock' : 'Increase stock',
                    ),
                  ),
                  TextFormField(
                    controller: amount,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: _fieldDecoration(
                      label: 'Quantity to ${reduceStock ? 'remove' : 'add'}',
                      icon: Icons.scale_outlined,
                    ),
                    validator: (value) =>
                        (double.tryParse(value ?? '') ?? 0) > 0
                        ? null
                        : 'Enter a valid quantity',
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  if (!(formKey.currentState?.validate() ?? false)) return;
                  final delta = double.parse(amount.text.trim());
                  final nextQuantity = reduceStock
                      ? product.quantity - delta
                      : product.quantity + delta;
                  if (nextQuantity < 0) {
                    _showAdminSnack('Stock cannot go below zero.');
                    return;
                  }
                  try {
                    await Supabase.instance.client
                        .from(_productsTable)
                        .update({
                          'quantity': nextQuantity,
                          'is_available': nextQuantity > 0
                              ? product.isAvailable || !reduceStock
                              : false,
                        })
                        .eq('id', product.id);
                    if (!mounted || !dialogContext.mounted) return;
                    Navigator.pop(dialogContext);
                    await _loadAdminData(showLoading: false);
                    _showAdminSnack('Stock updated.');
                  } catch (error) {
                    _showAdminSnack(
                      _friendlyAdminError(
                        error,
                        fallbackMessage: 'Unable to adjust stock.',
                      ),
                    );
                  }
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );

    amount.dispose();
  }

  Future<void> _editProduct([_AdminProduct? existing]) async {
    final formKey = GlobalKey<FormState>();
    final name = TextEditingController(text: existing?.name ?? '');
    final description = TextEditingController(
      text: existing?.description ?? '',
    );
    final purchasePrice = TextEditingController(
      text: existing == null
          ? ''
          : _initialPurchasePriceForEdit(existing).toStringAsFixed(0),
    );
    final discountPrice = TextEditingController(
      text: existing?.discountPrice?.toStringAsFixed(0) ?? '',
    );
    final productUnit = existing?.unit ?? 'kg';
    final discountThreshold = TextEditingController(
      text: existing?.discountThresholdKg == null
          ? ''
          : _formatQuantity(existing!.discountThresholdKg!, productUnit),
    );
    final quantity = TextEditingController(
      text: existing == null
          ? ''
          : _formatQuantity(existing.quantity, productUnit),
    );
    final initialCategoryId =
        existing?.categoryId ??
        (categories.isNotEmpty ? categories.first.id : null);
    final initialShopId =
        existing?.shopId ??
        _selectedShopId ??
        (shops.isNotEmpty ? shops.first.id : null);
    final initialPurchasePrice = existing == null
        ? null
        : _initialPurchasePriceForEdit(existing);
    final initialSuggestedSelling = initialPurchasePrice == null
        ? null
        : _sellingPriceForCategoryPurchase(
            initialPurchasePrice,
            initialCategoryId,
          );
    final sellingPrice = TextEditingController(
      text:
          existing?.displayPrice.toStringAsFixed(0) ??
          initialSuggestedSelling?.toStringAsFixed(0) ??
          '',
    );

    String unit = productUnit;
    String? shopId = initialShopId;
    String? categoryId = initialCategoryId;
    bool isAvailable = existing?.isAvailable ?? true;
    bool isSaving = false;
    String? currentImageUrl = existing?.imageUrl;
    _PickedImageData? pickedImage;
    bool sellingPriceEditedManually =
        existing != null &&
        initialSuggestedSelling != null &&
        (existing.displayPrice - initialSuggestedSelling).abs() > 0.01;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          double? previewSellingPrice() {
            final parsedPurchase = double.tryParse(purchasePrice.text.trim());
            if (parsedPurchase == null || parsedPurchase <= 0) {
              return null;
            }
            return _sellingPriceForCategoryPurchase(parsedPurchase, categoryId);
          }

          void syncSellingPriceIfNeeded() {
            if (sellingPriceEditedManually) return;
            final suggested = previewSellingPrice();
            sellingPrice.text = suggested == null
                ? ''
                : suggested.toStringAsFixed(0);
          }

          return Dialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 24,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          existing == null ? 'Create Product' : 'Edit Product',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Upload a real product image, choose a category, set purchase price, and use the category profit as a suggested selling price you can still change.',
                          style: TextStyle(color: Color(0xFF617066)),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: pickedImage != null
                                  ? Image.memory(
                                      pickedImage!.bytes,
                                      width: 132,
                                      height: 132,
                                      fit: BoxFit.cover,
                                    )
                                  : currentImageUrl != null
                                  ? Image.network(
                                      currentImageUrl!,
                                      width: 132,
                                      height: 132,
                                      fit: BoxFit.cover,
                                      cacheWidth: 300,
                                      errorBuilder: (_, _, _) =>
                                          _imageFallbackBox(),
                                    )
                                  : _imageFallbackBox(),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Product Image',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'The file is uploaded to Supabase Storage automatically.',
                                    style: TextStyle(color: Color(0xFF617066)),
                                  ),
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 10,
                                    runSpacing: 10,
                                    children: [
                                      FilledButton.icon(
                                        onPressed: isSaving
                                            ? null
                                            : () async {
                                                final selected =
                                                    await _pickImageData();
                                                if (selected == null) return;
                                                setDialogState(() {
                                                  pickedImage = selected;
                                                });
                                              },
                                        icon: const Icon(Icons.upload_file),
                                        label: const Text('Choose Image'),
                                      ),
                                      if (currentImageUrl != null ||
                                          pickedImage != null)
                                        OutlinedButton.icon(
                                          onPressed: isSaving
                                              ? null
                                              : () {
                                                  setDialogState(() {
                                                    pickedImage = null;
                                                    currentImageUrl = null;
                                                  });
                                                },
                                          icon: const Icon(
                                            Icons.delete_outline,
                                          ),
                                          label: const Text('Remove'),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        TextFormField(
                          controller: name,
                          decoration: _fieldDecoration(
                            label: 'Product name',
                            icon: Icons.shopping_bag_outlined,
                          ),
                          validator: _required,
                        ),
                        const SizedBox(height: 12),
                        if (shops.isNotEmpty) ...[
                          DropdownButtonFormField<String>(
                            initialValue: shopId,
                            items: shops
                                .map(
                                  (shop) => DropdownMenuItem<String>(
                                    value: shop.id,
                                    child: Text(shop.name),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) =>
                                setDialogState(() => shopId = value),
                            decoration: _fieldDecoration(
                              label: 'Shop',
                              icon: Icons.storefront_outlined,
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        DropdownButtonFormField<String>(
                          initialValue: categoryId,
                          items: categories
                              .map(
                                (category) => DropdownMenuItem<String>(
                                  value: category.id,
                                  child: Text(category.name),
                                ),
                              )
                              .toList(),
                          onChanged: (value) => setDialogState(() {
                            categoryId = value;
                            syncSellingPriceIfNeeded();
                          }),
                          decoration: _fieldDecoration(
                            label: 'Category',
                            icon: Icons.category_outlined,
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: unit,
                          items: const [
                            DropdownMenuItem(
                              value: 'kg',
                              child: Text('Kilogram (kg)'),
                            ),
                            DropdownMenuItem(
                              value: 'pc',
                              child: Text('Piece (pc)'),
                            ),
                          ],
                          onChanged: (value) => setDialogState(() {
                            unit = value ?? 'kg';
                          }),
                          decoration: _fieldDecoration(
                            label: 'Measurement unit',
                            icon: Icons.straighten_outlined,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: description,
                          minLines: 3,
                          maxLines: 4,
                          decoration: _fieldDecoration(
                            label: 'Description',
                            icon: Icons.notes_outlined,
                          ),
                          validator: _required,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: purchasePrice,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                onChanged: (_) => setDialogState(() {
                                  syncSellingPriceIfNeeded();
                                }),
                                decoration: _fieldDecoration(
                                  label: 'Purchase price',
                                  icon: Icons.payments_outlined,
                                ),
                                validator: (value) =>
                                    (double.tryParse(value ?? '') ?? -1) > 0
                                    ? null
                                    : 'Enter a valid purchase price',
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  TextFormField(
                                    controller: sellingPrice,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    onChanged: (_) => setDialogState(() {
                                      sellingPriceEditedManually = true;
                                    }),
                                    decoration: _fieldDecoration(
                                      label: 'Your selling price',
                                      icon: Icons.sell_outlined,
                                      helper:
                                          'You can keep the suggestion or enter your own selling price.',
                                    ),
                                    validator: (value) =>
                                        (double.tryParse(value ?? '') ?? -1) > 0
                                        ? null
                                        : 'Enter a valid selling price',
                                  ),
                                  const SizedBox(height: 10),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF5FBF2),
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(
                                        color: const Color(0xFFDCEBD6),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Suggested price',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.green.shade900,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          previewSellingPrice() == null
                                              ? '--'
                                              : _moneyLabel(
                                                  previewSellingPrice()!,
                                                ),
                                          style: const TextStyle(
                                            fontSize: 22,
                                            fontWeight: FontWeight.w900,
                                            color: _AdminUi.primary,
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        Text(
                                          'Your selling price',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.grey.shade700,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          (double.tryParse(
                                                        sellingPrice.text
                                                            .trim(),
                                                      ) ??
                                                      0) >
                                                  0
                                              ? _moneyLabel(
                                                  double.parse(
                                                    sellingPrice.text.trim(),
                                                  ),
                                                )
                                              : '--',
                                          style: const TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFF1E1E1E),
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          sellingPriceEditedManually
                                              ? 'Manual override is active. Category margin is only a guide.'
                                              : 'Category margin is guiding the selling price right now.',
                                          style: TextStyle(
                                            color: Colors.green.shade900,
                                            fontSize: 12,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Align(
                                          alignment: Alignment.centerLeft,
                                          child: TextButton(
                                            onPressed: () => setDialogState(() {
                                              final suggested =
                                                  previewSellingPrice();
                                              if (suggested != null) {
                                                sellingPrice.text = suggested
                                                    .toStringAsFixed(0);
                                              }
                                              sellingPriceEditedManually =
                                                  false;
                                            }),
                                            child: const Text(
                                              'Use suggested price',
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: quantity,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: _fieldDecoration(
                                  label:
                                      'Quantity (${unit.toLowerCase() == 'pc' ? 'Pc' : 'Kg'})',
                                  icon: Icons.inventory_2_outlined,
                                ),
                                validator: (value) {
                                  final parsed =
                                      double.tryParse(value ?? '') ?? -1;
                                  if (parsed < 0) {
                                    return 'Enter a valid quantity';
                                  }
                                  if (unit.toLowerCase() == 'pc' &&
                                      parsed != parsed.roundToDouble()) {
                                    return 'Use a whole number of pieces';
                                  }
                                  return null;
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: discountPrice,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: _fieldDecoration(
                                  label: 'Discount price',
                                  icon: Icons.local_offer_outlined,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: discountThreshold,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: _fieldDecoration(
                                  label:
                                      'Discount threshold (${unit.toLowerCase() == 'pc' ? 'Pc' : 'Kg'})',
                                  icon: Icons.scale_outlined,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SwitchListTile(
                          value: isAvailable,
                          onChanged: isSaving
                              ? null
                              : (value) => setDialogState(() {
                                  isAvailable = value;
                                }),
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Available for sale'),
                          subtitle: const Text(
                            'Disabled products stay in admin but disappear from the customer catalogue.',
                          ),
                          activeThumbColor: _AdminUi.primary,
                        ),
                        const SizedBox(height: 18),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: isSaving
                                  ? null
                                  : () => Navigator.pop(dialogContext),
                              child: const Text('Cancel'),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: isSaving
                                  ? null
                                  : () async {
                                      if (!(formKey.currentState?.validate() ??
                                          false)) {
                                        return;
                                      }
                                      final parsedSellingPrice = double.parse(
                                        sellingPrice.text.trim(),
                                      );
                                      final parsedDiscount = double.tryParse(
                                        discountPrice.text.trim(),
                                      );
                                      final parsedThreshold = double.tryParse(
                                        discountThreshold.text.trim(),
                                      );
                                      if ((parsedDiscount == null) !=
                                          (parsedThreshold == null)) {
                                        _showAdminSnack(
                                          'Provide both discount price and threshold, or leave both empty.',
                                        );
                                        return;
                                      }
                                      if (parsedDiscount != null &&
                                          parsedDiscount >=
                                              parsedSellingPrice) {
                                        _showAdminSnack(
                                          'Discount price must be lower than the selling price.',
                                        );
                                        return;
                                      }
                                      if (currentImageUrl == null &&
                                          pickedImage == null) {
                                        _showAdminSnack(
                                          'Choose a product image before saving.',
                                        );
                                        return;
                                      }
                                      final parsedPurchase = double.parse(
                                        purchasePrice.text.trim(),
                                      );
                                      setDialogState(() => isSaving = true);
                                      String? uploadedImageUrl;
                                      try {
                                        var imageUrl = currentImageUrl;
                                        if (pickedImage != null) {
                                          uploadedImageUrl =
                                              await _uploadProductImage(
                                                pickedImage!,
                                              );
                                          imageUrl = uploadedImageUrl;
                                        }
                                        final product = _AdminProduct(
                                          id: existing?.id ?? const Uuid().v4(),
                                          shopId: shopId,
                                          name: name.text.trim(),
                                          description: description.text.trim(),
                                          imageUrl: imageUrl!,
                                          unit: unit,
                                          categoryId: categoryId,
                                          purchasePrice: parsedPurchase,
                                          sellingPrice: parsedSellingPrice,
                                          price: parsedSellingPrice,
                                          discountPrice: parsedDiscount,
                                          discountThresholdKg: parsedThreshold,
                                          quantity: double.parse(
                                            quantity.text.trim(),
                                          ),
                                          isAvailable: isAvailable,
                                          createdAt: existing?.createdAt,
                                        );
                                        if (existing == null) {
                                          await Supabase.instance.client
                                              .from(_productsTable)
                                              .insert(product.toJson());
                                        } else {
                                          await Supabase.instance.client
                                              .from(_productsTable)
                                              .update(product.toJson())
                                              .eq('id', existing.id);
                                          if (pickedImage != null &&
                                              currentImageUrl != null &&
                                              currentImageUrl != imageUrl) {
                                            await _deleteStoredImageByUrl(
                                              currentImageUrl!,
                                            );
                                          }
                                        }
                                        if (!mounted ||
                                            !dialogContext.mounted) {
                                          return;
                                        }
                                        Navigator.pop(dialogContext);
                                        await _loadAdminData(
                                          showLoading: false,
                                        );
                                        _showAdminSnack(
                                          existing == null
                                              ? 'Product created.'
                                              : 'Product updated.',
                                        );
                                      } catch (error) {
                                        if (uploadedImageUrl != null) {
                                          await _deleteStoredImageByUrl(
                                            uploadedImageUrl,
                                          );
                                        }
                                        if (!mounted) return;
                                        setDialogState(() => isSaving = false);
                                        _showAdminSnack(
                                          _friendlyAdminError(
                                            error,
                                            fallbackMessage:
                                                'Unable to save the product.',
                                          ),
                                        );
                                      }
                                    },
                              child: Text(
                                isSaving
                                    ? 'Saving...'
                                    : existing == null
                                    ? 'Create Product'
                                    : 'Save Changes',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );

    name.dispose();
    description.dispose();
    purchasePrice.dispose();
    sellingPrice.dispose();
    discountPrice.dispose();
    discountThreshold.dispose();
    quantity.dispose();
  }

  Future<void> _editProductPricing(_AdminProduct product) async {
    final formKey = GlobalKey<FormState>();
    final categoryProfit = _profitPercentageForCategoryId(product.categoryId);
    final currentSelling = product.displayPrice;
    final purchasePrice = TextEditingController(
      text: _initialPurchasePriceForEdit(product).toStringAsFixed(0),
    );
    final suggestedSelling = _sellingPriceForCategoryPurchase(
      _initialPurchasePriceForEdit(product),
      product.categoryId,
    );
    final sellingPrice = TextEditingController(
      text: currentSelling.toStringAsFixed(0),
    );
    bool isSaving = false;
    bool sellingPriceEditedManually =
        (currentSelling - suggestedSelling).abs() > 0.01;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          double? previewSellingPrice() {
            final parsedPurchase = double.tryParse(purchasePrice.text.trim());
            if (parsedPurchase == null || parsedPurchase <= 0) {
              return null;
            }
            return _sellingPriceForCategoryPurchase(
              parsedPurchase,
              product.categoryId,
            );
          }

          void syncSellingPriceIfNeeded() {
            if (sellingPriceEditedManually) return;
            final suggested = previewSellingPrice();
            sellingPrice.text = suggested == null
                ? ''
                : suggested.toStringAsFixed(0);
          }

          return AlertDialog(
            title: Text('Update price for ${product.name}'),
            content: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Before price: ${_moneyLabel(currentSelling)}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Category profit margin: ${_formatPercent(categoryProfit)}%',
                      style: const TextStyle(color: Color(0xFF617066)),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: purchasePrice,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: (_) => setDialogState(() {
                        syncSellingPriceIfNeeded();
                      }),
                      decoration: _fieldDecoration(
                        label: 'Purchase price',
                        icon: Icons.payments_outlined,
                      ),
                      validator: (value) =>
                          (double.tryParse(value ?? '') ?? -1) > 0
                          ? null
                          : 'Enter a valid purchase price',
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: sellingPrice,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: (_) => setDialogState(() {
                        sellingPriceEditedManually = true;
                      }),
                      decoration: _fieldDecoration(
                        label: 'Your selling price',
                        icon: Icons.sell_outlined,
                        helper:
                            'You can keep the suggestion or enter your own selling price.',
                      ),
                      validator: (value) =>
                          (double.tryParse(value ?? '') ?? -1) > 0
                          ? null
                          : 'Enter a valid selling price',
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5FBF2),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFDCEBD6)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Suggested price',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.green.shade900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            previewSellingPrice() == null
                                ? '--'
                                : _moneyLabel(previewSellingPrice()!),
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: _AdminUi.primary,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Your selling price',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            (double.tryParse(sellingPrice.text.trim()) ?? 0) > 0
                                ? _moneyLabel(
                                    double.parse(sellingPrice.text.trim()),
                                  )
                                : '--',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1E1E1E),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            sellingPriceEditedManually
                                ? 'Manual override is active. Category margin is only a guide.'
                                : 'Category margin is guiding the selling price right now.',
                            style: TextStyle(
                              color: Colors.green.shade900,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () => setDialogState(() {
                              final suggested = previewSellingPrice();
                              if (suggested != null) {
                                sellingPrice.text = suggested.toStringAsFixed(
                                  0,
                                );
                              }
                              sellingPriceEditedManually = false;
                            }),
                            child: const Text('Use suggested price'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: isSaving
                    ? null
                    : () async {
                        if (!(formKey.currentState?.validate() ?? false)) {
                          return;
                        }
                        final parsedPurchase = double.parse(
                          purchasePrice.text.trim(),
                        );
                        final parsedSellingPrice = double.parse(
                          sellingPrice.text.trim(),
                        );
                        if (product.hasDiscount &&
                            product.discountPrice! >= parsedSellingPrice) {
                          _showAdminSnack(
                            'Discount price must be lower than the selling price.',
                          );
                          return;
                        }
                        setDialogState(() => isSaving = true);
                        try {
                          await Supabase.instance.client
                              .from(_productsTable)
                              .update({
                                'purchase_price': parsedPurchase,
                                'selling_price': parsedSellingPrice,
                                'price': parsedSellingPrice,
                              })
                              .eq('id', product.id);
                          if (!mounted || !dialogContext.mounted) {
                            return;
                          }
                          Navigator.pop(dialogContext);
                          await _loadAdminData(showLoading: false);
                          _showAdminSnack('Price updated.');
                        } catch (error) {
                          if (!mounted) return;
                          setDialogState(() => isSaving = false);
                          _showAdminSnack(
                            _friendlyAdminError(
                              error,
                              fallbackMessage: 'Unable to update the price.',
                            ),
                          );
                        }
                      },
                child: Text(isSaving ? 'Saving...' : 'Update'),
              ),
            ],
          );
        },
      ),
    );

    purchasePrice.dispose();
    sellingPrice.dispose();
  }

  Future<void> _recordPaymentForOrder(_AdminOrder order) async {
    final amount = TextEditingController();
    final formKey = GlobalKey<FormState>();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Record Payment for Order #${order.id}'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${order.clientName} - ${order.displayProductName}'),
              const SizedBox(height: 10),
              Text(
                'Outstanding balance: ${_paymentBalanceLabel(order.balance)}',
              ),
              if ((order.paymentInputMax - order.balance).abs() >= 0.01) ...[
                const SizedBox(height: 8),
                Text(
                  'This saved balance includes cents. Enter up to ${_moneyLabel(order.paymentInputMax)} and the app will record only the exact remaining balance.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: _fieldDecoration(
                  label: 'Payment amount',
                  icon: Icons.payments_outlined,
                ),
                validator: (value) {
                  final parsed = _parsePaymentAmount(value ?? '');
                  if (parsed == null || parsed <= 0) {
                    return 'Enter a valid amount';
                  }
                  if (parsed > order.paymentInputMax) {
                    return 'Amount exceeds current balance';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (!(formKey.currentState?.validate() ?? false)) return;
              try {
                final paymentValue = _parsePaymentAmount(amount.text) ?? 0;
                if (paymentValue <= 0) {
                  throw Exception('Payment amount must be greater than zero.');
                }
                final response = await Supabase.instance.client.functions
                    .invoke(
                      AppConstants.recordOrderPaymentFunction,
                      body: {
                        'orderId': order.id,
                        'paymentAmount': paymentValue,
                        'paymentNote': 'Recorded from admin console',
                      },
                    );
                final responseData = response.data is Map
                    ? Map<String, dynamic>.from(response.data as Map)
                    : const <String, dynamic>{};
                final responseError =
                    responseData['error']?.toString().trim() ?? '';
                if (responseError.isNotEmpty) {
                  throw Exception(responseError);
                }
                final paymentData = responseData['payment'] is Map
                    ? Map<String, dynamic>.from(responseData['payment'] as Map)
                    : const <String, dynamic>{};
                final finalStatus = '${paymentData['status'] ?? order.status}';
                final fullyPaid = finalStatus == 'Completed';
                final notificationWarning =
                    responseData['notificationWarning']?.toString().trim() ??
                    '';

                if (!mounted || !dialogContext.mounted) return;
                Navigator.pop(dialogContext);
                await _loadAdminData(showLoading: false);
                _showAdminSnack(
                  notificationWarning.isNotEmpty
                      ? 'Payment recorded, but: $notificationWarning'
                      : fullyPaid
                      ? 'Payment recorded. Order is now fully paid.'
                      : 'Payment recorded.',
                );
              } catch (error) {
                _showAdminSnack(
                  _friendlyAdminError(
                    error,
                    fallbackMessage: 'Unable to record: $error',
                  ),
                );
              }
            },
            child: const Text('Record'),
          ),
        ],
      ),
    );
    amount.dispose();
  }

  Future<void> _showOrderHistory({
    required String title,
    required String phone,
    String? productId,
    bool allowPayment = false,
  }) async {
    final matchingOrders = _matchingOrders(
      phone: phone,
      productId: productId,
      unpaidOnly: false,
    );

    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760, maxHeight: 640),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
                decoration: const BoxDecoration(
                  color: _AdminUi.primary,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: matchingOrders.isEmpty
                      ? const Center(child: Text('No matching orders found.'))
                      : ListView.separated(
                          itemCount: matchingOrders.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, index) {
                            final order = matchingOrders[index];
                            return _adminOrderCard(
                              order,
                              compact: true,
                              showActions: allowPayment,
                            );
                          },
                        ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                child: SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // â”€â”€ Export orders as CSV (via PDF Share/Download) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<void> _exportOrdersCsvFlow() async {
    final now = DateTime.now();
    final start = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDate: now.subtract(const Duration(days: 30)),
    );
    if (start == null || !mounted) return;
    final end = await showDatePicker(
      context: context,
      firstDate: start,
      lastDate: now,
      initialDate: now,
    );
    if (end == null || !mounted) return;
    await _exportOrdersCsv(start, end);
  }

  Future<void> _exportOrdersCsv(DateTime start, DateTime end) async {
    final filtered = orders.where((order) {
      final createdAt = order.createdAt;
      if (createdAt == null) return false;
      final date = DateTime(createdAt.year, createdAt.month, createdAt.day);
      return !date.isBefore(DateTime(start.year, start.month, start.day)) &&
          !date.isAfter(DateTime(end.year, end.month, end.day));
    }).toList();

    if (filtered.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No orders found in selected date range.')),
        );
      }
      return;
    }

    // Produce a styled PDF table that can be saved/shared (works on web & mobile)
    await _printOrdersReport(start, end, filtered);
  }

  // â”€â”€ Print Orders Report â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<void> _printOrdersReportFlow() async {
    final now = DateTime.now();
    final start = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDate: now.subtract(const Duration(days: 30)),
    );
    if (start == null || !mounted) return;
    final end = await showDatePicker(
      context: context,
      firstDate: start,
      lastDate: now,
      initialDate: now,
    );
    if (end == null || !mounted) return;
    final filtered = orders.where((order) {
      final createdAt = order.createdAt;
      if (createdAt == null) return false;
      final date = DateTime(createdAt.year, createdAt.month, createdAt.day);
      return !date.isBefore(DateTime(start.year, start.month, start.day)) &&
          !date.isAfter(DateTime(end.year, end.month, end.day));
    }).toList();
    if (filtered.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No orders found in selected date range.')),
        );
      }
      return;
    }
    await _printOrdersReport(start, end, filtered);
  }

  Future<void> _printOrdersReport(
    DateTime start,
    DateTime end,
    List<_AdminOrder> filtered,
  ) async {
    final businessName = _businessProfile.businessName.trim().isEmpty
        ? 'PAFLY'
        : _businessProfile.businessName.trim();
    final businessAddress = _businessProfile.addressSummary;
    final businessContact = _businessProfile.contactSummary;

    final doc = pw.Document();
    const headerColor = PdfColor.fromInt(0xFF2E7D32);
    const lightGreen = PdfColor.fromInt(0xFFE8F5E9);

    final grandTotal = filtered.fold<double>(0, (s, o) => s + o.totalPrice);
    final grandDelivery = filtered.fold<double>(0, (s, o) => s + o.deliveryFee);
    final grandDiscount = filtered.fold<double>(0, (s, o) => s + o.discountAmount);
    final grandSubtotal = filtered.fold<double>(
      0,
      (s, o) => s + o.normalizedItems.fold<double>(0, (ss, i) => ss + i.quantityKg * i.pricePerKg),
    );

    String fmtDate(DateTime? dt) {
      if (dt == null) return '';
      return '${dt.day.toString().padLeft(2, "0")}/${dt.month.toString().padLeft(2, "0")}/${dt.year}';
    }
    String fmtTime(DateTime? dt) {
      if (dt == null) return '';
      return '${dt.hour.toString().padLeft(2, "0")}:${dt.minute.toString().padLeft(2, "0")}';
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(businessName, style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: headerColor)),
                    if (businessAddress.isNotEmpty) pw.Text(businessAddress, style: const pw.TextStyle(fontSize: 10)),
                    if (businessContact.isNotEmpty) pw.Text(businessContact, style: const pw.TextStyle(fontSize: 10)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('ORDERS REPORT', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                    pw.Text('${fmtDate(start)} to ${fmtDate(end)}', style: const pw.TextStyle(fontSize: 10)),
                    pw.Text('Generated: ${fmtDate(DateTime.now())} ${fmtTime(DateTime.now())}', style: const pw.TextStyle(fontSize: 9)),
                  ],
                ),
              ],
            ),
            pw.Divider(color: headerColor, thickness: 1.5),
            pw.SizedBox(height: 4),
          ],
        ),
        footer: (ctx) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('$businessName - Confidential', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
            pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
          ],
        ),
        build: (ctx) => [
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(color: lightGreen, borderRadius: pw.BorderRadius.circular(8)),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                pw.Column(children: [
                  pw.Text('Orders', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                  pw.Text(filtered.length.toString(), style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: headerColor)),
                ]),
                pw.Column(children: [
                  pw.Text('Products', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                  pw.Text('${grandSubtotal.toStringAsFixed(0)} Frw', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                ]),
                pw.Column(children: [
                  pw.Text('Delivery', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                  pw.Text('${grandDelivery.toStringAsFixed(0)} Frw', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                ]),
                if (grandDiscount > 0)
                  pw.Column(children: [
                    pw.Text('Discounts', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                    pw.Text('-${grandDiscount.toStringAsFixed(0)} Frw', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.green800)),
                  ]),
                pw.Column(children: [
                  pw.Text('Grand Total', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                  pw.Text('${grandTotal.toStringAsFixed(0)} Frw', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: headerColor)),
                ]),
              ],
            ),
          ),
          pw.SizedBox(height: 14),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.green200, width: 0.5),
            columnWidths: {
              0: const pw.FixedColumnWidth(32),
              1: const pw.FlexColumnWidth(2.2),
              2: const pw.FlexColumnWidth(1.5),
              3: const pw.FlexColumnWidth(2.5),
              4: const pw.FixedColumnWidth(52),
              5: const pw.FixedColumnWidth(38),
              6: const pw.FixedColumnWidth(60),
              7: const pw.FixedColumnWidth(50),
            },
            children: [
              pw.TableRow(
                decoration: pw.BoxDecoration(color: headerColor),
                children: ['#', 'Client', 'Phone', 'Products', 'Date', 'Time', 'Total (Frw)', 'Status']
                    .map((h) => pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                      child: pw.Text(h, style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 8)),
                    )).toList(),
              ),
              ...filtered.asMap().entries.map((entry) {
                final idx = entry.key;
                final o = entry.value;
                final bg = idx.isEven ? PdfColors.white : lightGreen;
                final products = o.normalizedItems
                    .map((it) => '${it.productName} (${it.quantityKg.toStringAsFixed(1)}${it.unit})')
                    .join(', ');
                final totalLabel = o.discountAmount > 0
                    ? '${o.totalPrice.toStringAsFixed(0)} (-${o.discountAmount.toStringAsFixed(0)})'
                    : o.totalPrice.toStringAsFixed(0);
                return pw.TableRow(
                  decoration: pw.BoxDecoration(color: bg),
                  children: [
                    o.id.toString(),
                    o.clientName,
                    o.phone,
                    products.isEmpty ? '-' : products,
                    fmtDate(o.createdAt),
                    fmtTime(o.createdAt),
                    totalLabel,
                    o.status,
                  ].map((cell) => pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: pw.Text(cell, style: const pw.TextStyle(fontSize: 7.5)),
                  )).toList(),
                );
              }),
            ],
          ),
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (_) => doc.save());
  }
  Future<void> _printDeliveryNote(_AdminOrder order) async {
    final businessName = _businessProfile.businessName.trim().isEmpty
        ? 'PAFLY'
        : _businessProfile.businessName.trim();
    final businessContact = _businessProfile.contactSummary;
    final businessAddress = _businessProfile.addressSummary;
    final orderItems = order.normalizedItems;
    final itemsSubtotal = orderItems.isEmpty
        ? (order.totalPrice - order.deliveryFee).clamp(0, double.infinity)
        : orderItems.fold<double>(
            0,
            (sum, item) => sum + (item.quantityKg * item.pricePerKg),
          );
    final statusColor = switch (order.status.toLowerCase()) {
      'completed' => PdfColors.green700,
      'received' => PdfColors.orange700,
      'cancelled' => PdfColors.red700,
      _ => PdfColors.blueGrey700,
    };

    pw.Widget slipField(
      String label,
      String value, {
      bool emphasize = false,
      PdfColor accent = PdfColors.grey700,
    }) {
      return pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: pw.BoxDecoration(
          color: emphasize ? PdfColors.green50 : PdfColors.white,
          borderRadius: pw.BorderRadius.circular(10),
          border: pw.Border.all(
            color: emphasize ? PdfColors.green300 : PdfColors.grey300,
          ),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              label.toUpperCase(),
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: accent,
              ),
            ),
            pw.SizedBox(height: 5),
            pw.Text(
              value.trim().isEmpty ? '-' : value,
              style: pw.TextStyle(
                fontSize: emphasize ? 12 : 10.5,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey900,
              ),
            ),
          ],
        ),
      );
    }

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageTheme: const pw.PageTheme(
          margin: pw.EdgeInsets.fromLTRB(28, 28, 28, 28),
        ),
        build: (context) {
          return [
            pw.Container(
              padding: const pw.EdgeInsets.all(18),
              decoration: pw.BoxDecoration(
                color: PdfColors.white,
                borderRadius: pw.BorderRadius.circular(20),
                border: pw.Border.all(color: PdfColors.grey400, width: 1.1),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              'DELIVERY RIDER SLIP',
                              style: pw.TextStyle(
                                fontSize: 10,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColors.green700,
                                letterSpacing: 1.2,
                              ),
                            ),
                            pw.SizedBox(height: 6),
                            pw.Text(
                              businessName,
                              style: pw.TextStyle(
                                fontSize: 20,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColors.grey900,
                              ),
                            ),
                            if (businessAddress.isNotEmpty) ...[
                              pw.SizedBox(height: 5),
                              pw.Text(
                                'Business location: $businessAddress',
                                style: const pw.TextStyle(fontSize: 10),
                              ),
                            ],
                            if (businessContact.isNotEmpty) ...[
                              pw.SizedBox(height: 2),
                              pw.Text(
                                businessContact,
                                style: const pw.TextStyle(fontSize: 10),
                              ),
                            ],
                          ],
                        ),
                      ),
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        decoration: pw.BoxDecoration(
                          color: statusColor,
                          borderRadius: pw.BorderRadius.circular(999),
                        ),
                        child: pw.Text(
                          order.status.toUpperCase(),
                          style: pw.TextStyle(
                            color: PdfColors.white,
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 10),
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.symmetric(vertical: 8),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.green50,
                      borderRadius: pw.BorderRadius.circular(12),
                    ),
                    child: pw.Text(
                      businessName.toUpperCase(),
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(
                        fontSize: 24,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.green100,
                        letterSpacing: 3,
                      ),
                    ),
                  ),
                  pw.SizedBox(height: 12),
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Expanded(
                        child: slipField(
                          'Rider ref',
                          '#${order.id}',
                          emphasize: true,
                          accent: PdfColors.green700,
                        ),
                      ),
                      pw.SizedBox(width: 8),
                      pw.Expanded(
                        child: slipField(
                          'Date',
                          _orderDateLabel(order.createdAt),
                        ),
                      ),
                      pw.SizedBox(width: 8),
                      pw.Expanded(
                        child: slipField(
                          'Payment',
                          (order.paymentMethod ?? '').trim().isEmpty
                              ? 'Not saved'
                              : order.paymentMethod!.trim(),
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 10),
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Expanded(
                        child: slipField(
                          'Pickup',
                          businessAddress.isEmpty
                              ? _businessProfile.location.trim()
                              : businessAddress,
                          accent: PdfColors.green700,
                        ),
                      ),
                      pw.SizedBox(width: 8),
                      pw.Expanded(
                        child: slipField(
                          'Dropoff',
                          '${order.clientName}\n${order.phone}\n${order.location}',
                          emphasize: true,
                          accent: PdfColors.red700,
                        ),
                      ),
                    ],
                  ),
                  if (_liveLocationLabelForOrder(order).trim().isNotEmpty) ...[
                    pw.SizedBox(height: 8),
                    slipField(
                      'Delivery point',
                      _liveLocationLabelForOrder(order),
                      accent: PdfColors.blueGrey700,
                    ),
                  ],
                ],
              ),
            ),
            pw.SizedBox(height: 18),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              decoration: pw.BoxDecoration(
                color: PdfColors.green700,
                borderRadius: pw.BorderRadius.circular(10),
              ),
              child: pw.Text(
                'ORDER ITEMS',
                style: pw.TextStyle(
                  color: PdfColors.white,
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ),
            pw.SizedBox(height: 8),
            if (orderItems.isEmpty)
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(14),
                decoration: pw.BoxDecoration(
                  borderRadius: pw.BorderRadius.circular(12),
                  border: pw.Border.all(color: PdfColors.grey300),
                ),
                child: pw.Text('No product lines saved.'),
              )
            else
              pw.Table(
                border: pw.TableBorder(
                  horizontalInside: pw.BorderSide(
                    color: PdfColors.grey300,
                    width: 0.6,
                  ),
                  bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.8),
                  left: pw.BorderSide(color: PdfColors.grey400, width: 0.8),
                  right: pw.BorderSide(color: PdfColors.grey400, width: 0.8),
                ),
                columnWidths: const {
                  0: pw.FlexColumnWidth(3.8),
                  1: pw.FlexColumnWidth(1.6),
                  2: pw.FlexColumnWidth(1.8),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(
                      color: PdfColors.grey100,
                    ),
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(
                          'Product',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(
                          'Qty',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(
                          'Price',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  ...orderItems.map(
                    (item) => pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                item.productName,
                                style: pw.TextStyle(
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                              pw.SizedBox(height: 2),
                              pw.Text(
                                _rateLabel(
                                  item.pricePerKg,
                                  _unitForOrderItem(item),
                                ),
                                style: pw.TextStyle(
                                  fontSize: 9,
                                  color: PdfColors.grey700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text(
                            _qtyLabel(item.quantityKg, _unitForOrderItem(item)),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text(
                            _moneyLabel(item.quantityKg * item.pricePerKg),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            pw.SizedBox(height: 18),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(12),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.grey100,
                      borderRadius: pw.BorderRadius.circular(12),
                      border: pw.Border.all(color: PdfColors.grey300),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'CLIENT ADDRESS',
                          style: pw.TextStyle(
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.red700,
                          ),
                        ),
                        pw.SizedBox(height: 6),
                        pw.Text(
                          order.location.trim().isEmpty
                              ? '-'
                              : order.location.trim(),
                          style: pw.TextStyle(
                            fontSize: 11,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                pw.SizedBox(width: 10),
                pw.Container(
                  width: 215,
                  padding: const pw.EdgeInsets.all(14),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.green50,
                    borderRadius: pw.BorderRadius.circular(14),
                    border: pw.Border.all(color: PdfColors.green200),
                  ),
                  child: pw.Column(
                    children: [
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('Products'),
                          pw.Text(_moneyLabel(itemsSubtotal)),
                        ],
                      ),
                      pw.SizedBox(height: 6),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('Delivery fee'),
                          pw.Text(_moneyLabel(order.deliveryFee)),
                        ],
                      ),
                      pw.Divider(color: PdfColors.green300),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            'Total amount',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          ),
                          pw.Text(
                            _moneyLabel(order.totalPrice),
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 16),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(11),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300),
                borderRadius: pw.BorderRadius.circular(10),
              ),
              child: pw.Text(
                'Rider check: confirm product name, quantity, delivery fee, and client address before dispatch.',
                style: const pw.TextStyle(fontSize: 9.5),
              ),
            ),
          ];
        },
      ),
    );
    await Printing.layoutPdf(onLayout: (_) => doc.save());
  }

  Future<void> _printDebtReportFlow() async {
    final now = DateTime.now();
    final start = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDate: now.subtract(const Duration(days: 30)),
    );
    if (start == null || !mounted) return;
    final end = await showDatePicker(
      context: context,
      firstDate: start,
      lastDate: now,
      initialDate: now,
    );
    if (end == null) return;
    await _printDebtReport(start, end);
  }

  Future<void> _printDebtReport(DateTime start, DateTime end) async {
    final filteredOrders = orders.where((order) {
      final createdAt = order.createdAt;
      if (createdAt == null) return false;
      final date = DateTime(createdAt.year, createdAt.month, createdAt.day);
      return !date.isBefore(DateTime(start.year, start.month, start.day)) &&
          !date.isAfter(DateTime(end.year, end.month, end.day)) &&
          order.status != 'Cancelled' &&
          order.balance > 0;
    }).toList();

    final aggregated = <String, _AdminDebt>{};
    for (final order in filteredOrders) {
      final items = order.normalizedItems;
      if (items.isEmpty) continue;

      final subtotal = items.fold<double>(
        0,
        (sum, item) => sum + (item.quantityKg * item.pricePerKg),
      );

      for (final item in items) {
        final lineSubtotal = item.quantityKg * item.pricePerKg;
        final weight = subtotal > 0
            ? (lineSubtotal / subtotal)
            : 1 / items.length;
        final lineTotal = order.totalPrice * weight;
        final linePaid = order.paidAmount * weight;
        final lineBalance = lineTotal - linePaid;
        final key = '${order.phone}_${item.productId}';
        final existing = aggregated[key];

        if (existing == null) {
          aggregated[key] = _AdminDebt(
            clientName: order.clientName,
            phone: order.phone,
            location: order.location,
            productId: item.productId,
            productName: item.productName,
            quantityKg: item.quantityKg,
            totalAmount: lineTotal,
            paid: linePaid,
            balance: lineBalance,
          );
        } else {
          aggregated[key] = _AdminDebt(
            clientName: existing.clientName,
            phone: existing.phone,
            location: existing.location,
            productId: existing.productId,
            productName: existing.productName,
            quantityKg: existing.quantityKg + item.quantityKg,
            totalAmount: existing.totalAmount + lineTotal,
            paid: existing.paid + linePaid,
            balance: existing.balance + lineBalance,
          );
        }
      }
    }

    final filteredDeliveryFees = filteredOrders.fold<double>(
      0,
      (sum, order) => sum + order.deliveryFee,
    );
    final filteredSales = filteredOrders.fold<double>(
      0,
      (sum, order) => sum + order.totalPrice,
    );

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        build: (context) => [
          pw.Text(
            'Debt Report',
            style: pw.TextStyle(fontSize: 26, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.Text('From ${_orderDateLabel(start)} to ${_orderDateLabel(end)}'),
          pw.SizedBox(height: 8),
          pw.Text('Orders: ${filteredOrders.length}'),
          pw.Text('Sales total: ${_moneyLabel(filteredSales)}'),
          pw.Text('Delivery fees: ${_moneyLabel(filteredDeliveryFees)}'),
          pw.SizedBox(height: 18),
          if (aggregated.isEmpty)
            pw.Text('No outstanding debt found in the selected date range.')
          else
            pw.TableHelper.fromTextArray(
              headers: const [
                'Client',
                'Phone',
                'Product',
                'Total',
                'Paid',
                'Balance',
              ],
              data: aggregated.values
                  .map(
                    (debt) => [
                      debt.clientName,
                      debt.phone,
                      debt.productName,
                      _moneyLabel(debt.totalAmount),
                      _moneyLabel(debt.paid),
                      _moneyLabel(debt.balance),
                    ],
                  )
                  .toList(),
            ),
        ],
      ),
    );
    await Printing.layoutPdf(onLayout: (_) => doc.save());
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Admin Control Center')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Admin Control Center')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: _AdminEmptyState(
              icon: Icons.storage_rounded,
              title: 'Unable to load admin data',
              message: _friendlyAdminError(
                _loadError!,
                fallbackMessage:
                    'The admin panel could not load its backend data.',
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF3F7EF),
      body: SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFF7FAF3), Color(0xFFE7F0DD)],
            ),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final forceCompactSidebar = constraints.maxWidth < 820;
              final isCollapsed = forceCompactSidebar || _sidebarCollapsed;

              return Row(
                children: [
                  AdminConsoleSidebar(
                    items: _sidebarItems,
                    isCollapsed: isCollapsed,
                    onToggle: () => setState(() {
                      _sidebarCollapsed = !_sidebarCollapsed;
                    }),
                    onSignOut: _signOut,
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(0, 12, 12, 12),
                      child: Column(
                        children: [
                          AdminConsoleHeader(
                            pendingOrdersCount: _pendingOrdersCount,
                            onBrowseInventory: () => setState(
                              () => _section = _AdminSection.products,
                            ),
                            onOpenOrders: () =>
                                setState(() => _section = _AdminSection.orders),
                            onOpenSettings: () => setState(
                              () => _section = _AdminSection.settings,
                            ),
                            onRefresh: _loadAdminData,
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: RefreshIndicator(
                              onRefresh: _loadAdminData,
                              child: SingleChildScrollView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.only(bottom: 24),
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 220),
                                  child: KeyedSubtree(
                                    key: ValueKey(_section),
                                    child: _section == _AdminSection.dashboard
                                        ? _dashboardShellSection()
                                        : Padding(
                                            padding: const EdgeInsets.only(
                                              right: 4,
                                            ),
                                            child: _buildSection(),
                                          ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSection() {
    return switch (_section) {
      _AdminSection.dashboard => _dashboardSection(),
      _AdminSection.products => _productsSection(),
      _AdminSection.priceControl => _priceControlSection(),
      _AdminSection.categories => _categoriesSection(),
      _AdminSection.promotions => _promotionsSection(),
      _AdminSection.orders => _ordersSection(),
      _AdminSection.clients => _clientsSection(),
      _AdminSection.debts => _debtsSection(),
      _AdminSection.reports => _reportsSection(),
      _AdminSection.settings => _settingsSection(),
    };
  }

  Widget _dashboardSection() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 700;
        final quickActionSpacing = isCompact ? 10.0 : 10.0;

        final quickActions = [
          _AdminQuickActionButton(
            label: 'Add Product',
            icon: Icons.add_box_outlined,
            background: const LinearGradient(
              colors: [Color(0xFF2E7D32), Color(0xFF43A047)],
            ),
            onTap: _editProduct,
          ),
          _AdminQuickActionButton(
            label: 'Category',
            icon: Icons.category_outlined,
            background: const LinearGradient(
              colors: [Color(0xFF2E7D32), Color(0xFF43A047)],
            ),
            onTap: _editCategory,
          ),
          _AdminQuickActionButton(
            label: 'Print Debt Report',
            icon: Icons.print_outlined,
            outlined: true,
            onTap: _printDebtReportFlow,
          ),
        ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionTitle(
              title: 'Overview',
              subtitle:
                  'Fast visibility into stock, pending work, and money owed.',
            ),
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Quick Actions',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade800,
                ),
              ),
            ),
            const SizedBox(height: 10),
            if (isCompact)
              Column(
                children: [
                  for (var i = 0; i < quickActions.length; i++) ...[
                    quickActions[i],
                    if (i != quickActions.length - 1)
                      SizedBox(height: quickActionSpacing),
                  ],
                ],
              )
            else
              Row(
                children: [
                  Expanded(child: quickActions[0]),
                  const SizedBox(width: 10),
                  Expanded(child: quickActions[1]),
                ],
              ),
            if (!isCompact) const SizedBox(height: 10),
            if (!isCompact) quickActions[2],
            if (isCompact) const SizedBox(height: 0),

            const SizedBox(height: 24),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Low Stock',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade800,
                ),
              ),
            ),
            const SizedBox(height: 10),
            _lowStockProducts.isEmpty
                ? Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          color: Color(0xFF2E7D32),
                          size: 28,
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'No low-stock warnings right now.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      ],
                    ),
                  )
                : Column(
                    children: _lowStockProducts.take(5).map((product) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(15),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.warning_amber_rounded,
                              color: Colors.orange,
                              size: 30,
                            ),
                            const SizedBox(width: 15),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    product.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                  Text(
                                    '${_qtyLabel(product.quantity, product.unit)} left - ${_categoryNameFor(product)}',
                                    style: const TextStyle(
                                      color: Colors.grey,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
          ],
        );
      },
    );
  }

  Widget _productsSection() {
    final visibleProducts = _visibleProducts;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _shopFilterBar(),
        const SizedBox(height: 14),
        _SectionTitle(
          title: 'Products',
          subtitle:
              'Create products, set purchase cost, and let category margins calculate selling prices.',
          action: FilledButton.icon(
            onPressed: () => _editProduct(),
            icon: const Icon(Icons.add),
            label: const Text('New Product'),
          ),
        ),
        const SizedBox(height: 14),
        if (visibleProducts.isEmpty)
          const _AdminEmptyState(
            icon: Icons.add_business_outlined,
            title: 'No products in stock',
            message:
                'Create the first product to start selling in the admin panel.',
          )
        else
          ...visibleProducts.map(_productCard),
      ],
    );
  }

  Widget _shopFilterBar() {
    if (shops.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ChoiceChip(
          selected: _selectedShopId == null,
          label: const Text('All shops'),
          avatar: const Icon(Icons.dashboard_customize_outlined, size: 18),
          onSelected: (_) => setState(() => _selectedShopId = null),
        ),
        ...shops.map(
          (shop) => ChoiceChip(
            selected: _selectedShopId == shop.id,
            label: Text(shop.name),
            avatar: const Icon(Icons.storefront_outlined, size: 18),
            onSelected: (_) => setState(() => _selectedShopId = shop.id),
          ),
        ),
      ],
    );
  }

  Widget _priceControlSection() {
    final selectedCategory = _selectedPriceControlCategory;
    final categoryProducts = _priceControlProducts;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          title: 'Price Control',
          subtitle:
              'Select a category, inspect its products, and update purchase and selling prices in one place.',
        ),
        const SizedBox(height: 14),
        if (categories.isEmpty)
          const _AdminEmptyState(
            icon: Icons.price_change_outlined,
            title: 'No categories to price',
            message:
                'Create a category and set its profit margin before managing product prices.',
          )
        else
          _PanelCard(
            title: 'Category pricing',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedCategory?.id,
                  items: categories
                      .map(
                        (category) => DropdownMenuItem<String>(
                          value: category.id,
                          child: Text(
                            '${category.name} - ${_formatPercent(category.profitPercentage)}%',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() {
                    _priceControlCategoryId = value;
                  }),
                  decoration: _fieldDecoration(
                    label: 'Select category',
                    icon: Icons.category_outlined,
                  ),
                ),
                const SizedBox(height: 12),
                if (selectedCategory != null)
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _OrderMetricChip(
                        label: 'Profit margin',
                        value:
                            '${_formatPercent(selectedCategory.profitPercentage)}%',
                        valueColor: _AdminUi.primary,
                      ),
                      _OrderMetricChip(
                        label: 'Products',
                        value: '${categoryProducts.length}',
                      ),
                    ],
                  ),
                if (selectedCategory != null) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.tonalIcon(
                      onPressed: categoryProducts.isEmpty
                          ? null
                          : () async {
                              try {
                                final syncedCount =
                                    await _syncCategoryProductPrices(
                                      categoryId: selectedCategory.id,
                                      sourceProfitPercentage:
                                          selectedCategory.profitPercentage,
                                      targetProfitPercentage:
                                          selectedCategory.profitPercentage,
                                    );
                                await _loadAdminData(showLoading: false);
                                _showAdminSnack(
                                  'Synced $syncedCount product prices for ${selectedCategory.name}.',
                                );
                              } catch (error) {
                                _showAdminSnack(
                                  _friendlyAdminError(
                                    error,
                                    fallbackMessage:
                                        'Unable to sync category prices.',
                                  ),
                                );
                              }
                            },
                      icon: const Icon(Icons.sync_alt_outlined),
                      label: const Text('Sync Category Prices'),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                if (categoryProducts.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'No products are linked to this category yet.',
                      style: TextStyle(color: Color(0xFF617066)),
                    ),
                  )
                else
                  Column(
                    children: categoryProducts
                        .map(_priceControlProductCard)
                        .toList(),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _priceControlProductCard(_AdminProduct product) {
    final currentSelling = product.displayPrice;
    final purchasePrice =
        product.purchasePrice ?? _initialPurchasePriceForEdit(product);
    final categoryProfit = _profitPercentageForCategoryId(product.categoryId);
    final computedSelling = _sellingPriceForCategoryPurchase(
      purchasePrice,
      product.categoryId,
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 620;
            final info = Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _OrderMetricChip(
                  label: 'Before',
                  value:
                      '${_moneyLabel(currentSelling)}/${product.unit.toLowerCase()}',
                ),
                _OrderMetricChip(
                  label: 'Purchase',
                  value:
                      '${_moneyLabel(purchasePrice)}/${product.unit.toLowerCase()}',
                ),
                _OrderMetricChip(
                  label: 'Selling',
                  value:
                      '${_moneyLabel(computedSelling)}/${product.unit.toLowerCase()}',
                  valueColor: _AdminUi.primary,
                ),
              ],
            );

            return compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  product.name,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${_categoryNameFor(product)} - ${_formatPercent(categoryProfit)}% margin',
                                  style: const TextStyle(
                                    color: Color(0xFF617066),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton(
                            onPressed: () => _editProductPricing(product),
                            child: const Text('Update'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      info,
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              product.name,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${_categoryNameFor(product)} - ${_formatPercent(categoryProfit)}% margin',
                              style: const TextStyle(color: Color(0xFF617066)),
                            ),
                            const SizedBox(height: 12),
                            info,
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton(
                        onPressed: () => _editProductPricing(product),
                        child: const Text('Update'),
                      ),
                    ],
                  );
          },
        ),
      ),
    );
  }

  Widget _categoriesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          title: 'Categories',
          subtitle:
              'Group products and define the profit margin used for automatic selling prices.',
          action: FilledButton.icon(
            onPressed: () => _editCategory(),
            icon: const Icon(Icons.add),
            label: const Text('New Category'),
          ),
        ),
        const SizedBox(height: 14),
        if (categories.isEmpty)
          const _AdminEmptyState(
            icon: Icons.category_outlined,
            title: 'No categories yet',
            message: 'Create categories to organize the catalogue.',
          )
        else
          ...categories.map(_categoryCard),
      ],
    );
  }

  Widget _ordersSection() {
    final visibleOrders = _visibleOrders;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _shopFilterBar(),
        const SizedBox(height: 14),
        const _SectionTitle(
          title: 'Orders',
          subtitle:
              'Track checkout activity, update status, collect payments, and print notes.',
        ),
        const SizedBox(height: 14),
        if (visibleOrders.isEmpty)
          const _AdminEmptyState(
            icon: Icons.receipt_long_outlined,
            title: 'No orders yet',
            message: 'Customer orders will appear here after checkout.',
          )
        else
          ...visibleOrders.map((order) => _adminOrderCard(order)),
      ],
    );
  }

  Widget _clientsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(
          title: 'Clients',
          subtitle:
              'See buying history, total paid, and current outstanding balances.',
        ),
        const SizedBox(height: 14),
        if (clients.isEmpty)
          const _AdminEmptyState(
            icon: Icons.group_outlined,
            title: 'No clients yet',
            message:
                'Client records appear automatically after the first order.',
          )
        else
          ...clients.map(_clientCard),
      ],
    );
  }

  Widget _debtsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(
          title: 'Debts',
          subtitle:
              'See open balances, inspect order history, and record new payments.',
        ),
        const SizedBox(height: 14),
        if (debts.isEmpty)
          const _AdminEmptyState(
            icon: Icons.account_balance_wallet_outlined,
            title: 'No outstanding debts',
            message:
                'Credit orders with unpaid balances will appear here automatically.',
          )
        else
          ...debts.map(_debtCard),
      ],
    );
  }

  Widget _reportsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          title: 'Reports & Printing',
          subtitle:
              'Export orders, print delivery notes and debt reports by date range.',
          action: Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _exportOrdersCsvFlow,
                icon: const Icon(Icons.download_outlined),
                label: const Text('Export CSV'),
              ),
              FilledButton.icon(
                onPressed: _printOrdersReportFlow,
                icon: const Icon(Icons.print_outlined),
                label: const Text('Print Orders'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _PanelCard(
          title: 'Report Summary',
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _OrderMetricChip(
                label: 'Active orders',
                value: '${_activeOrders.length}',
              ),
              _OrderMetricChip(
                label: 'Product revenue',
                value: _moneyLabel(_totalProductRevenue),
              ),
              _OrderMetricChip(
                label: 'Delivery fees',
                value: _moneyLabel(_totalDeliveryFees),
                valueColor: _AdminUi.primary,
              ),
              _OrderMetricChip(
                label: 'Total sales',
                value: _moneyLabel(_totalSalesRevenue),
              ),
              if (_totalDiscountsGiven > 0)
                _OrderMetricChip(
                  label: 'Promo discounts given',
                  value: '-',
                  valueColor: Colors.green.shade700,
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _PanelCard(
          title: 'Delivery Notes',
          child: orders.isEmpty
              ? const Text('No orders available to print yet.')
              : Column(
                  children: orders
                      .take(6)
                      .map(
                        (order) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(
                            Icons.local_shipping_outlined,
                            color: _AdminUi.primary,
                          ),
                          title: Text(
                            '#${order.id} ${order.displayProductName}',
                          ),
                          subtitle: Text(
                            '${order.clientName} - ${order.phone}\n${_liveLocationLabelForOrder(order)}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: OutlinedButton.icon(
                            onPressed: () => _printDeliveryNote(order),
                            icon: const Icon(Icons.print_outlined),
                            label: const Text('Print'),
                          ),
                        ),
                      )
                      .toList(),
                ),
        ),
      ],
    );
  }

  Widget _settingsSection() {
    final contactSummary = _businessProfile.contactSummary.isEmpty
        ? 'No phone or email saved yet.'
        : _businessProfile.contactSummary;
    final addressSummary = _businessProfile.addressSummary.isEmpty
        ? 'No address or location label saved yet.'
        : _businessProfile.addressSummary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          title: 'Business Settings',
          subtitle:
              'Set the company details printed on delivery notes and the business GPS used for delivery-fee distance.',
          action: FilledButton.icon(
            onPressed: _editBusinessProfile,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Edit Settings'),
          ),
        ),
        const SizedBox(height: 14),
        _PanelCard(
          title: 'Current business profile',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _OrderMetricChip(
                    label: 'Business',
                    value: _businessProfile.businessName,
                    valueColor: _AdminUi.primary,
                  ),
                  _OrderMetricChip(
                    label: 'Location',
                    value: _businessProfile.location.trim().isEmpty
                        ? 'Not set'
                        : _businessProfile.location.trim(),
                  ),
                  _OrderMetricChip(
                    label: 'GPS',
                    value: _businessGpsLabel(_businessProfile),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'Contact: $contactSummary',
                style: const TextStyle(
                  color: Color(0xFF617066),
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                addressSummary,
                style: const TextStyle(
                  color: Color(0xFF617066),
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (!_businessProfile.hasCoordinates) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF4E5),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFFFD9A8)),
                  ),
                  child: const Text(
                    'Business GPS is not set yet. Delivery calculations will keep using the fallback store coordinates until you save latitude and longitude here.',
                    style: TextStyle(
                      color: Color(0xFF8A5A00),
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        _PanelCard(
          title: 'Partner shops',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: () => _editShop(),
                  icon: const Icon(Icons.add_business_outlined),
                  label: const Text('Add Shop'),
                ),
              ),
              const SizedBox(height: 12),
              if (shops.isEmpty)
                const Text(
                  'Run the latest Supabase schema to enable partner shops.',
                  style: TextStyle(
                    color: Color(0xFF617066),
                    fontWeight: FontWeight.w600,
                  ),
                )
              else
                ...shops.map(
                  (shop) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      shop.isActive
                          ? Icons.storefront_rounded
                          : Icons.storefront_outlined,
                      color: shop.isActive ? _AdminUi.primary : Colors.grey,
                    ),
                    title: Text(shop.name),
                    subtitle: Text(
                      [
                        if (shop.location.trim().isNotEmpty) shop.location,
                        '${_formatPercent(shop.commissionPercent)}% commission',
                        shop.isActive ? 'Active' : 'Hidden',
                      ].join(' - '),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(
                          value: shop.isActive,
                          onChanged: (_) => _toggleShopStatus(shop),
                          activeThumbColor: _AdminUi.primary,
                        ),
                        IconButton(
                          onPressed: () => _editShop(shop),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const _PanelCard(
          title: 'Used by the app',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Delivery notes print the saved business name, contact, and address.',
                style: TextStyle(
                  color: Color(0xFF617066),
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 10),
              Text(
                'Client delivery fees use the saved business GPS as the starting point when measuring distance to the client location.',
                style: TextStyle(
                  color: Color(0xFF617066),
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _productCard(_AdminProduct product) {
    final lowStock = product.quantity > 0 && product.quantity < 50;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 560;
        final imageSize = compact ? 124.0 : 96.0;
        final imageWidget = ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: product.imageUrl.isNotEmpty
              ? Image.network(
                  product.imageUrl,
                  width: imageSize,
                  height: imageSize,
                  fit: BoxFit.cover,
                  cacheWidth: 260,
                  errorBuilder: (_, _, _) => _imageFallbackBox(size: imageSize),
                )
              : _imageFallbackBox(size: imageSize),
        );

        final metricChips = Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _OrderMetricChip(
              label: 'Sale',
              value:
                  '${_moneyLabel(product.displayPrice)}/${product.unit.toLowerCase()}',
            ),
            if (product.purchasePrice != null)
              _OrderMetricChip(
                label: 'Purchase',
                value:
                    '${_moneyLabel(product.purchasePrice!)}/${product.unit.toLowerCase()}',
                valueColor: const Color(0xFF617066),
              ),
            if (product.hasDiscount)
              _OrderMetricChip(
                label: 'Discount',
                value:
                    '${_moneyLabel(product.discountPrice!)}/${product.unit.toLowerCase()} from ${_qtyLabel(product.discountThresholdKg!, product.unit)}',
                valueColor: Colors.orange,
              ),
            _OrderMetricChip(
              label: 'Stock',
              value: _qtyLabel(product.quantity, product.unit),
              valueColor: lowStock ? Colors.red : _AdminUi.primary,
            ),
          ],
        );

        final actionButtons = Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            OutlinedButton.icon(
              onPressed: () => _editProduct(product),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit'),
            ),
            OutlinedButton.icon(
              onPressed: () => _adjustStock(product),
              icon: const Icon(Icons.sync_alt_outlined),
              label: const Text('Stock'),
            ),
            OutlinedButton.icon(
              onPressed: () => _toggleProductAvailability(product),
              icon: Icon(
                product.isAvailable
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
              label: Text(product.isAvailable ? 'Disable' : 'Enable'),
            ),
            FilledButton.tonalIcon(
              onPressed: () => _deleteProduct(product),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete'),
            ),
          ],
        );

        return Card(
          margin: const EdgeInsets.only(bottom: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: imageWidget,
                      ),
                      const SizedBox(height: 14),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  product.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _categoryNameFor(product),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: _AdminUi.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          _InventoryStatusPill(available: product.isAvailable),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        product.description,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF607066),
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 12),
                      metricChips,
                      const SizedBox(height: 14),
                      actionButtons,
                    ],
                  )
                : Column(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          imageWidget,
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        product.name,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 19,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    _InventoryStatusPill(
                                      available: product.isAvailable,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _categoryNameFor(product),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: _AdminUi.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  product.description,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFF607066),
                                    height: 1.35,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                metricChips,
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      actionButtons,
                    ],
                  ),
          ),
        );
      },
    );
  }

  Widget _categoryCard(_AdminCategory category) {
    final productCount = products
        .where((product) => product.categoryId == category.id)
        .length;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: Color(0xFFE8F3E9),
          child: Icon(Icons.category_outlined, color: _AdminUi.primary),
        ),
        title: Text(category.name),
        subtitle: Text(
          '$productCount products - ${_formatPercent(category.profitPercentage)}% profit margin',
        ),
        trailing: Wrap(
          spacing: 8,
          children: [
            IconButton(
              onPressed: () => _editCategory(category),
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              onPressed: () => _deleteCategory(category),
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
      ),
    );
  }

  Widget _clientCard(_ClientSummary client) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 420;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: EdgeInsets.all(compact ? 14 : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  client.clientName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${client.phone} - ${client.location}',
                  style: const TextStyle(color: Color(0xFF617066)),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _OrderMetricChip(
                      label: 'Orders',
                      value: '${client.ordersCount}',
                    ),
                    _OrderMetricChip(
                      label: 'Paid',
                      value: _moneyLabel(client.totalPaid),
                      valueColor: _AdminUi.primary,
                    ),
                    _OrderMetricChip(
                      label: 'Debt',
                      value: _moneyLabel(client.totalDebt),
                      valueColor: client.totalDebt > 0
                          ? Colors.red
                          : _AdminUi.primary,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: compact ? double.infinity : null,
                  child: OutlinedButton.icon(
                    onPressed: () => _showOrderHistory(
                      title: 'Orders for ${client.clientName}',
                      phone: client.phone,
                      allowPayment: true,
                    ),
                    icon: const Icon(Icons.history),
                    label: const Text('View Orders'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _debtCard(_AdminDebt debt) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 420;

        final actions = compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _showOrderHistory(
                      title: 'Debt History for ${debt.clientName}',
                      phone: debt.phone,
                      productId: debt.productId,
                      allowPayment: true,
                    ),
                    icon: const Icon(Icons.history),
                    label: const Text('View History'),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.tonalIcon(
                    onPressed: () async {
                      final matching = _matchingOrders(
                        phone: debt.phone,
                        productId: debt.productId,
                        unpaidOnly: true,
                      );
                      if (matching.isEmpty) {
                        _showAdminSnack(
                          'No unpaid orders are available for payment.',
                        );
                        return;
                      }
                      await _recordPaymentForOrder(matching.first);
                    },
                    icon: const Icon(Icons.payments_outlined),
                    label: const Text('Record Payment'),
                  ),
                ],
              )
            : Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _showOrderHistory(
                      title: 'Debt History for ${debt.clientName}',
                      phone: debt.phone,
                      productId: debt.productId,
                      allowPayment: true,
                    ),
                    icon: const Icon(Icons.history),
                    label: const Text('View History'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () async {
                      final matching = _matchingOrders(
                        phone: debt.phone,
                        productId: debt.productId,
                        unpaidOnly: true,
                      );
                      if (matching.isEmpty) {
                        _showAdminSnack(
                          'No unpaid orders are available for payment.',
                        );
                        return;
                      }
                      await _recordPaymentForOrder(matching.first);
                    },
                    icon: const Icon(Icons.payments_outlined),
                    label: const Text('Record Payment'),
                  ),
                ],
              );

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: EdgeInsets.all(compact ? 14 : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        '${debt.clientName} - ${debt.productName}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red.withAlpha(24),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _moneyLabel(debt.balance),
                        style: const TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${debt.phone} - ${debt.location}',
                  style: const TextStyle(color: Color(0xFF617066)),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _OrderMetricChip(
                      label: 'Quantity',
                      value: _qtyLabel(
                        debt.quantityKg,
                        _unitForProductId(debt.productId),
                      ),
                    ),
                    _OrderMetricChip(
                      label: 'Total',
                      value: _moneyLabel(debt.totalAmount),
                    ),
                    _OrderMetricChip(
                      label: 'Paid',
                      value: _moneyLabel(debt.paid),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                actions,
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _adminOrderCard(
    _AdminOrder order, {
    bool compact = false,
    bool showActions = true,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = compact || constraints.maxWidth < 420;

        final actions = showActions
            ? (isCompact
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (order.status != 'Received')
                          OutlinedButton(
                            onPressed: () =>
                                _updateOrderStatus(order, 'Received'),
                            child: const Text('Mark Received'),
                          ),
                        if (order.status != 'Received')
                          const SizedBox(height: 10),
                        if (order.status != 'Completed')
                          OutlinedButton(
                            onPressed: () =>
                                _updateOrderStatus(order, 'Completed'),
                            child: const Text('Mark Completed'),
                          ),
                        if (order.status != 'Completed')
                          const SizedBox(height: 10),
                        if (order.status != 'Cancelled')
                          OutlinedButton(
                            onPressed: () =>
                                _updateOrderStatus(order, 'Cancelled'),
                            child: const Text('Cancel'),
                          ),
                        if (order.status != 'Cancelled')
                          const SizedBox(height: 10),
                        if (order.balance > 0 &&
                            order.status != 'Completed' &&
                            order.status != 'Cancelled')
                          FilledButton.tonalIcon(
                            onPressed: () => _recordPaymentForOrder(order),
                            icon: const Icon(Icons.payments_outlined),
                            label: const Text('Record Payment'),
                          ),
                        if (order.balance > 0 &&
                            order.status != 'Completed' &&
                            order.status != 'Cancelled')
                          const SizedBox(height: 10),
                        FilledButton.icon(
                          onPressed: () => _printDeliveryNote(order),
                          icon: const Icon(Icons.print_outlined),
                          label: const Text('Print Note'),
                        ),
                      ],
                    )
                  : Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        if (order.status != 'Received')
                          OutlinedButton(
                            onPressed: () =>
                                _updateOrderStatus(order, 'Received'),
                            child: const Text('Mark Received'),
                          ),
                        if (order.status != 'Completed')
                          OutlinedButton(
                            onPressed: () =>
                                _updateOrderStatus(order, 'Completed'),
                            child: const Text('Mark Completed'),
                          ),
                        if (order.status != 'Cancelled')
                          OutlinedButton(
                            onPressed: () =>
                                _updateOrderStatus(order, 'Cancelled'),
                            child: const Text('Cancel'),
                          ),
                        if (order.balance > 0 &&
                            order.status != 'Completed' &&
                            order.status != 'Cancelled')
                          FilledButton.tonalIcon(
                            onPressed: () => _recordPaymentForOrder(order),
                            icon: const Icon(Icons.payments_outlined),
                            label: const Text('Record Payment'),
                          ),
                        FilledButton.icon(
                          onPressed: () => _printDeliveryNote(order),
                          icon: const Icon(Icons.print_outlined),
                          label: const Text('Print Note'),
                        ),
                      ],
                    ))
            : const SizedBox.shrink();

        final statusColor = switch (order.status.toLowerCase()) {
          'completed' => const Color(0xFF2E7D32),
          'received' => const Color(0xFFE65100),
          'cancelled' => const Color(0xFFC62828),
          _ => const Color(0xFF455A64),
        };

        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: BorderSide(
              color: statusColor.withValues(alpha: 0.15),
              width: 1.5,
            ),
          ),
          color: Colors.white,
          child: Padding(
            padding: EdgeInsets.all(isCompact ? 14 : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isCompact)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              '#${order.id} ${order.displayProductName}',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          _StatusChip(status: order.status),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        order.clientName,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: _AdminUi.primary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_shopNameForId(order.shopId)} - ${order.phone}',
                        style: const TextStyle(
                          color: Color(0xFF617066),
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      _orderLocationLink(order),
                    ],
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '#${order.id} ${order.displayProductName}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      _StatusChip(status: order.status),
                    ],
                  ),
                if (!isCompact) ...[
                  const SizedBox(height: 6),
                  Text(
                    '${order.clientName} (${order.phone}) - ${_shopNameForId(order.shopId)}',
                    style: const TextStyle(
                      color: Color(0xFF617066),
                      height: 1.35,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  _orderLocationLink(order),
                ],
                if (order.status == 'Cancelled' &&
                    (order.cancelReason ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.red.shade100),
                    ),
                    child: Text(
                      'Cancel reason: ${order.cancelReason!.trim()}',
                      style: TextStyle(
                        color: Colors.red.shade800,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9FBF8),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFEFF3EF)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Ordered products',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: _AdminUi.dark,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...order.normalizedItems.map(
                        (item) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.productName,
                                      style: const TextStyle(
                                        color: _AdminUi.dark,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${_qtyLabel(item.quantityKg, _unitForOrderItem(item))} x ${_moneyLabel(item.pricePerKg)}',
                                      style: const TextStyle(
                                        color: Color(0xFF617066),
                                        fontWeight: FontWeight.w500,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                _moneyLabel(item.quantityKg * item.pricePerKg),
                                style: const TextStyle(
                                  color: _AdminUi.primary,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (order.normalizedItems.isEmpty)
                        const Text(
                          'No product lines saved.',
                          style: TextStyle(
                            color: Color(0xFF617066),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                   children: [
                    _OrderMetricChip(
                      label: 'Items',
                      value: '${order.itemsCount}',
                    ),
                    _OrderMetricChip(
                      label: 'Total (after discount)',
                      value: _moneyLabel(order.totalPrice),
                    ),
                    _OrderMetricChip(
                      label: 'Delivery',
                      value: _moneyLabel(order.deliveryFee),
                    ),
                    if (order.discountAmount > 0)
                      _OrderMetricChip(
                        label: order.discountAmount == order.deliveryFee
                            ? 'Discount (Free Delivery)'
                            : 'Promo Discount',
                        value: '-${_moneyLabel(order.discountAmount)}',
                        valueColor: Colors.green.shade700,
                      ),
                    _OrderMetricChip(
                      label: 'Paid',
                      value: _moneyLabel(order.paidAmount),
                    ),
                    _OrderMetricChip(
                      label: 'Balance',
                      value: _moneyLabel(order.balance),
                      valueColor: order.balance > 0
                          ? Colors.red
                          : _AdminUi.primary,
                    ),
                    _OrderMetricChip(
                      label: 'Payment',
                      value: (order.paymentMethod ?? '').trim().isEmpty
                          ? 'Not saved'
                          : order.paymentMethod!.trim(),
                    ),
                  ],
                ),
                if (!isCompact) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Created ${_orderDateLabel(order.createdAt)}',
                    style: const TextStyle(color: Color(0xFF617066)),
                  ),
                ],
                if (showActions) ...[const SizedBox(height: 14), actions],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _promotionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          title: 'Promotions & Coupons',
          subtitle: 'Create and manage promo codes for your customers.',
          action: FilledButton.icon(
            onPressed: () => _editPromoCode(),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Create Promo Code'),
          ),
        ),
        const SizedBox(height: 18),
        if (promoCodes.isEmpty)
          const _AdminEmptyState(
            icon: Icons.stars_rounded,
            title: 'No promotions yet',
            message:
                'Create your first promo code to offer discounts or free delivery.',
          )
        else
          ...promoCodes.map((promo) => _promoCodeCard(promo)),
      ],
    );
  }

  Widget _promoCodeCard(_AdminPromoCode promo) {
    final isExpired =
        promo.expiryDate != null && promo.expiryDate!.isBefore(DateTime.now());
    final statusColor = promo.isActive && !isExpired ? Colors.green : Colors.red;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.stars_rounded, color: statusColor),
        ),
        title: Row(
          children: [
            Text(
              promo.code,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                promo.isActive && !isExpired ? 'ACTIVE' : 'INACTIVE',
                style: TextStyle(
                  color: statusColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (promo.isVisibleToAll) ...[
              const SizedBox(width: 6),
              const Icon(Icons.visibility_rounded, size: 16, color: Colors.blue),
            ],
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              promo.description ?? 'No description',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 4),
            Text(
              'Type: ${promo.type.replaceAll('_', ' ').toUpperCase()} • Exp: ${promo.expiryDate == null ? 'Never' : _orderDateLabel(promo.expiryDate!)}',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
            ),
          ],
        ),
        trailing: IconButton(
          onPressed: () => _editPromoCode(promo),
          icon: const Icon(Icons.edit_outlined),
        ),
      ),
    );
  }

  Future<void> _editPromoCode([_AdminPromoCode? promo]) async {
    final codeCtrl = TextEditingController(text: promo?.code);
    final descCtrl = TextEditingController(text: promo?.description);
    final valueCtrl = TextEditingController(text: promo?.value.toString());
    final minPurchaseCtrl =
        TextEditingController(text: promo?.minPurchaseAmount.toString());
    final maxUsesCtrl =
        TextEditingController(text: promo?.totalMaxUses?.toString() ?? '');
    var type = promo?.type ?? 'free_delivery';
    var isActive = promo?.isActive ?? true;
    var isVisible = promo?.isVisibleToAll ?? false;
    var expiryDate = promo?.expiryDate;
    var isSaving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(promo == null ? 'Create Promo Code' : 'Edit Promo Code'),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: codeCtrl,
                      decoration: _fieldDecoration(
                        label: 'Promo Code (e.g. SAVE20)',
                        icon: Icons.abc,
                      ),
                      textCapitalization: TextCapitalization.characters,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descCtrl,
                      decoration: _fieldDecoration(
                        label: 'Description',
                        icon: Icons.description_outlined,
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: type,
                      decoration: _fieldDecoration(
                        label: 'Type',
                        icon: Icons.merge_type,
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'free_delivery',
                          child: Text('Free Delivery'),
                        ),
                        DropdownMenuItem(
                          value: 'discount_fixed',
                          child: Text('Fixed Discount'),
                        ),
                        DropdownMenuItem(
                          value: 'discount_percent',
                          child: Text('Percentage Discount'),
                        ),
                      ],
                      onChanged: (val) => setDialogState(() => type = val!),
                    ),
                    if (type != 'free_delivery') ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: valueCtrl,
                        keyboardType: TextInputType.number,
                        decoration: _fieldDecoration(
                          label: type == 'discount_percent'
                              ? 'Discount Percentage (%)'
                              : 'Discount Amount (Rwf)',
                          icon: Icons.money,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: minPurchaseCtrl,
                      keyboardType: TextInputType.number,
                      decoration: _fieldDecoration(
                        label: 'Minimum Purchase (Rwf)',
                        icon: Icons.shopping_bag_outlined,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: maxUsesCtrl,
                      keyboardType: TextInputType.number,
                      decoration: _fieldDecoration(
                        label: 'Total Max Uses (Empty for Unlimited)',
                        icon: Icons.repeat_rounded,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      title: Text(
                        expiryDate == null
                            ? 'No Expiry Date'
                            : 'Expires: ${_orderDateLabel(expiryDate!)}',
                      ),
                      trailing: const Icon(Icons.calendar_today_rounded),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: expiryDate ??
                              DateTime.now().add(const Duration(days: 30)),
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(
                            const Duration(days: 365),
                          ),
                        );
                        if (picked != null) {
                          setDialogState(() => expiryDate = picked);
                        }
                      },
                    ),
                    SwitchListTile(
                      title: const Text('Active'),
                      value: isActive,
                      onChanged: (val) => setDialogState(() => isActive = val),
                    ),
                    SwitchListTile(
                      title: const Text('Visible to all users'),
                      subtitle: const Text(
                        'Will be shown in user profiles as an offer',
                      ),
                      value: isVisible,
                      onChanged: (val) => setDialogState(() => isVisible = val),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: isSaving
                    ? null
                    : () async {
                        final code = codeCtrl.text.trim().toUpperCase();
                        if (code.isEmpty) return;

                        setDialogState(() => isSaving = true);
                        try {
                          final data = {
                            'code': code,
                            'description': descCtrl.text.trim(),
                            'type': type,
                            'value':
                                double.tryParse(valueCtrl.text.trim()) ?? 0,
                            'min_purchase_amount':
                                double.tryParse(minPurchaseCtrl.text.trim()) ??
                                0,
                            'total_max_uses':
                                int.tryParse(maxUsesCtrl.text.trim()),
                            'expiry_date': expiryDate?.toIso8601String(),
                            'is_active': isActive,
                            'is_visible_to_all': isVisible,
                          };

                          if (promo == null) {
                            await Supabase.instance.client
                                .from('promo_codes')
                                .insert(data);
                          } else {
                            await Supabase.instance.client
                                .from('promo_codes')
                                .update(data)
                                .eq('id', promo.id);
                          }

                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext);
                            _loadAdminData(showLoading: false);
                            _showAdminSnack('Promo code saved successfully!');
                          }
                        } catch (e) {
                          _showAdminSnack('Error saving promo code: $e',
                              isError: true);
                        } finally {
                          if (dialogContext.mounted) {
                            setDialogState(() => isSaving = false);
                          }
                        }
                      },
                child: isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? action;

  const _SectionTitle({
    required this.title,
    required this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(subtitle, style: const TextStyle(color: Color(0xFF617066))),
            ],
          ),
        ),
        if (action != null) ...[const SizedBox(width: 12), action!],
      ],
    );
  }
}

class _PanelCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _PanelCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _AdminQuickActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final LinearGradient? background;
  final bool outlined;
  final VoidCallback onTap;

  const _AdminQuickActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.background,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    final isOutlined = outlined || background == null;
    final foregroundColor = isOutlined ? const Color(0xFF2E7D32) : Colors.white;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          width: double.infinity,
          height: 55,
          decoration: BoxDecoration(
            gradient: isOutlined ? null : background,
            color: isOutlined ? Colors.white : null,
            borderRadius: BorderRadius.circular(15),
            border: isOutlined
                ? Border.all(color: const Color(0xFF2E7D32))
                : null,
            boxShadow: isOutlined
                ? null
                : [
                    BoxShadow(
                      color: Colors.green.withValues(alpha: 0.25),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: foregroundColor),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foregroundColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _AdminEmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE4ECE3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 52,
            width: 52,
            decoration: BoxDecoration(
              color: const Color(0x1A2E7D32),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, color: _AdminUi.primary, size: 28),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Color(0xFF24302A),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            message,
            style: TextStyle(
              color: Colors.grey.shade700,
              height: 1.45,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _InventoryStatusPill extends StatelessWidget {
  final bool available;

  const _InventoryStatusPill({required this.available});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: available
            ? Colors.green.withAlpha(28)
            : Colors.red.withAlpha(28),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        available ? 'Enabled' : 'Disabled',
        style: TextStyle(
          color: available ? Colors.green : Colors.red,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status.toLowerCase()) {
      'completed' => const Color(0xFF2E7D32),
      'received' => const Color(0xFFE65100),
      'cancelled' => const Color(0xFFC62828),
      _ => const Color(0xFF455A64),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2), width: 1.5),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 10,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _OrderMetricChip extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _OrderMetricChip({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE1EAE1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF6B7A71),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: valueColor ?? _AdminUi.dark,
            ),
          ),
        ],
      ),
    );
  }
}
