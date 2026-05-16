import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter/rendering.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:potato_app/services/notification_service.dart';
import 'package:potato_app/utils/app_ui.dart';
import 'package:potato_app/utils/constants.dart';
import 'package:potato_app/utils/supabase_errors.dart';
import 'package:potato_app/services/pwa_service.dart';
import 'package:potato_app/models/business_profile.dart';
import 'package:potato_app/models/product.dart';
import 'package:potato_app/models/category.dart';
import 'package:potato_app/models/shop.dart';
import 'package:potato_app/models/promotion.dart';
import 'package:potato_app/models/order.dart';
import 'package:potato_app/screens/login_screen.dart';
import 'package:potato_app/services/live_location_service.dart';
import 'package:potato_app/services/push_notification_service.dart';
import 'package:potato_app/utils/delivery_fee.dart';
import 'package:potato_app/utils/formatters.dart';
import 'package:potato_app/utils/input_rules.dart';
import 'package:potato_app/widgets/fresh_market_home_widgets.dart';
import 'package:potato_app/widgets/branded_loading_indicator.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';

class ClientDashboard extends StatefulWidget {
  const ClientDashboard({super.key});

  @override
  State<ClientDashboard> createState() => _ClientDashboardState();
}

class _ClientDashboardState extends State<ClientDashboard> {
  int _currentIndex = 0;
  Map<String, dynamic>? _userProfile;
  bool _showBottomNav = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(NotificationService.instance.checkAndPromptPermissions());
    });
  }

  Future<void> _loadProfile() async {
    final uid = Supabase.instance.client.auth.currentUser!.id;
    NotificationService.instance.setupClientListener(uid);
    unawaited(PushNotificationService.instance.registerClientDevice(uid));
    final res = await Supabase.instance.client
        .from('users')
        .select()
        .eq('id', uid)
        .maybeSingle();

    if (mounted && res != null) {
      final profile = Map<String, dynamic>.from(res);
      final metadataPhone =
          Supabase.instance.client.auth.currentUser?.userMetadata?['phone']
              ?.toString()
              .trim() ??
          '';
      final savedPhone = profile['phone']?.toString().trim() ?? '';

      if (savedPhone.isEmpty && metadataPhone.isNotEmpty) {
        try {
          final updated = await Supabase.instance.client.rpc(
            'update_own_user_profile',
            params: {
              'display_name': profile['name']?.toString().trim() ?? '',
              'location_param': profile['location']?.toString().trim() ?? '',
              'whatsapp_param': profile['whatsapp']?.toString().trim() ?? '',
              'phone_param': metadataPhone,
            },
          );

          if (updated is Map) {
            profile.addAll(Map<String, dynamic>.from(updated));
          } else {
            final refreshed = await Supabase.instance.client
                .from('users')
                .select()
                .eq('id', uid)
                .maybeSingle();
            if (refreshed != null) {
              profile
                ..clear()
                ..addAll(Map<String, dynamic>.from(refreshed));
            }
          }
        } catch (_) {
          // Best effort only. The dashboard still loads if the sync fails.
        }
      }

      unawaited(
        LiveLocationService.instance.startTracking(
          userId: uid,
          customerName: profile['name']?.toString() ?? 'Client',
          phone: profile['phone']?.toString() ?? metadataPhone,
          locationLabel: profile['location']?.toString() ?? '',
        ),
      );
      unawaited(LiveLocationService.instance.loadBusinessProfile());
      setState(() => _userProfile = profile);
    }
  }

  @override
  void dispose() {
    unawaited(LiveLocationService.instance.stopTracking());
    super.dispose();
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) {
      return false;
    }

    final atTop = notification.metrics.pixels <= 16;
    final shouldShow =
        atTop ||
        (notification is UserScrollNotification &&
            notification.direction != ScrollDirection.reverse);

    if (shouldShow != _showBottomNav && mounted) {
      setState(() => _showBottomNav = shouldShow);
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (_userProfile == null) {
      return const Scaffold(
        backgroundColor: Color(0xFFF5F8EF),
        body: Center(
          child: BrandedLoadingIndicator(
            size: 88,
            logoSize: 44,
            label: 'Loading your PAFLY dashboard...',
          ),
        ),
      );
    }

    final tabs = [
      _ClientHomeTab(userProfile: _userProfile!),
      _ClientOrdersTab(userId: _userProfile!['id']),
      _ClientProfileTab(
        userProfile: _userProfile!,
        onProfileUpdated: _loadProfile,
        onOpenOrders: () => setState(() => _currentIndex = 1),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 800;

        return Scaffold(
          extendBody: true,
          body: Row(
            children: [
              if (isDesktop)
                NavigationRail(
                  selectedIndex: _currentIndex,
                  onDestinationSelected: (v) => setState(() {
                    _currentIndex = v;
                  }),
                  labelType: NavigationRailLabelType.all,
                  backgroundColor: Colors.white,
                  indicatorColor: const Color(0x1F3B8B3F),
                  selectedIconTheme: const IconThemeData(color: AppUi.primary),
                  selectedLabelTextStyle: const TextStyle(
                    color: AppUi.primary,
                    fontWeight: FontWeight.w800,
                  ),
                  unselectedLabelTextStyle: TextStyle(
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w600,
                  ),
                  leading: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Image.asset('assets/logo.png', height: 48),
                  ),
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.home_outlined),
                      selectedIcon: Icon(Icons.home_rounded),
                      label: Text('Home'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.receipt_long_outlined),
                      selectedIcon: Icon(Icons.receipt_long_rounded),
                      label: Text('Orders'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.person_outline_rounded),
                      selectedIcon: Icon(Icons.person_rounded),
                      label: Text('Account'),
                    ),
                  ],
                ),
              if (isDesktop) const VerticalDivider(thickness: 1, width: 1),
              Expanded(
                child: NotificationListener<ScrollNotification>(
                  onNotification: _handleScrollNotification,
                  child: tabs[_currentIndex],
                ),
              ),
            ],
          ),
          bottomNavigationBar: !isDesktop
              ? AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  child: _showBottomNav
                      ? SafeArea(
                          key: const ValueKey('bottom_nav_visible'),
                          minimum: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(28),
                            child: NavigationBarTheme(
                              data: NavigationBarThemeData(
                                height: 76,
                                backgroundColor: Colors.white.withValues(alpha: 0.96),
                                indicatorColor: const Color(0x1F3B8B3F),
                                elevation: 10,
                                labelTextStyle: WidgetStateProperty.resolveWith((states) {
                                  final selected = states.contains(WidgetState.selected);
                                  return TextStyle(
                                    fontSize: 12,
                                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                                    color: selected ? AppUi.primary : Colors.grey.shade600,
                                  );
                                }),
                                iconTheme: WidgetStateProperty.resolveWith((states) {
                                  final selected = states.contains(WidgetState.selected);
                                  return IconThemeData(
                                    color: selected ? AppUi.primary : Colors.grey.shade500,
                                    size: 24,
                                  );
                                }),
                              ),
                              child: NavigationBar(
                                selectedIndex: _currentIndex,
                                onDestinationSelected: (v) => setState(() {
                                  _currentIndex = v;
                                  _showBottomNav = true;
                                }),
                                destinations: const [
                                  NavigationDestination(
                                    icon: Icon(Icons.home_outlined),
                                    selectedIcon: Icon(Icons.home_rounded),
                                    label: 'Home',
                                  ),
                                  NavigationDestination(
                                    icon: Icon(Icons.receipt_long_outlined),
                                    selectedIcon: Icon(Icons.receipt_long_rounded),
                                    label: 'Orders',
                                  ),
                                  NavigationDestination(
                                    icon: Icon(Icons.person_outline_rounded),
                                    selectedIcon: Icon(Icons.person_rounded),
                                    label: 'Account',
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                      : const SizedBox.shrink(key: ValueKey('bottom_nav_hidden')),
                )
              : null,
        );
      },
    );
  }
}

class _ClientHomeTab extends StatefulWidget {
  final Map<String, dynamic> userProfile;

  const _ClientHomeTab({required this.userProfile});

  @override
  State<_ClientHomeTab> createState() => _ClientHomeTabState();
}

class _ClientHomeTabState extends State<_ClientHomeTab> {
  late Future<List<Map<String, dynamic>>> _productsFuture;
  final Map<String, double> _cart = {};
  List<Shop> _shops = [];
  List<Category> _categories = [];
  List<Promotion> _promotions = [];
  String? _selectedCategory;
  String? _selectedShopId;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  int _bannerPage = 0;
  Timer? _bannerTimer;
  final PageController _bannerPageController = PageController(
    initialPage: 1000,
  );
  final Set<String> _precacheQueuedImageUrls = {};

  static const String _cartDraftKey = 'client_cart_draft_v1';

  @override
  void initState() {
    super.initState();
    _productsFuture = _loadProducts();

    _loadHomeData();
    unawaited(_restoreCartDraft());
  }

  Future<List<Map<String, dynamic>>> _loadProducts() async {
    dynamic response;
    try {
      response = await Supabase.instance.client
          .from('products')
          .select(
            'id,shop_id,name,description,image_url,category_id,purchase_price,selling_price,price,discount_price,discount_threshold_kg,quantity,unit,is_available,created_at',
          )
          .eq('is_available', true)
          .gt('quantity', 0)
          .order('created_at', ascending: false);
    } on PostgrestException catch (error) {
      final details = '${error.message} ${error.details} ${error.hint}'
          .toLowerCase();
      if (!details.contains('shop_id')) rethrow;
      response = await Supabase.instance.client
          .from('products')
          .select(
            'id,name,description,image_url,category_id,purchase_price,selling_price,price,discount_price,discount_threshold_kg,quantity,unit,is_available,created_at',
          )
          .eq('is_available', true)
          .gt('quantity', 0)
          .order('created_at', ascending: false);
    }

    return List<Map<String, dynamic>>.from(response as List);
  }

