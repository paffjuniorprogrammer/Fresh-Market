import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:potato_app/models/product.dart';
import 'package:potato_app/utils/app_ui.dart';
import 'package:potato_app/utils/constants.dart';
import 'package:potato_app/models/promotion.dart';
import 'package:potato_app/widgets/state_message_card.dart';
import 'package:potato_app/widgets/fresh_market_home_widgets.dart';
import 'package:potato_app/services/pwa_service.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';

class GuestBrowseScreen extends StatefulWidget {
  final VoidCallback onLoginTapped;

  const GuestBrowseScreen({super.key, required this.onLoginTapped});

  @override
  State<GuestBrowseScreen> createState() => _GuestBrowseScreenState();
}

class _GuestBrowseScreenState extends State<GuestBrowseScreen> {
  late Stream<List<Map<String, dynamic>>> _productsStream;
  String _searchQuery = '';
  String? _selectedCategoryId;
  final List<Map<String, dynamic>> _categories = [];
  final List<Promotion> _promotions = [];
  int _currentBannerIndex = 0;
  Timer? _bannerTimer;
  final PageController _bannerPageController = PageController(initialPage: 1000);

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _loadPromotions();
    _productsStream = Supabase.instance.client
        .from(AppConstants.productsTable)
        .stream(primaryKey: ['id'])
        .order('name', ascending: true);
  }

  Future<void> _loadPromotions() async {
    try {
      final response = await Supabase.instance.client
          .from('promotions')
          .select()
          .eq('is_active', true);
      if (mounted) {
        setState(() {
          _promotions.clear();
          _promotions.addAll(
            (response as List<dynamic>).map((p) => Promotion.fromJson(p)),
          );
        });
        _startBannerTimer();
      }
    } catch (e) {
      debugPrint('Promotion loading error: $e');
    }
  }

  void _startBannerTimer() {
    _bannerTimer?.cancel();
    if (_promotions.isEmpty) return;
    _bannerTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && _bannerPageController.hasClients) {
        _bannerPageController.nextPage(
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  Future<void> _loadCategories() async {
    try {
      final response = await Supabase.instance.client
          .from(AppConstants.categoriesTable)
          .select()
          .order('name', ascending: true);

      if (mounted) {
        setState(() {
          _categories.clear();
          _categories.addAll(
            (response as List<dynamic>).cast<Map<String, dynamic>>(),
          );
        });
      }
    } catch (e) {
      debugPrint('Category loading error: $e');
    }
  }

  List<Product> _filterProducts(List<Product> products) {
    var filtered = products.where((p) => p.quantity > 0).toList();

    if (_selectedCategoryId != null) {
      filtered = filtered
          .where((p) => p.categoryId == _selectedCategoryId)
          .toList();
    }

    if (_searchQuery.isNotEmpty) {
      filtered = filtered
          .where(
            (p) =>
                p.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                p.description.toLowerCase().contains(
                  _searchQuery.toLowerCase(),
                ),
          )
          .toList();
    }

    return filtered;
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _bannerPageController.dispose();
    super.dispose();
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
    if (name.contains('fruit')) return Icons.spa_outlined;
    if (name.contains('veget')) return Icons.eco_outlined;
    if (name.contains('dairy')) return Icons.icecream_outlined;
    if (name.contains('meat')) return Icons.set_meal_outlined;
    if (name.contains('bread') || name.contains('bak')) {
      return Icons.bakery_dining_outlined;
    }
    return Icons.shopping_basket_outlined;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            backgroundColor: const Color(0xFFF0F4FF),
            elevation: 0,
            pinned: true,
            toolbarHeight: 80,
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: Image.asset(
                    'assets/logo.png',
                    height: 40,
                    width: 40,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'PAFLY',
                  style: TextStyle(
                    color: AppUi.primary,
                    fontWeight: FontWeight.w900,
                    fontSize: 22,
                  ),
                ),
              ],
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: FilledButton.icon(
                  onPressed: widget.onLoginTapped,
                  icon: const Icon(Icons.login_rounded, size: 18),
                  label: const Text('Login'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppUi.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (kIsWeb)
            SliverToBoxAdapter(
              child: StreamBuilder<bool>(
                stream: PwaService.instance.installableStream,
                initialData: PwaService.instance.isInstallable,
                builder: (context, snapshot) {
                  if (snapshot.data != true) return const SizedBox.shrink();
                  return Container(
                    margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppUi.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
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
                                'Get a better experience on your phone.',
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
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 15,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: TextField(
                      onChanged: (value) => setState(() => _searchQuery = value),
                      decoration: InputDecoration(
                        hintText: 'Search fresh products...',
                        prefixIcon: const Icon(
                          Icons.search_rounded,
                          color: AppUi.primary,
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  StreamBuilder<List<Map<String, dynamic>>>(
                    stream: _productsStream,
                    builder: (context, snapshot) {
                      final products = (snapshot.data ?? [])
                          .map((j) => Product.fromJson(j))
                          .where((p) => p.isAvailable && p.imageUrl.isNotEmpty && p.hasDiscount)
                          .toList();

                      if (products.isEmpty) {
                        if (_promotions.isEmpty) return const SizedBox.shrink();
                        return Column(
                          children: [
                            SizedBox(
                              height: 220,
                              child: PageView.builder(
                                controller: _bannerPageController,
                                onPageChanged: (index) {
                                  setState(() {
                                    _currentBannerIndex = index % _promotions.length;
                                  });
                                },
                                itemBuilder: (context, index) {
                                  final promo = _promotions[index % _promotions.length];
                                  return FreshMarketHeroCard(
                                    title: 'Fresh Deals Today',
                                    subtitle: promo.title,
                                    badgeText: 'DEAL',
                                    imageUrl: promo.imageUrl,
                                    onPressed: widget.onLoginTapped,
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],
                        );
                      }

                      return Column(
                        children: [
                          SizedBox(
                            height: 220,
                            child: PageView.builder(
                              controller: _bannerPageController,
                              onPageChanged: (index) {
                                setState(() {
                                  _currentBannerIndex = index % products.length;
                                });
                              },
                              itemBuilder: (context, index) {
                                final product = products[index % products.length];
                                return FreshMarketProductHeroCard(
                                  product: product,
                                  onTap: widget.onLoginTapped,
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(
                              products.length,
                              (index) => AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                margin: const EdgeInsets.symmetric(horizontal: 4),
                                height: 8,
                                width: _currentBannerIndex == index ? 24 : 8,
                                decoration: BoxDecoration(
                                  color: _currentBannerIndex == index
                                      ? AppUi.primary
                                      : Colors.grey.shade300,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                      );
                    },
                  ),
                  if (_categories.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 100,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _categories.length + 1,
                        separatorBuilder: (_, _) => const SizedBox(width: 12),
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            final selected = _selectedCategoryId == null;
                            return GestureDetector(
                              onTap: () => setState(() => _selectedCategoryId = null),
                              child: Column(
                                children: [
                                  Container(
                                    height: 64,
                                    width: 64,
                                    decoration: BoxDecoration(
                                      color: selected ? AppUi.primary : Colors.white,
                                      borderRadius: BorderRadius.circular(20),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.05),
                                          blurRadius: 10,
                                        ),
                                      ],
                                    ),
                                    child: Icon(
                                      Icons.grid_view_rounded,
                                      color: selected ? Colors.white : AppUi.primary,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'All',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                                      color: selected ? AppUi.primary : Colors.grey.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }

                          final category = _categories[index - 1];
                          final catId = category['id'] as String?;
                          final catName = category['name'] as String? ?? '';
                          final selected = _selectedCategoryId == catId;

                          return GestureDetector(
                            onTap: () => setState(() => _selectedCategoryId = catId),
                            child: FreshMarketCategoryChip(
                              label: catName,
                              imageUrl: category['image_url'] as String?,
                              isSelected: selected,
                              accentColor: _categoryColor(index),
                              icon: _categoryIcon(catName),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            sliver: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _productsStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return SliverToBoxAdapter(
                    child: StateMessageCard(
                      icon: Icons.cloud_off,
                      title: 'Connection Issue',
                      message: 'Could not load products. Please try again.',
                    ),
                  );
                }

                if (!snapshot.hasData) {
                  return const SliverToBoxAdapter(
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.all(60),
                        child: CircularProgressIndicator(color: AppUi.primary),
                      ),
                    ),
                  );
                }

                final products = _filterProducts(
                  snapshot.data!.map((j) => Product.fromJson(j)).toList(),
                );

                if (products.isEmpty) {
                  return SliverToBoxAdapter(
                    child: StateMessageCard(
                      icon: Icons.inventory_2_outlined,
                      title: 'No products found',
                      message: _searchQuery.isNotEmpty
                          ? 'Try different search terms.'
                          : 'Check back soon for fresh produce!',
                    ),
                  );
                }

                return SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.68,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 16,
                  ),
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final product = products[index];
                    return FreshMarketProductCard(
                      product: product,
                      qtyInCart: 0,
                      badgeText: product.hasDiscount ? 'SPECIAL DEAL' : '',
                      onAdd: widget.onLoginTapped,
                      onRemove: widget.onLoginTapped,
                    );
                  }, childCount: products.length),
                );
              },
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }
}