  Future<void> _loadHomeData() async {
    final responses = await Future.wait<dynamic>([
      _loadShops(),
      Supabase.instance.client.from('categories').select().order('name'),
      _loadPromotions(),
    ]);

    if (!mounted) return;
    setState(() {
      _shops = (responses[0] as List<dynamic>)
          .map((s) => Shop.fromJson(s as Map<String, dynamic>))
          .toList();
      if (_selectedShopId == null && _shops.isNotEmpty) {
        final freshMarket = _shops.cast<Shop?>().firstWhere(
          (shop) => shop!.name.trim().toLowerCase() == 'pafly',
          orElse: () => _shops.first,
        );
        _selectedShopId = freshMarket?.id;
      }
      _categories = (responses[1] as List<dynamic>)
          .map((c) => Category.fromJson(c))
          .toList();
      _promotions = (responses[2] as List<dynamic>)
          .map((p) => Promotion.fromJson(p))
          .toList();
    });
    _startBannerTimer();
  }

  Future<List<dynamic>> _loadShops() async {
    try {
      final shops = await Supabase.instance.client
          .from(AppConstants.shopsTable)
          .select()
          .eq('is_active', true)
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

  Future<List<dynamic>> _loadPromotions() async {
    try {
      final promos = await Supabase.instance.client
          .from('promotions')
          .select()
          .eq('is_active', true);
      return List<dynamic>.from(promos as List);
    } on PostgrestException catch (error) {
      final details = '${error.message} ${error.details} ${error.hint}'
          .toLowerCase();
      final missingPromotionsTable =
          error.code == 'PGRST205' ||
          error.code == '42P01' ||
          details.contains('public.promotions');
      if (!missingPromotionsTable) rethrow;
      return const [];
    }
  }

  void _precacheProductImages(List<Product> products) {
    final urls = products
        .map((product) => product.imageUrl.trim())
        .where((url) => url.isNotEmpty && _precacheQueuedImageUrls.add(url))
        .take(15)
        .toList();
    if (urls.isEmpty) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final url in urls) {
        unawaited(
          precacheImage(
            CachedNetworkImageProvider(url),
            context,
          ).catchError((_) {}),
        );
      }
    });
  }

  void _startBannerTimer() {
    _bannerTimer?.cancel();
    _bannerTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      if (_bannerPageController.hasClients) {
        final nextPage = (_bannerPageController.page?.round() ?? 0) + 1;
        _bannerPageController.animateToPage(
          nextPage,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _bannerPageController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _updateCart(String productId, double delta, double availableQty) {
    setState(() {
      final current = _cart[productId] ?? 0.0;
      final next = current + delta;
      if (next > availableQty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Only ${availableQty.toStringAsFixed(0)} ${delta > 0 ? (delta == 1 ? "piece" : "pieces") : "kg"} available.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      if (next <= 0) {
        _cart.remove(productId);
      } else {
        _cart[productId] = next;
      }
    });
    unawaited(_saveCartDraft());
  }

  Future<void> _restoreCartDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cartDraftKey);
    if (raw == null || raw.trim().isEmpty) return;

    try {
      final restored = <String, double>{};
      for (final part in raw.split(';')) {
        final entry = part.trim();
        if (entry.isEmpty) continue;
        final pieces = entry.split('|');
        if (pieces.length != 2) continue;
        final productId = pieces[0].trim();
        final quantity = double.tryParse(pieces[1].trim()) ?? 0;
        if (productId.isEmpty || quantity <= 0) continue;
        restored[productId] = quantity;
      }
      if (!mounted || restored.isEmpty) return;
      setState(() {
        _cart
          ..clear()
          ..addAll(restored);
      });
    } catch (_) {
      await prefs.remove(_cartDraftKey);
    }
  }

  Future<void> _saveCartDraft() async {
    final prefs = await SharedPreferences.getInstance();
    if (_cart.isEmpty) {
      await prefs.remove(_cartDraftKey);
      return;
    }

    final encoded = _cart.entries
        .map((entry) => '${entry.key}|${entry.value}')
        .join(';');
    await prefs.setString(_cartDraftKey, encoded);
  }

  Future<void> _clearCartDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cartDraftKey);
  }

  double _cartTotal(List<Product> products) {
    double total = 0;
    for (final entry in _cart.entries) {
      final product = products.cast<Product?>().firstWhere(
        (item) => item?.id == entry.key,
        orElse: () => null,
      );
      if (product != null) {
        total += product.effectivePriceFor(entry.value) * entry.value;
      }
    }
    return total;
  }

  int _cartItemCount() => _cart.length;

  Future<int?> _placeOrders({
    required String paymentMethod,
    required double deliveryFee,
    required double totalPrice,
    required List<Product> products,
  }) async {
    final name = widget.userProfile['name'] as String;
    final phone = widget.userProfile['phone'] as String;
    final location = widget.userProfile['location'] as String;
    final uid = widget.userProfile['id'] as String;
    final livePosition = LiveLocationService.instance.currentPosition.value;
    final readableLocation = LiveLocationService
        .instance
        .currentReadableLocation
        .value
        ?.trim();
    final deliveryLocationLabel =
        readableLocation != null && readableLocation.isNotEmpty
        ? readableLocation
        : livePosition == null
        ? location
        : 'Live GPS ${livePosition.latitude.toStringAsFixed(5)}, ${livePosition.longitude.toStringAsFixed(5)}';

    final navigator = Navigator.of(context, rootNavigator: true);
    var loadingDialogOpen = true;
    showDialog(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (_) =>
          const Center(child: CircularProgressIndicator(color: AppUi.primary)),
    );

    try {
      final List<Map<String, dynamic>> items = [];
      String orderDetails = '';
      for (final entry in _cart.entries) {
        final qty = entry.value;
        if (qty <= 0) continue;
        items.add({'product_id': entry.key, 'quantity_kg': qty});
        final product = products.firstWhere((p) => p.id == entry.key);
        final qtyStr = qty % 1 == 0
            ? qty.toInt().toString()
            : qty.toStringAsFixed(1);
        orderDetails += '$qtyStr${product.unit} ${product.name}, ';
      }
      if (orderDetails.endsWith(', ')) {
        orderDetails = orderDetails.substring(0, orderDetails.length - 2);
      }

      if (items.isEmpty) {
        return null;
      }

      final createdOrderId = await Supabase.instance.client
          .rpc(
            'place_grouped_order',
            params: {
              'customer_name_param': name,
              'phone_param': phone,
              'location_param': location,
              'items_json': items,
              'is_credit_param': false,
              'paid_amount_param': 0,
              'delivery_fee_param': deliveryFee,
              'payment_method_param': paymentMethod,
              'delivery_location_label_param': deliveryLocationLabel,
              'delivery_latitude_param': livePosition?.latitude,
              'delivery_longitude_param': livePosition?.longitude,
              'client_id_param': uid,
            },
          )
          .timeout(const Duration(seconds: 30));

      final orderId = (createdOrderId as num?)?.toInt();
      if (orderId != null) {
        unawaited(
          PushNotificationService.instance.notifyAdminsOfNewOrder(
            orderId: orderId,
            customerName: name,
            paymentMethod: paymentMethod,
            totalPrice: totalPrice,
            orderDetails: orderDetails,
          ),
        );
        unawaited(
          PushNotificationService.instance.notifyClientEvent(
            eventType: 'new_order',
            userId: uid,
            orderId: orderId,
            customerName: name,
            totalPrice: totalPrice,
          ),
        );
      }

      if (!mounted) return orderId;
      setState(() => _cart.clear());
      unawaited(_clearCartDraft());

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Order sent with $paymentMethod. Payment stays unpaid until admin confirms it.',
                ),
              ),
            ],
          ),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return orderId;
    } on TimeoutException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Order took too long to submit. Please try again.'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return null;
    } catch (e) {
      if (loadingDialogOpen && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        loadingDialogOpen = false;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error placing order: $e'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return null;
    } finally {
      if (loadingDialogOpen && navigator.canPop()) {
        navigator.pop();
      }
      loadingDialogOpen = false;
    }
  }

  Future<bool> _openMomoDialer(
    double totalAmount, {
    String? merchantCodeOverride,
  }) async {
    final amount = totalAmount.round();
    final fallbackMomoCode =
        LiveLocationService
            .instance
            .businessProfile
            .value
            ?.momoPayMerchantCode ??
        '';
    final merchantCode = merchantCodeOverride?.trim().isNotEmpty == true
        ? merchantCodeOverride!.trim()
        : fallbackMomoCode.isNotEmpty
        ? fallbackMomoCode
        : '775276';
    final ussdCode = '*182*8*1*$merchantCode*$amount#';
    final dialUri = Uri(scheme: 'tel', path: ussdCode);

    try {
      return await launchUrl(dialUri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  void _showCheckoutSheet(List<Product> products) {
    if (_cart.isEmpty) return;
    final selectedShop = _selectedShop;
    final isDesktop = MediaQuery.of(context).size.width >= 800;

    Widget buildSheet(BuildContext ctx) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.88,
              maxWidth: isDesktop ? 500 : double.infinity,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFFF7F6F3),
                borderRadius: isDesktop
                    ? BorderRadius.circular(32)
                    : const BorderRadius.vertical(top: Radius.circular(32)),
                boxShadow: isDesktop
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 24,
                          offset: const Offset(0, 12),
                        )
                      ]
                    : null,
              ),
              child: CartCheckoutSheet(
                cart: _cart,
                products: products,
                selectedShop: selectedShop,
                totalCost: _cartTotal(products),
                liveLocationService: LiveLocationService.instance,
                onSaveDraft: _saveCartDraft,
                onIncrease: (product) {
                  _updateCart(product.id, 1, product.quantity);
                },
                onDecrease: (product) {
                  _updateCart(product.id, -1, product.quantity);
                },
                onSubmit: (paymentMethod, deliveryFee, finalTotal) async {
                  if (paymentMethod == 'MoMo Pay') {
                    final launched = await _openMomoDialer(
                      finalTotal,
                      merchantCodeOverride: selectedShop?.momoPayMerchantCode,
                    );
                    if (!launched) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Could not open the MoMo dial screen on this device.',
                            ),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                      return null;
                    }
                  }

                  final orderId = await _placeOrders(
                    paymentMethod: paymentMethod,
                    deliveryFee: deliveryFee,
                    totalPrice: finalTotal,
                    products: products,
                  );
                  return orderId;
                },
              ),
            ),
          ),
        );

    if (isDesktop) {
      showDialog(
        context: context,
        builder: (dialogContext) => Center(
          child: Material(
            color: Colors.transparent,
            child: buildSheet(dialogContext),
          ),
        ),
      );
    } else {
      showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) => buildSheet(sheetContext),
      );
    }
  }

  Promotion? get _currentPromotion {
    if (_promotions.isEmpty) return null;
    return _promotions[_bannerPage % _promotions.length];
  }

  List<Product> _visibleProducts(List<Product> allProducts) {
    var products = allProducts
        .where((product) => product.quantity > 0)
        .toList();
    if (_selectedCategory != null) {
      products = products
          .where((product) => product.categoryId == _selectedCategory)
          .toList();
    }
    final query = _searchQuery.trim().toLowerCase();
    if (query.isNotEmpty) {
      products = products.where((product) {
        final categoryName = _categoryNameForProduct(product).toLowerCase();
        return product.name.toLowerCase().contains(query) ||
            product.description.toLowerCase().contains(query) ||
            categoryName.contains(query);
      }).toList();
    }
    return products;
  }

  double? _bestDiscount(List<Product> products) {
    double? best;
    for (final product in products) {
      if (!product.hasDiscount) continue;
      final percentage = (1 - (product.discountPrice! / product.price)) * 100;
      if (best == null || percentage > best) {
        best = percentage;
      }
    }
    return best;
  }

  String _heroArtworkUrl(List<Product> products, Promotion? promotion) {
    if (promotion != null && promotion.imageUrl.isNotEmpty) {
      return promotion.imageUrl;
    }
    for (final product in products) {
      if (product.imageUrl.isNotEmpty) {
        return product.imageUrl;
      }
    }
    return '';
  }

  String _deliveryLocationLabel(Position? position) {
    final state = LiveLocationService.instance.trackingState.value;
    final readable = LiveLocationService.instance.currentReadableLocation.value
        ?.trim();

    if (readable != null && readable.isNotEmpty) {
      return readable;
    }

    if (state.status == LiveLocationTrackingStatus.loading) {
      return 'Locating...';
    }

    if (position != null) {
      return 'Live GPS (${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)})';
    }

    final fallback = widget.userProfile['location']?.toString().trim();
    if (fallback != null && fallback.isNotEmpty) {
      return fallback;
    }

    return 'Set delivery location';
  }

  String _categoryNameForProduct(Product product) {
    if (product.categoryId == null) return 'PAFLY';
    for (final category in _categories) {
      if (category.id == product.categoryId) return category.name;
    }
    return 'PAFLY';
  }

  Shop? get _selectedShop {
    final shopId = _selectedShopId;
    if (shopId == null) return null;
    for (final shop in _shops) {
      if (shop.id == shopId) return shop;
    }
    return null;
  }

  List<Product> _productsForSelectedShop(List<Product> products) {
    final shopId = _selectedShopId;
    if (shopId == null) return products;
    return products.where((product) => product.shopId == shopId).toList();
  }

  String get _activeSearchQuery => _searchQuery.trim();

  String _productBadgeText(Product product) {
    if (product.hasDiscount) {
      final basePrice = product.price <= 0 ? 1 : product.price;
      final discountPercent = ((1 - (product.discountPrice! / basePrice)) * 100)
          .round();
      return '-$discountPercent%';
    }
    return _categoryNameForProduct(product);
  }

  Color _categoryColor(int index) {
    const palette = [
      Color(0xFFFFF0D5),
      Color(0xFFE2F4D8),
      Color(0xFFFFF1C9),
      Color(0xFFFFDEE0),
      Color(0xFFDDF3FF),
    ];
    return palette[index % palette.length];
  }

  IconData _categoryIcon(String label) {
    final name = label.toLowerCase();
    if (name.contains('fruit')) {
      return Icons.spa_outlined;
    }
    if (name.contains('veget')) {
      return Icons.eco_outlined;
    }
    if (name.contains('dairy')) {
      return Icons.icecream_outlined;
    }
    if (name.contains('meat')) {
      return Icons.set_meal_outlined;
    }
    if (name.contains('bread') || name.contains('bak')) {
      return Icons.bakery_dining_outlined;
    }
    return Icons.shopping_basket_outlined;
  }

  void _showHeroHint() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Browse today\'s fresh deals below.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 800;
    final sidePadding = isDesktop ? (width - 1100).clamp(0.0, width) / 2 : 0.0;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7EF),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _productsFuture,
        builder: (context, snapshot) {
          final allProducts = (snapshot.data ?? [])
              .map((item) => Product.fromJson(item))
              .where((product) => product.isAvailable)
              .toList();
          _precacheProductImages(allProducts);
          final shopProducts = _productsForSelectedShop(allProducts);
          final products = _visibleProducts(shopProducts);
          final productsWithImages = shopProducts
              .where((product) => product.imageUrl.isNotEmpty)
              .take(5)
              .toList();
          final promotion = _currentPromotion;
          final bestDiscount = _bestDiscount(shopProducts);
          final heroImageUrl = _heroArtworkUrl(shopProducts, promotion);
          final selectedShop = _selectedShop;

          return Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFFF7FAF2),
                        const Color(0xFFEAF4DF),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ),
              CustomScrollView(
                slivers: [
                  if (kIsWeb)
                    SliverToBoxAdapter(
                      child: StreamBuilder<bool>(
                        stream: PwaService.instance.installableStream,
                        initialData: PwaService.instance.isInstallable,
                        builder: (context, snapshot) {
                          if (snapshot.data != true) return const SizedBox.shrink();
                          return Container(
                            margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: AppUi.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: AppUi.primary.withValues(alpha: 0.2)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.install_mobile_rounded, color: AppUi.primary),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Install PAFLY App',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                      Text(
                                        'Install on your home screen for quick access.',
                                        style: TextStyle(fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => PwaService.instance.triggerInstall(),
                                  style: TextButton.styleFrom(
                                    foregroundColor: AppUi.primary,
                                    textStyle: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  child: const Text('INSTALL'),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  SliverToBoxAdapter(
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  height: 90,
                                  width: 90,
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(26),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.08,
                                        ),
                                        blurRadius: 24,
                                        offset: const Offset(0, 10),
                                      ),
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(22),
                                    child: Image.asset(
                                      'assets/logo.png',
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        selectedShop?.name ?? 'PAFLY',
                                        style: const TextStyle(
                                          fontSize: 34,
                                          fontWeight: FontWeight.w900,
                                          color: Color(0xFF256B34),
                                          letterSpacing: -0.8,
                                        ),
                                      ),
                                      Text(
                                        selectedShop?.description
                                                    .trim()
                                                    .isNotEmpty ==
                                                true
                                            ? selectedShop!.description
                                            : 'Fresh groceries delivered fast',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey.shade600,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    InkWell(
                                      borderRadius: BorderRadius.circular(20),
                                      onTap: _cart.isNotEmpty
                                          ? () =>
                                                _showCheckoutSheet(shopProducts)
                                          : null,
                                      child: Container(
                                        height: 52,
                                        width: 52,
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(
                                            26,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withValues(
                                                alpha: 0.07,
                                              ),
                                              blurRadius: 20,
                                              offset: const Offset(0, 8),
                                            ),
                                          ],
                                        ),
                                        child: const Icon(
                                          Icons.shopping_cart_outlined,
                                          color: AppUi.primary,
                                          size: 26,
                                        ),
                                      ),
                                    ),
                                    if (_cart.isNotEmpty)
                                      Positioned(
                                        top: -3,
                                        right: -3,
                                        child: Container(
                                          height: 22,
                                          width: 22,
                                          decoration: const BoxDecoration(
                                            color: Color(0xFF7AC143),
                                            shape: BoxShape.circle,
                                          ),
                                          alignment: Alignment.center,
                                          child: Text(
                                            '${_cartItemCount()}',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            if (_shops.length > 1) ...[
                              SizedBox(
                                height: 48,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: _shops.length,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(width: 8),
                                  itemBuilder: (context, index) {
                                    final shop = _shops[index];
                                    final selected = shop.id == _selectedShopId;
                                    return ChoiceChip(
                                      selected: selected,
                                      label: Text(shop.name),
                                      avatar: Icon(
                                        selected
                                            ? Icons.storefront_rounded
                                            : Icons.storefront_outlined,
                                        size: 18,
                                      ),
                                      onSelected: (_) => setState(() {
                                        if (_selectedShopId != shop.id) {
                                          _cart.clear();
                                          unawaited(_clearCartDraft());
                                        }
                                        _selectedShopId = shop.id;
                                        _selectedCategory = null;
                                      }),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(height: 14),
                            ],
                            // INTEGRATED HEADER: Location and Search combined
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(26),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.06),
                                    blurRadius: 20,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: Column(
                                children: [
                                  // Subtle Location Row
                                  ValueListenableBuilder<Position?>(
                                    valueListenable: LiveLocationService
                                        .instance
                                        .currentPosition,
                                    builder: (context, position, _) {
                                      return ValueListenableBuilder<String?>(
                                        valueListenable: LiveLocationService
                                            .instance
                                            .currentReadableLocation,
                                        builder: (context, readableLocation, _) => InkWell(
                                          onTap: () {
                                            LiveLocationService.instance.startTracking(
                                              userId:
                                                  widget.userProfile['id'] ??
                                                  '',
                                              customerName:
                                                  widget.userProfile['name'] ??
                                                  '',
                                              phone:
                                                  widget.userProfile['phone'] ??
                                                  '',
                                              locationLabel:
                                                  widget
                                                      .userProfile['location'] ??
                                                  '',
                                            );
                                          },
                                          borderRadius:
                                              const BorderRadius.vertical(
                                                top: Radius.circular(26),
                                              ),
                                          child: Padding(
                                            padding: const EdgeInsets.fromLTRB(
                                              16,
                                              14,
                                              16,
                                              10,
                                            ),
                                            child: Row(
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.all(
                                                    6,
                                                  ),
                                                  decoration:
                                                      const BoxDecoration(
                                                        color: Color(
                                                          0xFFEAF5E3,
                                                        ),
                                                        shape: BoxShape.circle,
                                                      ),
                                                  child: const Icon(
                                                    Icons.location_on,
                                                    color: AppUi.primary,
                                                    size: 14,
                                                  ),
                                                ),
                                                const SizedBox(width: 10),
                                                Expanded(
                                                  child: Text(
                                                    _deliveryLocationLabel(
                                                      position,
                                                    ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: Color(0xFF415144),
                                                    ),
                                                  ),
                                                ),
                                                Icon(
                                                  Icons.chevron_right,
                                                  size: 18,
                                                  color: Colors.grey.shade400,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                  Divider(
                                    height: 1,
                                    thickness: 1,
                                    color: Colors.grey.shade100,
                                    indent: 16,
                                    endIndent: 16,
                                  ),
                                  // Integrated Search Bar
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                    child: TextField(
                                      controller: _searchController,
                                      onChanged: (value) => setState(() {
                                        _searchQuery = value;
                                      }),
                                      textInputAction: TextInputAction.search,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      decoration: InputDecoration(
                                        border: InputBorder.none,
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 14,
                                            ),
                                        prefixIcon: const Icon(
                                          Icons.search_rounded,
                                          color: AppUi.primary,
                                          size: 22,
                                        ),
                                        hintText: 'Search fresh groceries...',
                                        hintStyle: TextStyle(
                                          color: Colors.grey.shade400,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        suffixIcon: _activeSearchQuery.isEmpty
                                            ? null
                                            : IconButton(
                                                onPressed: () => setState(() {
                                                  _searchController.clear();
                                                  _searchQuery = '';
                                                }),
                                                icon: const Icon(
                                                  Icons.close_rounded,
                                                  color: Color(0xFF6F7F72),
                                                  size: 20,
                                                ),
                                              ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                            SizedBox(
                              height: 220,
                              child: productsWithImages.isEmpty
                                  ? FreshMarketHeroCard(
                                      title:
                                          'Get Your Groceries Delivered Fresh!',
                                      subtitle:
                                          promotion?.title.isNotEmpty == true
                                          ? promotion!.title
                                          : 'Fast delivery for fruits, vegetables, dairy and daily essentials.',
                                      badgeText: bestDiscount != null
                                          ? '${bestDiscount.round()}% OFF'
                                          : 'Fresh Picks',
                                      imageUrl: heroImageUrl,
                                      onPressed: _showHeroHint,
                                    )
                                  : PageView.builder(
                                      controller: _bannerPageController,
                                      onPageChanged: (index) {
                                        setState(() {
                                          _bannerPage =
                                              index % productsWithImages.length;
                                        });
                                      },
                                      itemBuilder: (context, index) {
                                        final product =
                                            productsWithImages[index %
                                                productsWithImages.length];
                                        return FreshMarketProductHeroCard(
                                          product: product,
                                          onTap: _showHeroHint,
                                        );
                                      },
                                    ),
                            ),
                            if (productsWithImages.length > 1) ...[
                              const SizedBox(height: 10),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: List.generate(
                                  productsWithImages.length,
                                  (index) => AnimatedContainer(
                                    duration: const Duration(milliseconds: 250),
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 3,
                                    ),
                                    height: 6,
                                    width: _bannerPage == index ? 24 : 6,
                                    decoration: BoxDecoration(
                                      color: _bannerPage == index
                                          ? AppUi.primary
                                          : Colors.grey.shade300,
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                            if (_categories.isNotEmpty) ...[
                              const SizedBox(height: 18),
                              Row(
                                children: [
                                  const Text(
                                    'Shop by Category',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFF26352A),
                                      letterSpacing: -0.4,
                                    ),
                                  ),
                                  const Spacer(),
                                  TextButton(
                                    onPressed: () => setState(
                                      () => _selectedCategory = null,
                                    ),
                                    style: TextButton.styleFrom(
                                      foregroundColor: AppUi.primary,
                                      padding: EdgeInsets.zero,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    child: const Text(
                                      'See All',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              SizedBox(
                                height: 92,
                                child: ListView.builder(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: _categories.length,
                                  itemBuilder: (context, index) {
                                    final category = _categories[index];
                                    final isSelected =
                                        _selectedCategory == category.id;
                                    return GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          _selectedCategory = isSelected
                                              ? null
                                              : category.id;
                                        });
                                      },
                                      child: FreshMarketCategoryChip(
                                        label: category.name,
                                        imageUrl: category.imageUrl,
                                        isSelected: isSelected,
                                        accentColor: _categoryColor(index),
                                        icon: _categoryIcon(category.name),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                            const SizedBox(height: 18),
                          ],
                        ),
                      ),
                    ),
                  ),
                    if (snapshot.hasError)
                      SliverPadding(
                        padding: EdgeInsets.symmetric(
                          horizontal: isDesktop ? sidePadding : 20,
                        ),
                        sliver: SliverToBoxAdapter(
                          child: Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.05),
                                  blurRadius: 18,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: const Column(
                              children: [
                                Icon(Icons.cloud_off_rounded, color: AppUi.primary, size: 38),
                                SizedBox(height: 12),
                                Text(
                                  'We could not load fresh deals right now.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                                ),
                                SizedBox(height: 6),
                                Text(
                                  'Please refresh the page or try again later.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.grey, height: 1.4),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    else if (snapshot.connectionState == ConnectionState.waiting && snapshot.data == null)
                      SliverPadding(
                        padding: EdgeInsets.symmetric(
                          horizontal: isDesktop ? sidePadding : 18,
                        ),
                        sliver: SliverGrid(
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                            mainAxisExtent: 260,
                          ),
                          delegate: SliverChildBuilderDelegate((context, index) {
                            return Shimmer.fromColors(
                              baseColor: Colors.white,
                              highlightColor: Colors.grey.shade50,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(24),
                                ),
                              ),
                            );
                          }, childCount: 6),
                        ),
                      )
                    else if (products.isEmpty)
                      SliverPadding(
                        padding: EdgeInsets.symmetric(
                          horizontal: isDesktop ? sidePadding : 20,
                        ),
                        sliver: SliverToBoxAdapter(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(28),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.05),
                                  blurRadius: 18,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                Container(
                                  height: 72,
                                  width: 72,
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF2F8EC),
                                    borderRadius: BorderRadius.circular(22),
                                  ),
                                  child: Image.asset('assets/logo.png'),
                                ),
                                const SizedBox(height: 18),
                                Text(
                                  _activeSearchQuery.isNotEmpty
                                      ? 'No products matched "$_activeSearchQuery".'
                                      : 'No deals available in this category yet.',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _activeSearchQuery.isNotEmpty
                                      ? 'Try a different product name, category, or switch to another shop.'
                                      : 'PAFLY will show matching products here as soon as they are available.',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.grey, height: 1.4),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: EdgeInsets.symmetric(
                          horizontal: isDesktop ? sidePadding : 18,
                        ),
                        sliver: SliverGrid(
                          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 260,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                            mainAxisExtent: 262,
                          ),
                          delegate: SliverChildBuilderDelegate((context, index) {
                            final product = products[index];
                            final qtyInCart = _cart[product.id] ?? 0.0;
                            return FreshMarketProductCard(
                              product: product,
                              qtyInCart: qtyInCart,
                              badgeText: _productBadgeText(product),
                              onAdd: () => _updateCart(product.id, 1, product.quantity),
                              onRemove: () => _updateCart(product.id, -1, product.quantity),
                            );
                          }, childCount: products.length),
                        ),
                      ),
                    const SliverToBoxAdapter(child: SizedBox(height: 120)),
                  ],
                ),
              ],
            );
          },
        ),
      );
  }
}

class CartCheckoutSheet extends StatefulWidget {
  final Map<String, double> cart;
  final List<Product> products;
  final Shop? selectedShop;
  final double totalCost;
  final LiveLocationService liveLocationService;
  final Future<void> Function() onSaveDraft;
  final ValueChanged<Product> onIncrease;
  final ValueChanged<Product> onDecrease;
  final Future<int?> Function(
    String paymentMethod,
    double deliveryFee,
    double finalTotal,
  )
  onSubmit;

  const CartCheckoutSheet({
    super.key,
    required this.cart,
    required this.products,
    required this.selectedShop,
    required this.totalCost,
    required this.liveLocationService,
    required this.onSaveDraft,
    required this.onIncrease,
    required this.onDecrease,
    required this.onSubmit,
  });

  @override
  State<CartCheckoutSheet> createState() => _CartCheckoutSheetState();
}

class _CartCheckoutSheetState extends State<CartCheckoutSheet> {
  bool _isSubmitting = false;
  bool _isLoadingDelivery = true;
  double? _distanceKm;
  double _deliveryFee = 0;

  final _promoCtrl = TextEditingController();
  Map<String, dynamic>? _appliedPromo;
  String? _promoError;
  bool _isVerifyingPromo = false;

  BusinessProfile get _checkoutProfile {
    final shop = widget.selectedShop;
    final globalProfile =
        widget.liveLocationService.businessProfile.value ??
        BusinessProfile.fallback();

    // If no specific shop or it's the main 'PAFLY' shop,
    // use the Global Business Profile (which is updated in real-time by Admin).
    if (shop == null || shop.name.trim().toLowerCase() == 'pafly') {
      return globalProfile;
    }

    return BusinessProfile(
      id: 1,
      businessName: shop.name.trim().isEmpty
          ? AppConstants.defaultBusinessName
          : shop.name.trim(),
      email: '',
      phone: shop.phone,
      location: shop.location,
      addressLine: shop.addressLine,
      latitude: shop.latitude,
      longitude: shop.longitude,
      momoPayMerchantCode: shop.momoPayMerchantCode,
      deliveryBaseFee: shop.deliveryBaseFee,
      deliveryDistanceThresholdKm: shop.deliveryDistanceThresholdKm,
      deliveryExtraKmFee: shop.deliveryExtraKmFee,
      deliveryOrderThreshold: shop.deliveryOrderThreshold,
      deliveryExtraOrderPercent: shop.deliveryExtraOrderPercent,
    );
  }

  @override
  void initState() {
    super.initState();
    widget.liveLocationService.businessProfile.addListener(
      _loadDeliveryEstimate,
    );
    _deliveryFee = calculateDeliveryFee(
      distanceKm: 0,
      orderAmount: _subtotal,
      profile: _checkoutProfile,
    );
    _loadDeliveryEstimate();
  }

  @override
  void dispose() {
    widget.liveLocationService.businessProfile.removeListener(
      _loadDeliveryEstimate,
    );
    _promoCtrl.dispose();
    super.dispose();
  }

  Future<void> _verifyPromo() async {
    final code = _promoCtrl.text.trim().toUpperCase();
    if (code.isEmpty) return;

    setState(() {
      _isVerifyingPromo = true;
      _promoError = null;
    });

    try {
      final now = DateTime.now().toUtc().toIso8601String();
      final response = await Supabase.instance.client
          .from('promo_codes')
          .select()
          .eq('code', code)
          .eq('is_active', true)
          .or('expiry_date.is.null,expiry_date.gt.$now')
          .maybeSingle();

      if (!mounted) return;

      if (response == null) {
        setState(() {
          _promoError = 'Invalid or expired code';
          _appliedPromo = null;
          _isVerifyingPromo = false;
        });
        return;
      }

      final maxUses = response['max_uses_per_user'] as int?;
      if (maxUses != null) {
        final userId = Supabase.instance.client.auth.currentUser?.id;
        if (userId != null) {
          final usage = await Supabase.instance.client
              .from('promo_code_usage')
              .select('id')
              .eq('promo_code_id', response['id'])
              .eq('user_id', userId);
          if ((usage as List).length >= maxUses) {
            setState(() {
              _promoError = 'Usage limit reached';
              _appliedPromo = null;
              _isVerifyingPromo = false;
            });
            return;
          }
        }
      }

      // Check minimum purchase amount
      final minPurchase = (response['min_purchase_amount'] as num?)?.toDouble() ?? 0;
      if (minPurchase > 0 && _subtotal < minPurchase) {
        setState(() {
          _promoError = 'Min purchase of ${minPurchase.toStringAsFixed(0)} Frw required';
          _appliedPromo = null;
          _isVerifyingPromo = false;
        });
        return;
      }

      setState(() {
        _appliedPromo = response;
        _promoError = null;
        _isVerifyingPromo = false;
      });
      if (!mounted) return;
      FocusScope.of(context).unfocus();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _promoError = 'Error verifying code';
        _appliedPromo = null;
        _isVerifyingPromo = false;
      });
    }
  }

  List<_CartSheetLineItem> get _items {
    final list = <_CartSheetLineItem>[];
    for (final entry in widget.cart.entries) {
      if (entry.value <= 0) continue;
      final product = widget.products.cast<Product?>().firstWhere(
        (item) => item?.id == entry.key,
        orElse: () => null,
      );
      if (product != null) {
        list.add(_CartSheetLineItem(product: product, quantity: entry.value));
      }
    }
    return list;
  }

  String _merchantLabel(Product product) {
    final label = product.name.trim();
    return label.isEmpty ? 'PAFLY' : label;
  }

  double _lineTotal(_CartSheetLineItem item) =>
      item.product.effectivePriceFor(item.quantity) * item.quantity;

  double get _subtotal {
    double total = 0;
    for (final entry in widget.cart.entries) {
      if (entry.value <= 0) continue;
      final product = widget.products.cast<Product?>().firstWhere(
        (item) => item?.id == entry.key,
        orElse: () => null,
      );
      if (product != null) {
        total += product.effectivePriceFor(entry.value) * entry.value;
      }
    }
    return total;
  }

  double get _discountAmount {
    if (_appliedPromo == null) return 0;
    final type = _appliedPromo!['type'];
    final value = _appliedPromo!['value'] as num? ?? 0;
    
    if (type == 'free_delivery') {
      return _deliveryFee;
    } else if (type == 'discount_fixed') {
      return value.toDouble();
    } else if (type == 'discount_percent') {
      return _subtotal * (value.toDouble() / 100.0);
    }
    return 0;
  }

  double get _finalTotal {
    final t = _subtotal + _deliveryFee - _discountAmount;
    return t < 0 ? 0 : t;
  }

  Future<void> _loadDeliveryEstimate() async {
    if (!mounted) return;

    // If we already have a distance, we can quickly re-calculate the fee
    // without doing another GPS lookup if the profile changes.
    if (_distanceKm != null) {
      final nextDeliveryFee = calculateDeliveryFee(
        distanceKm: _distanceKm!,
        orderAmount: _subtotal,
        profile: _checkoutProfile,
      );
      setState(() {
        _deliveryFee = nextDeliveryFee;
        _isLoadingDelivery = false;
      });
    } else {
      setState(() => _isLoadingDelivery = true);
    }

    final profile = _checkoutProfile;
    final distanceKm = profile.latitude != null && profile.longitude != null
        ? await widget.liveLocationService.getDistanceToCoordinates(
            latitude: profile.latitude!,
            longitude: profile.longitude!,
          )
        : await widget.liveLocationService.getDistanceToStoreKm();

    final nextDeliveryFee = calculateDeliveryFee(
      distanceKm: distanceKm ?? 0,
      orderAmount: _subtotal,
      profile: profile,
    );

    if (!mounted) return;
    setState(() {
      _distanceKm = distanceKm;
      _deliveryFee = nextDeliveryFee;
      _isLoadingDelivery = false;
    });
  }

  Future<String?> _askForPaymentMethod() {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
        contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        title: const Text(
          'Choose Payment Method',
          style: TextStyle(fontWeight: FontWeight.w900, color: AppUi.dark),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Select Cash or MoMo Pay before the order is sent. The order stays unpaid until admin confirms payment.',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 18),
            _CheckoutPaymentOption(
              label: 'Cash',
              subtitle:
                  'Send the order now and let admin confirm the payment later.',
              icon: Icons.payments_outlined,
              onTap: () => Navigator.pop(dialogContext, 'Cash'),
            ),
            const SizedBox(height: 12),
            _CheckoutPaymentOption(
              label: 'MoMo Pay',
              subtitle:
                  'Open the phone dial screen for MoMo payment, then send the order as unpaid.',
              icon: Icons.phone_android_rounded,
              onTap: () => Navigator.pop(dialogContext, 'MoMo Pay'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final paymentMethod = await _askForPaymentMethod();
    if (paymentMethod == null) return;

    setState(() => _isSubmitting = true);
    final orderId = await widget.onSubmit(
      paymentMethod,
      _deliveryFee,
      _finalTotal,
    );
    
    if (orderId != null && _appliedPromo != null) {
      try {
        await Supabase.instance.client.rpc(
          'apply_promo_code_to_order',
          params: {
            'p_order_id': orderId,
            'p_promo_code_id': _appliedPromo!['id'],
          },
        );
      } catch (e) {
        // Fail silently or show warning if promo couldn't apply
      }
    }

    if (!mounted) return;

    setState(() => _isSubmitting = false);
    if (orderId != null) {
      Navigator.pop(context);
    }
  }

  Future<void> _saveDraft() async {
    FocusScope.of(context).unfocus();
    await widget.onSaveDraft();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Cart draft saved. You can continue later.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final businessName = _checkoutProfile.businessName;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      child: Column(
        children: [
          Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppUi.dark,
                ),
              ),
              const Expanded(
                child: Text(
                  'My Cart',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: AppUi.dark,
                  ),
                ),
              ),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.shopping_bag_outlined,
                  color: AppUi.primary,
                  size: 20,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: ListView(
              children: [
                ...items.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _CartProductCard(
                      item: item,
                      merchantLabel: _merchantLabel(item.product),
                      lineTotal: _lineTotal(item),
                      onIncrease: () {
                        widget.onIncrease(item.product);
                        if (mounted) {
                          setState(() {});
                          unawaited(_loadDeliveryEstimate());
                        }
                      },
                      onDecrease: () {
                        widget.onDecrease(item.product);
                        if (widget.cart.isEmpty && mounted) {
                          Navigator.pop(context);
                          return;
                        }
                        if (mounted) {
                          setState(() {});
                          unawaited(_loadDeliveryEstimate());
                        }
                      },
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      _CheckoutSummaryRow(
                        label: 'Subtotal',
                        value: '${_subtotal.toStringAsFixed(0)} Frw',
                      ),
                      const SizedBox(height: 8),
                      _CheckoutSummaryRow(
                        label: 'Delivery Fee',
                        value: _isLoadingDelivery
                            ? 'Calculating...'
                            : '${_deliveryFee.toStringAsFixed(0)} Frw',
                      ),
                      if (!_isLoadingDelivery)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              _distanceKm == null
                                  ? 'Using base delivery fee (${_checkoutProfile.deliveryBaseFee.toStringAsFixed(0)} Frw) because GPS distance is unavailable.'
                                  : (_distanceKm! <=
                                        _checkoutProfile
                                            .deliveryDistanceThresholdKm)
                                  ? 'Within ${_checkoutProfile.deliveryDistanceThresholdKm.toStringAsFixed(0)}km: Base fee of ${_checkoutProfile.deliveryBaseFee.toStringAsFixed(0)} Frw applied.'
                                  : 'Distance: ${_distanceKm!.toStringAsFixed(1)} km from $businessName (Base + Extra Km applied).',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 10),
                      ValueListenableBuilder<Position?>(
                        valueListenable:
                            widget.liveLocationService.currentPosition,
                        builder: (context, position, _) {
                          return ValueListenableBuilder<String?>(
                            valueListenable: widget
                                .liveLocationService
                                .currentReadableLocation,
                            builder: (context, readableLocation, _) {
                              final label =
                                  readableLocation != null &&
                                      readableLocation.trim().isNotEmpty
                                  ? readableLocation
                                  : position == null
                                  ? 'Using saved delivery address from profile.'
                                  : 'Live GPS: ${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}';
                              return Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF6F9EF),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: const Color(0xFFE1EAD8),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 30,
                                      height: 30,
                                      decoration: BoxDecoration(
                                        color: const Color(0x1A66BB6A),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(
                                        Icons.my_location_rounded,
                                        color: AppUi.primary,
                                        size: 16,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Delivery point',
                                            style: TextStyle(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w800,
                                              color: AppUi.dark,
                                            ),
                                          ),
                                          const SizedBox(height: 1),
                                          Text(
                                            label,
                                            style: TextStyle(
                                              color: Colors.grey.shade700,
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          );
                        },
                      ),
                      if (_discountAmount > 0) ...[
                        const SizedBox(height: 8),
                        _CheckoutSummaryRow(
                          label: 'Discount (${_appliedPromo!['code']})',
                          value: '-${_discountAmount.toStringAsFixed(0)} Frw',
                          valueColor: AppUi.primary,
                        ),
                      ],
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: Divider(height: 1),
                      ),
                      _CheckoutSummaryRow(
                        label: 'Total',
                        value: '${_finalTotal.toStringAsFixed(0)} Frw',
                        isEmphasized: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _promoCtrl,
                              decoration: InputDecoration(
                                hintText: 'Enter Promo Code',
                                hintStyle: TextStyle(
                                  color: Colors.grey.shade400,
                                  fontSize: 14,
                                ),
                                border: InputBorder.none,
                                icon: const Icon(
                                  Icons.local_offer_outlined,
                                  color: AppUi.primary,
                                ),
                              ),
                              textCapitalization: TextCapitalization.characters,
                              onSubmitted: (_) => _verifyPromo(),
                            ),
                          ),
                          TextButton(
                            onPressed: _isVerifyingPromo ? null : _verifyPromo,
                            child: _isVerifyingPromo
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text(
                                    'Apply',
                                    style: TextStyle(
                                      color: AppUi.primary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ],
                      ),
                      if (_promoError != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4, bottom: 4),
                          child: Text(
                            _promoError!,
                            style: TextStyle(
                              color: Colors.red.shade700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      if (_appliedPromo != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4, bottom: 4),
                          child: Text(
                            'Promo applied: ${_appliedPromo!['code']}',
                            style: const TextStyle(
                              color: AppUi.primary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isSubmitting ? null : _saveDraft,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppUi.primary,
                    side: const BorderSide(color: AppUi.primary),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text(
                    'Save Draft',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppUi.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.4,
                            ),
                          )
                        : const Text(
                            'Proceed',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CartSheetLineItem {
  final Product product;
  final double quantity;

  const _CartSheetLineItem({required this.product, required this.quantity});
}

class _CartProductCard extends StatelessWidget {
  final _CartSheetLineItem item;
  final String merchantLabel;
  final double lineTotal;
  final VoidCallback onIncrease;
  final VoidCallback onDecrease;

  const _CartProductCard({
    required this.item,
    required this.merchantLabel,
    required this.lineTotal,
    required this.onIncrease,
    required this.onDecrease,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: SizedBox(
              width: 56,
              height: 56,
              child: Image.network(
                item.product.imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  color: const Color(0xFFF2F7EC),
                  padding: const EdgeInsets.all(10),
                  child: Image.asset('assets/logo.png'),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppUi.dark,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  merchantLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${lineTotal.toStringAsFixed(0)} Frw',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: AppUi.dark,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 7),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F4EE),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _QtyActionButton(icon: Icons.remove_rounded, onTap: onDecrease),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 7),
                  child: Text(
                    qtyLabel(item.quantity, item.product.unit),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 11.5,
                    ),
                  ),
                ),
                _QtyActionButton(
                  icon: Icons.add_rounded,
                  onTap: onIncrease,
                  isAdd: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QtyActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool isAdd;

  const _QtyActionButton({
    required this.icon,
    required this.onTap,
    this.isAdd = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: isAdd ? const Color(0xFFE3F3DD) : Colors.white,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 15, color: isAdd ? AppUi.primary : AppUi.dark),
      ),
    );
  }
}

class _CheckoutPaymentOption extends StatelessWidget {
  final String label;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _CheckoutPaymentOption({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF7F7F3),
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: Padding(
          padding: const EdgeInsets.all(11),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF6E6),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, color: AppUi.primary, size: 20),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: AppUi.dark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 11,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppUi.primary),
            ],
          ),
        ),
      ),
    );
  }
}

class _CheckoutSummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isEmphasized;
  final Color? valueColor;

  const _CheckoutSummaryRow({
    required this.label,
    required this.value,
    this.isEmphasized = false,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final style = isEmphasized
        ? const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: AppUi.dark,
          )
        : TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade700,
          );

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: style),
        Text(
          value,
          style: valueColor != null ? style.copyWith(color: valueColor) : style,
        ),
      ],
    );
  }
}

// ==========================================
// MY ORDERS TAB
// ==========================================

class _ClientOrdersTab extends StatefulWidget {
  final String userId;
  const _ClientOrdersTab({required this.userId});

  @override
  State<_ClientOrdersTab> createState() => _ClientOrdersTabState();
}

class _ClientOrdersTabState extends State<_ClientOrdersTab> {
  late Future<List<Order>> _ordersFuture;

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  void _loadOrders() {
    setState(() {
      _ordersFuture = _fetchOrders();
    });
  }

  Future<void> _cancelOrder(Order order) async {
    if (order.status == 'Cancelled' || order.status == 'Completed') {
      return;
    }
    if (order.paidAmount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This order already has a payment and cannot be cancelled here.',
          ),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final reasonController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    try {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Cancel order'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cancel order #${order.id} for ${order.displayProductName}? This will notify the admin.',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: reasonController,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Cancel reason',
                    hintText:
                        'Tell the admin why you are cancelling this order',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please add a reason';
                    }
                    if (value.trim().length < 5) {
                      return 'Add a little more detail';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Keep order'),
            ),
            FilledButton(
              onPressed: () {
                if (!(formKey.currentState?.validate() ?? false)) {
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Cancel order'),
            ),
          ],
        ),
      );

      if (confirm != true) return;

      await Supabase.instance.client.rpc(
        AppConstants.cancelOrderRpc,
        params: {
          'target_order_id': order.id,
          'cancel_reason_param': reasonController.text.trim(),
        },
      );
      unawaited(
        PushNotificationService.instance.notifyAdminsOfOrderEvent(
          eventType: 'order_cancelled',
          orderId: order.id,
          customerName: order.clientName,
          paymentMethod: order.paymentMethod ?? 'Cash',
          totalPrice: order.totalPrice,
          cancelReason: reasonController.text.trim(),
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Order #${order.id} cancelled and the admin was notified.',
          ),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
      _loadOrders();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to cancel order: $error'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      reasonController.dispose();
    }
  }

  Future<List<Order>> _fetchOrders() async {
    final response = await Supabase.instance.client
        .from('orders')
        .select('*, order_items(*, products(image_url))')
        .eq('client_id', widget.userId)
        .order('created_at', ascending: false);
    return (response as List<dynamic>)
        .map((json) => Order.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Order History'),
        backgroundColor: Colors.white,
        foregroundColor: AppUi.dark,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadOrders,
            tooltip: 'Refresh',
          ),
        ],
      ),
      backgroundColor: Colors.grey.shade50,
      body: FutureBuilder<List<Order>>(
        future: _ordersFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            final err = snapshot.error.toString().toLowerCase();
            final isNet =
                err.contains('socket') ||
                err.contains('host') ||
                err.contains('connection');
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isNet ? Icons.wifi_off : Icons.error_outline,
                    size: 48,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    isNet ? 'No internet connection' : 'Error loading orders',
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _loadOrders,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          final orders = snapshot.data ?? [];

          if (orders.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.shopping_bag_outlined,
                    size: 64,
                    color: Colors.grey.shade300,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No orders yet.',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => _loadOrders(),
            child: ListView.builder(
              itemCount: orders.length,
              padding: const EdgeInsets.all(16),
              itemBuilder: (context, i) {
                final o = orders[i];
                final total = o.totalPrice;
                final paid = o.paidAmount;
                final isPaid = o.isPaid;
                final displayStatus = isPaid ? 'Completed' : o.status;
                final paymentLabel = isPaid ? 'FULLY PAID' : 'UNPAID';

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  elevation: 0,
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: Colors.grey.shade200),
                  ),
                  child: ExpansionTile(
                    title: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            o.displayProductName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: isPaid
                                ? Colors.green.shade50
                                : Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            paymentLabel,
                            style: TextStyle(
                              color: isPaid
                                  ? Colors.green.shade700
                                  : Colors.red.shade700,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                    subtitle: Text(
                      '${o.displayTotalQuantity.toStringAsFixed(1)} ${o.items.isNotEmpty ? o.items.first.unit : (o.unit ?? 'kg')} - ${total.toStringAsFixed(0)} Frw${o.paymentMethod == null || o.paymentMethod!.isEmpty ? '' : ' - ${o.paymentMethod}'}',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13,
                      ),
                    ),
                    childrenPadding: const EdgeInsets.all(16).copyWith(top: 0),
                    expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (o.items.isNotEmpty) ...[
                        const Divider(),
                        const Text(
                          'Items',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...o.items.map(
                          (item) => Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.productName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        '${qtyLabel(item.quantityKg, item.unit)} @ ${item.pricePerKg.toStringAsFixed(0)} Frw/${item.unit}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  '${(item.quantityKg * item.pricePerKg).toStringAsFixed(0)} Frw',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const Divider(),
                      ] else if (o.productName != null) ...[
                        const Divider(),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      o.productName!,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      '${qtyLabel(o.quantityKg ?? 0, o.unit ?? 'kg')} @ ${o.pricePerKg?.toStringAsFixed(0) ?? '0'} Frw/${o.unit ?? 'kg'}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                '${o.totalPrice.toStringAsFixed(0)} Frw',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Divider(),
                      ],
                      _OrderBreakdownRow(
                        label: 'Subtotal',
                        value: '${o.itemsSubtotal.toStringAsFixed(0)} Frw',
                      ),
                      if (o.deliveryFee > 0) ...[
                        const SizedBox(height: 8),
                        _OrderBreakdownRow(
                          label: 'Delivery Fee',
                          value: '${o.deliveryFee.toStringAsFixed(0)} Frw',
                        ),
                      ],
                      if (o.discountAmount > 0) ...[
                        const SizedBox(height: 8),
                        _OrderBreakdownRow(
                          label: o.discountAmount == o.deliveryFee ? 'Promo: Free Delivery' : 'Promo Discount',
                          value: '-${o.discountAmount.toStringAsFixed(0)} Frw',
                          isDiscount: true,
                        ),
                      ],                      const SizedBox(height: 8),
                      _OrderBreakdownRow(
                        label: 'Total',
                        value: '${o.totalPrice.toStringAsFixed(0)} Frw',
                        isStrong: true,
                      ),
                      const Divider(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Status: $displayStatus',
                            style: TextStyle(
                              color: AppUi.primary,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          if (isPaid)
                            Text(
                              'Paid: ${paid.toStringAsFixed(0)} Frw',
                              style: TextStyle(
                                color: Colors.green.shade700,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          if (!isPaid)
                            Text(
                              'Debt: ${(total - paid).toStringAsFixed(0)} Frw',
                              style: const TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                        ],
                      ),
                      if (o.status == 'Cancelled' &&
                          (o.cancelReason ?? '').trim().isNotEmpty) ...[
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
                            'Cancel reason: ${o.cancelReason!.trim()}',
                            style: TextStyle(
                              color: Colors.red.shade800,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                      if (o.status != 'Cancelled' &&
                          o.status != 'Completed' &&
                          o.paidAmount <= 0) ...[
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: OutlinedButton.icon(
                            onPressed: () => _cancelOrder(o),
                            icon: const Icon(Icons.cancel_outlined),
                            label: const Text('Cancel Order'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red.shade700,
                              side: BorderSide(color: Colors.red.shade200),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _OrderBreakdownRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isStrong;
  final bool isDiscount;

  const _OrderBreakdownRow({
    required this.label,
    required this.value,
    this.isStrong = false,
    this.isDiscount = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDiscount
        ? Colors.green.shade700
        : isStrong
        ? AppUi.dark
        : Colors.grey.shade700;
    final style = TextStyle(
      color: color,
      fontWeight: isStrong || isDiscount ? FontWeight.w800 : FontWeight.w600,
      fontSize: isStrong ? 15 : 13,
    );

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: style),
        Text(value, style: style),
      ],
    );
  }
}

// ==========================================
// PROFILE TAB
// ==========================================

class _ClientProfileTab extends StatefulWidget {
  final Map<String, dynamic> userProfile;
  final VoidCallback onProfileUpdated;
  final VoidCallback onOpenOrders;

  const _ClientProfileTab({
    required this.userProfile,
    required this.onProfileUpdated,
    required this.onOpenOrders,
  });

  @override
  State<_ClientProfileTab> createState() => _ClientProfileTabState();
}

class _ClientProfileTabState extends State<_ClientProfileTab> {
  String _paymentMethod = 'MoMo Pay';
  bool _loadingPaymentMethod = true;
  @override
  void initState() {
    super.initState();
    _loadPaymentMethod();
  }

  Future<void> _launchWhatsAppHelp() async {
    final profile = await LiveLocationService.instance.loadBusinessProfile();
    final phone = profile.phone.trim();
    if (phone.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Business contact number is not available yet.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    final cleanPhone = phone.replaceAll(RegExp(r'[^0-9]'), '');
    final whatsappUrl = Uri.parse(
      'https://wa.me/$cleanPhone?text=Hello PAFLY Support, I need help with my account.',
    );

    try {
      if (await canLaunchUrl(whatsappUrl)) {
        await launchUrl(whatsappUrl, mode: LaunchMode.externalApplication);
      } else {
        throw 'Could not launch WhatsApp';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not open WhatsApp. Please contact us at $phone',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _loadPaymentMethod() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = widget.userProfile['id']?.toString() ?? 'guest';
    final saved = prefs.getString('payment_method_$userId');
    if (!mounted) return;
    setState(() {
      _paymentMethod = saved ?? 'MoMo Pay';
      _loadingPaymentMethod = false;
    });
  }

  Future<void> _savePaymentMethod(String value) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = widget.userProfile['id']?.toString() ?? 'guest';
    await prefs.setString('payment_method_$userId', value);
    if (!mounted) return;
    setState(() => _paymentMethod = value);
  }

  String _currentEmailLabel() {
    final profileEmail = widget.userProfile['email']?.toString().trim();
    if (profileEmail != null && profileEmail.isNotEmpty) {
      return profileEmail;
    }
    final authEmail = Supabase.instance.client.auth.currentUser?.email?.trim();
    if (authEmail != null && authEmail.isNotEmpty) {
      return authEmail;
    }
    return 'No email linked';
  }

  Future<void> _signOut() async {
    await LiveLocationService.instance.stopTracking();
    await Supabase.instance.client.auth.signOut();
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  void _showEditProfileSheet() {
    final isDesktop = MediaQuery.of(context).size.width >= 800;
    
    if (isDesktop) {
      showDialog(
        context: context,
        builder: (dialogContext) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Material(
              color: Colors.transparent,
              child: _EditProfileSheet(
                userProfile: widget.userProfile,
                onProfileUpdated: widget.onProfileUpdated,
              ),
            ),
          ),
        ),
      );
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => _EditProfileSheet(
          userProfile: widget.userProfile,
          onProfileUpdated: widget.onProfileUpdated,
        ),
      );
    }
  }

  void _showEmailUpgradeSheet() {
    final currentEmail = _currentEmailLabel() == 'No email linked'
        ? ''
        : _currentEmailLabel();
    final emailCtrl = TextEditingController(text: currentEmail);
    final isDesktop = MediaQuery.of(context).size.width >= 800;

    Widget buildUpgradeSheet(BuildContext sheetContext) {
      bool isSaving = false;

      return StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          Future<void> saveEmail() async {
            final newEmail = emailCtrl.text.trim();
            if (newEmail.isEmpty || !newEmail.contains('@')) {
              ScaffoldMessenger.of(sheetContext).showSnackBar(
                const SnackBar(
                  content: Text('Enter a valid email address.'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
              return;
            }

            setSheetState(() => isSaving = true);
            try {
              await Supabase.instance.client.auth.updateUser(
                UserAttributes(email: newEmail),
              );

              if (sheetContext.mounted) {
                Navigator.pop(sheetContext, newEmail);
              }
            } on AuthException catch (e) {
              if (sheetContext.mounted) {
                ScaffoldMessenger.of(sheetContext).showSnackBar(
                  SnackBar(
                    content: Text(
                      friendlyAccountIdentityErrorMessage(
                        e,
                        fallbackMessage: e.message,
                      ),
                    ),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            } catch (e) {
              if (sheetContext.mounted) {
                ScaffoldMessenger.of(sheetContext).showSnackBar(
                  SnackBar(
                    content: Text('Could not update email: $e'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            } finally {
              if (sheetContext.mounted) {
                setSheetState(() => isSaving = false);
              }
            }
          }

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
            ),
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: isDesktop 
                    ? BorderRadius.circular(28) 
                    : const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!isDesktop)
                    Center(
                      child: Container(
                        width: 48,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                  const SizedBox(height: 18),
                  const Text(
                    'Add Email Later',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Link an email to recover your password and sign in more easily.',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: 'Email address',
                      hintText: 'you@example.com',
                      prefixIcon: const Icon(Icons.email_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 54,
                    child: ElevatedButton.icon(
                      onPressed: isSaving ? null : saveEmail,
                      icon: isSaving
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check_rounded),
                      label: const Text(
                        'Save Email',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppUi.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    if (isDesktop) {
      showDialog<String>(
        context: context,
        builder: (dialogContext) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Material(
              color: Colors.transparent,
              child: buildUpgradeSheet(dialogContext),
            ),
          ),
        ),
      ).then((newEmail) {
        if (!mounted || newEmail == null) return;
        _handleEmailUpdateSuccess(newEmail);
      });
    } else {
      showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) => buildUpgradeSheet(sheetContext),
      ).then((newEmail) {
        if (!mounted || newEmail == null) return;
        _handleEmailUpdateSuccess(newEmail);
      });
    }
  }

  void _handleEmailUpdateSuccess(String newEmail) {
    widget.onProfileUpdated();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Email linked successfully. Use $newEmail for recovery.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }


  void _showPaymentMethodSheet() {
    final isDesktop = MediaQuery.of(context).size.width >= 800;

    Widget buildPaymentSheet(BuildContext ctx) => Container(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: isDesktop
                ? BorderRadius.circular(28)
                : const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isDesktop)
                Center(
                  child: Container(
                    width: 48,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              const SizedBox(height: 18),
              const Text(
                'Payment Methods',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Text(
                'Choose how you usually pay for your orders.',
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 18),
              ...['MoMo Pay', 'Cash'].map(
                (method) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _PaymentMethodOption(
                    title: method,
                    subtitle: method == 'MoMo Pay'
                        ? 'Mobile money payment'
                        : 'Pay on delivery with cash',
                    icon: method == 'MoMo Pay'
                        ? Icons.phone_android_rounded
                        : Icons.payments_outlined,
                    isSelected: _paymentMethod == method,
                    onTap: () async {
                      await _savePaymentMethod(method);
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                  ),
                ),
              ),
            ],
          ),
        );

    if (isDesktop) {
      showDialog(
        context: context,
        builder: (dialogContext) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Material(
              color: Colors.transparent,
              child: buildPaymentSheet(dialogContext),
            ),
          ),
        ),
      );
    } else {
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (context) => buildPaymentSheet(context),
      );
    }
  }

  void _showComingSoon(String title) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$title will be updated next.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _retryLiveLocationTracking() async {
    await LiveLocationService.instance.startTracking(
      userId: widget.userProfile['id']?.toString() ?? '',
      customerName: widget.userProfile['name']?.toString() ?? 'Client',
      phone: widget.userProfile['phone']?.toString() ?? '',
      locationLabel: widget.userProfile['location']?.toString() ?? '',
    );
  }

  void _showLiveLocationSheet() {
    final service = LiveLocationService.instance;
    final isDesktop = MediaQuery.of(context).size.width >= 800;

    Widget buildLiveLocationSheet(BuildContext ctx) =>
        ValueListenableBuilder<LiveLocationTrackingState>(
          valueListenable: service.trackingState,
          builder: (ctx, trackingState, _) {
            final lastUpdated = trackingState.lastUpdatedAt == null
                ? 'Waiting for first GPS fix'
                : 'Last update ${_formatTrackingTimestamp(trackingState.lastUpdatedAt!)}';
            final needsSettings =
                trackingState.status ==
                    LiveLocationTrackingStatus.permissionDeniedForever ||
                trackingState.status ==
                    LiveLocationTrackingStatus.serviceDisabled;

            return Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: isDesktop
                    ? BorderRadius.circular(28)
                    : const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isDesktop)
                    Center(
                      child: Container(
                        width: 48,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                  const SizedBox(height: 18),
                  const Text(
                    'Live Location',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    trackingState.message,
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    lastUpdated,
                    style: TextStyle(
                      color: AppUi.primary.withValues(alpha: 0.8),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.close_rounded),
                          label: const Text('Close'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 50),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed:
                              needsSettings
                                  ? () => Geolocator.openAppSettings()
                                  : () => _retryLiveLocationTracking(),
                          icon: Icon(
                            needsSettings
                                ? Icons.settings_rounded
                                : Icons.refresh_rounded,
                          ),
                          label: Text(needsSettings ? 'Settings' : 'Retry'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppUi.primary,
                            minimumSize: const Size(0, 50),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );

    if (isDesktop) {
      showDialog(
        context: context,
        builder: (dialogContext) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Material(
              color: Colors.transparent,
              child: buildLiveLocationSheet(dialogContext),
            ),
          ),
        ),
      );
    } else {
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (context) => buildLiveLocationSheet(context),
      );
    }
  }

  String _formatTrackingTimestamp(DateTime timestamp) {
    final difference = DateTime.now().difference(timestamp);
    if (difference.inSeconds < 60) return 'just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes} min ago';
    if (difference.inHours < 24) return '${difference.inHours} h ago';
    return '${difference.inDays} d ago';
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.userProfile['name']?.toString() ?? 'Client';
    final initials = name.length >= 2
        ? name.substring(0, 2).toUpperCase()
        : name.toUpperCase();
    final location =
        widget.userProfile['location']?.toString() ??
        'Add your delivery address';
    final phone = widget.userProfile['phone']?.toString() ?? 'No phone number';
    final email = _currentEmailLabel();
    final paymentLabel = _loadingPaymentMethod ? 'Loading...' : _paymentMethod;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF7),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 180,
            pinned: true,
            backgroundColor: AppUi.primary,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppUi.primary, Color(0xFF2E7D32)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      right: -30,
                      top: -20,
                      child: Opacity(
                        opacity: 0.1,
                        child: Image.asset('assets/logo.png', width: 200),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(40),
              child: Container(
                height: 40,
                decoration: const BoxDecoration(
                  color: Color(0xFFF8FAF7),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  Transform.translate(
                    offset: const Offset(0, -60),
                    child: Column(
                      children: [
                        Container(
                          width: 110,
                          height: 110,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                            border: Border.all(color: Colors.white, width: 4),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.1),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: ClipOval(
                            child: Container(
                              color: const Color(0xFFEAF7E3),
                              child: Center(
                                child: Text(
                                  initials,
                                  style: const TextStyle(
                                    fontSize: 38,
                                    fontWeight: FontWeight.w900,
                                    color: AppUi.primary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          name,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: AppUi.dark,
                          ),
                        ),
                        Text(
                          email,
                          style: TextStyle(
                            fontSize: 15,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  _buildSectionHeader('ACCOUNT SETTINGS'),
                  const SizedBox(height: 14),
                  _ProfileActionTile(
                    icon: Icons.person_outline_rounded,
                    title: 'Personal Info',
                    subtitle: phone,
                    accentColor: const Color(0xFFE6F2FF),
                    iconColor: const Color(0xFF4D91FF),
                    onTap: _showEditProfileSheet,
                  ),
                  const SizedBox(height: 12),
                  _ProfileActionTile(
                    icon: Icons.email_outlined,
                    title: 'Email Recovery',
                    subtitle: email == 'No email linked'
                        ? 'Add email later for reset'
                        : email,
                    accentColor: const Color(0xFFF2E8FF),
                    iconColor: const Color(0xFF7B55C7),
                    onTap: _showEmailUpgradeSheet,
                  ),
                  const SizedBox(height: 12),
                  _ProfileActionTile(
                    icon: Icons.location_on_outlined,
                    title: 'Addresses',
                    subtitle: location,
                    accentColor: const Color(0xFFEAF7E3),
                    iconColor: AppUi.primary,
                    onTap: _showEditProfileSheet,
                  ),
                  const SizedBox(height: 12),
                  ValueListenableBuilder<LiveLocationTrackingState>(
                    valueListenable: LiveLocationService.instance.trackingState,
                    builder: (context, trackingState, _) => _ProfileActionTile(
                      icon: trackingState.isTracking
                          ? Icons.location_searching_rounded
                          : Icons.gps_off_rounded,
                      title: 'Live Location',
                      subtitle: trackingState.isTracking
                          ? 'Sharing your live market position'
                          : trackingState.message,
                      accentColor: const Color(0xFFE7F2FF),
                      iconColor: const Color(0xFF2C73D2),
                      onTap: _showLiveLocationSheet,
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildSectionHeader('PAYMENT & ORDERS'),
                  const SizedBox(height: 14),
                  _ProfileActionTile(
                    icon: Icons.payments_outlined,
                    title: 'Payment Methods',
                    subtitle: paymentLabel,
                    accentColor: const Color(0xFFFFF2E2),
                    iconColor: const Color(0xFFB97A28),
                    onTap: _showPaymentMethodSheet,
                  ),
                  const SizedBox(height: 12),
                  _ProfileActionTile(
                    icon: Icons.receipt_long_outlined,
                    title: 'Order History',
                    subtitle: 'View your recent orders',
                    accentColor: const Color(0xFFE9F5E8),
                    iconColor: AppUi.primary,
                    onTap: widget.onOpenOrders,
                  ),
                  const SizedBox(height: 12),
                  _ProfileActionTile(
                    icon: Icons.favorite_outline_rounded,
                    title: 'Favorites',
                    subtitle: 'Saved items and quick reorders',
                    accentColor: const Color(0xFFFFEEE6),
                    iconColor: const Color(0xFFFF8E5D),
                    onTap: () => _showComingSoon('Favorites'),
                  ),
                  const SizedBox(height: 12),
                  _ProfileActionTile(
                    icon: Icons.support_agent_rounded,
                    title: 'Help Center',
                    subtitle: 'Contact support on WhatsApp',
                    accentColor: const Color(0xFFE3F2FD),
                    iconColor: const Color(0xFF1976D2),
                    onTap: _launchWhatsAppHelp,
                  ),
                  const SizedBox(height: 40),
                  SizedBox(
                    width: double.infinity,
                    height: 58,
                    child: OutlinedButton.icon(
                      onPressed: _signOut,
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text(
                        'Sign Out',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade700,
                        side: BorderSide(color: Colors.red.shade100, width: 2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w900,
          color: Colors.grey.shade500,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _ProfileActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accentColor;
  final Color iconColor;
  final VoidCallback onTap;

  const _ProfileActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accentColor,
    required this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 14,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accentColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppUi.dark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: Colors.grey.shade500,
                size: 28,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaymentMethodOption extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _PaymentMethodOption({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected ? const Color(0xFFF0F7EB) : Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? AppUi.primary : Colors.grey.shade200,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF7E3),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: AppUi.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                isSelected ? Icons.check_circle_rounded : Icons.circle_outlined,
                color: isSelected ? AppUi.primary : Colors.grey.shade400,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditProfileSheet extends StatefulWidget {
  final Map<String, dynamic> userProfile;
  final VoidCallback onProfileUpdated;

  const _EditProfileSheet({
    required this.userProfile,
    required this.onProfileUpdated,
  });

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  late TextEditingController _nameCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _locCtrl;
  late TextEditingController _waCtrl;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.userProfile['name']);
    _phoneCtrl = TextEditingController(text: widget.userProfile['phone'] ?? '');
    _locCtrl = TextEditingController(text: widget.userProfile['location']);
    _waCtrl = TextEditingController(text: widget.userProfile['whatsapp'] ?? '');
  }

  Future<void> _saveProfile() async {
    setState(() => _isSaving = true);
    try {
      await Supabase.instance.client.rpc(
        'update_own_user_profile',
        params: {
          'display_name': _nameCtrl.text.trim(),
          'location_param': _locCtrl.text.trim(),
          'whatsapp_param': _waCtrl.text.trim(),
          'phone_param': _phoneCtrl.text.trim(),
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Profile updated successfully!',
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
        widget.onProfileUpdated();
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              friendlyAccountIdentityErrorMessage(
                e,
                fallbackMessage: 'Update failed. Please try again.',
              ),
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      setState(() => _isSaving = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _locCtrl.dispose();
    _waCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Edit Profile',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _nameCtrl,
                inputFormatters: [InputRules.textOnly],
                decoration: InputDecoration(
                  labelText: 'Full Name',
                  prefixIcon: const Icon(Icons.person_outline),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                inputFormatters: [InputRules.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'Phone Number',
                  prefixIcon: const Icon(Icons.phone_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _waCtrl,
                keyboardType: TextInputType.phone,
                inputFormatters: [InputRules.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'WhatsApp Number',
                  prefixIcon: const Icon(Icons.chat_bubble_outline),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _locCtrl,
                decoration: InputDecoration(
                  labelText: 'Delivery Location',
                  prefixIcon: const Icon(Icons.location_on_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppUi.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'Save Changes',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
