import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:potato_app/models/product.dart';
import 'package:potato_app/models/order.dart';
import 'package:potato_app/models/debt.dart';
import 'package:potato_app/utils/app_ui.dart';
import 'package:potato_app/utils/formatters.dart';
import 'package:potato_app/utils/supabase_errors.dart';
import 'package:potato_app/utils/constants.dart';
import 'package:potato_app/widgets/state_message_card.dart';
import 'package:potato_app/widgets/dashboard_widgets.dart';
import 'package:potato_app/widgets/order_widgets.dart';

class FreshMarketScreen extends StatefulWidget {
  final VoidCallback onOpenAdmin;

  const FreshMarketScreen({super.key, required this.onOpenAdmin});

  @override
  State<FreshMarketScreen> createState() => _FreshMarketScreenState();
}

class _FreshMarketScreenState extends State<FreshMarketScreen> {
  late Stream<List<Map<String, dynamic>>> _productsStream;

  @override
  void initState() {
    super.initState();
    _productsStream = Supabase.instance.client
        .from(AppConstants.productsTable)
        .stream(primaryKey: ['id'])
        .order('name', ascending: true);
  }

  Future<bool> _placeOrder(
    Product product,
    String name,
    String phone,
    String location,
    double quantityKg,
    bool onCredit,
    double paid,
  ) async {
    try {
      final effectivePrice = product.effectivePriceFor(quantityKg);
      final totalPrice = quantityKg * effectivePrice;
      await Supabase.instance.client.rpc(
        AppConstants.placeOrderRpc,
        params: {
          'p_customer_name': name,
          'p_phone': phone,
          'p_location': location,
          'p_product_id': product.id,
          'p_quantity_kg': quantityKg,
          'p_is_credit': onCredit,
          'p_paid_amount': onCredit ? paid : totalPrice,
        },
      );
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              friendlyDataError(e, fallbackMessage: 'Order placement failed.'),
            ),
          ),
        );
      }
      return false;
    }
  }

  void _showOrderForm(Product product) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (ctx) => OrderForm(
        product: product,
        onSubmit: (name, phone, location, qty, credit, paid) =>
            _placeOrder(product, name, phone, location, qty, credit, paid),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FBF9),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 220,
            floating: false,
            pinned: true,
            backgroundColor: AppUi.primary,
            elevation: 0,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 18,
              ),
              title: const Text(
                'PAFLY',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 24,
                  letterSpacing: -0.5,
                ),
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppUi.primary, Color(0xFF2E6B40)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                  Positioned(
                    right: -40,
                    top: -20,
                    child: Icon(
                      Icons.eco,
                      size: 240,
                      color: Colors.white.withAlpha(20),
                    ),
                  ),
                  Positioned(
                    bottom: 70,
                    left: 20,
                    right: 20,
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              showDialog(
                                context: context,
                                builder: (ctx) =>
                                    const _PhoneInputDialog(type: 'orders'),
                              );
                            },
                            child: const DashboardPill(
                              label: 'Track Orders',
                              value: 'My Purchases',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              showDialog(
                                context: context,
                                builder: (ctx) =>
                                    const _PhoneInputDialog(type: 'debt'),
                              );
                            },
                            child: const DashboardPill(
                              label: 'Pay Later',
                              value: 'Credit Status',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              IconButton(
                onPressed: widget.onOpenAdmin,
                icon: const Icon(
                  Icons.admin_panel_settings,
                  color: Colors.white70,
                ),
                tooltip: 'Staff login',
              ),
              const SizedBox(width: 8),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
              child: Row(
                children: [
                  const Icon(
                    Icons.local_mall_outlined,
                    color: AppUi.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Available Produce',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppUi.primary.withAlpha(20),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Direct from Farm',
                      style: TextStyle(
                        color: AppUi.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
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
                      message: friendlyDataError(
                        snapshot.error!,
                        fallbackMessage: 'We couldn\'t load the marketplace.',
                      ),
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

                final products = snapshot.data!
                    .map((j) => Product.fromJson(j))
                    .where((p) => p.quantity > 0)
                    .toList();

                if (products.isEmpty) {
                  return const SliverToBoxAdapter(
                    child: _EmptyInventoryState(),
                  );
                }

                return SliverList(
                  delegate: SliverChildBuilderDelegate((ctx, i) {
                    final p = products[i];
                    return _MarketProductCard(
                      product: p,
                      onOrder: () => _showOrderForm(p),
                    );
                  }, childCount: products.length),
                );
              },
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 200)),
        ],
      ),
    );
  }
}

class _MarketProductCard extends StatelessWidget {
  final Product product;
  final VoidCallback onOrder;

  const _MarketProductCard({required this.product, required this.onOrder});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(10),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onOrder,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    Image.network(
                      product.imageUrl,
                      height: 180,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      cacheWidth: 720,
                      errorBuilder: (ctx, error, stackTrace) => Container(
                        height: 180,
                        color: const Color(0xFFF2F6F2),
                        child: const Icon(
                          Icons.image_outlined,
                          size: 40,
                          color: AppUi.primary,
                        ),
                      ),
                    ),
                    Positioned(
                      top: 14,
                      right: 14,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(230),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withAlpha(20),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: Text(
                          '${moneyLabel(product.price)} FRW/KG',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                            color: AppUi.primary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Fresh stock available now',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 13,
                          height: 1.3,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: onOrder,
                          icon: const Icon(
                            Icons.shopping_cart_outlined,
                            size: 18,
                          ),
                          label: const Text(
                            'Order',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppUi.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyInventoryState extends StatelessWidget {
  const _EmptyInventoryState();

  @override
  Widget build(BuildContext context) {
    return const StateMessageCard(
      icon: Icons.inventory_2_outlined,
      title: 'No products available yet',
      message:
          'The catalogue is connected and working, but there are no active potato listings to show customers right now.',
      details: [
        'Add products from the admin dashboard.',
        'The catalogue stays empty until products are created.',
      ],
    );
  }
}

class _PhoneInputDialog extends StatefulWidget {
  final String type;
  const _PhoneInputDialog({required this.type});

  @override
  State<_PhoneInputDialog> createState() => _PhoneInputDialogState();
}

class _PhoneInputDialogState extends State<_PhoneInputDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.type == 'orders' ? 'My Orders' : 'Credit Status'),
      content: TextField(
        controller: _controller,
        decoration: const InputDecoration(
          labelText: 'Enter your phone number',
          hintText: '078...',
        ),
        keyboardType: TextInputType.phone,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final phone = _controller.text.trim();
            if (phone.isNotEmpty) {
              Navigator.pop(context);
              showDialog(
                context: context,
                builder: (ctx) => widget.type == 'orders'
                    ? _CustomerOrdersDialog(phone: phone)
                    : _CustomerDebtDialog(phone: phone),
              );
            }
          },
          child: const Text('View'),
        ),
      ],
    );
  }
}

class _CustomerOrdersDialog extends StatelessWidget {
  final String phone;
  const _CustomerOrdersDialog({required this.phone});

  Future<List<Order>> _loadOrders() async {
    final response = await Supabase.instance.client
        .from(AppConstants.ordersTable)
        .select()
        .eq('phone', phone)
        .order('created_at', ascending: false);
    return (response as List<dynamic>)
        .map((item) => Order.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 620),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: const BoxDecoration(
                color: AppUi.primary,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: const Text(
                'My Orders',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Expanded(
              child: FutureBuilder<List<Order>>(
                future: _loadOrders(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(child: Text('Error: ${snapshot.error}'));
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final orders = snapshot.data!;
                  if (orders.isEmpty) {
                    return const Center(child: Text('No orders found.'));
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: orders.length,
                    separatorBuilder: (_, index) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final o = orders[i];
                      return Card(
                        child: ListTile(
                          title: Text(o.productName ?? 'Item Purchase'),
                          subtitle: Text(
                            orderDateLabel(o.createdAt ?? DateTime.now()),
                          ),
                          trailing: StatusChip(o.status),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _CustomerDebtDialog extends StatelessWidget {
  final String phone;
  const _CustomerDebtDialog({required this.phone});

  Future<List<Debt>> _loadDebts() async {
    final response = await Supabase.instance.client
        .from(AppConstants.debtsView)
        .select()
        .eq('phone', phone);
    return (response as List<dynamic>)
        .map((item) => Debt.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 620),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: const BoxDecoration(
                color: Color(0xFF9A5B13),
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: const Text(
                'Outstanding Debt',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Expanded(
              child: FutureBuilder<List<Debt>>(
                future: _loadDebts(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(child: Text('Error: ${snapshot.error}'));
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final debts = snapshot.data!;
                  if (debts.isEmpty) {
                    return const Center(child: Text('No debt found.'));
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: debts.length,
                    separatorBuilder: (_, index) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final d = debts[i];
                      return Card(
                        child: ListTile(
                          title: Text(d.productName),
                          trailing: Text(
                            '${moneyLabel(d.balance)} FRW',
                            style: const TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class OrderForm extends StatefulWidget {
  final Product product;
  final Future<bool> Function(
    String name,
    String phone,
    String location,
    double quantityKg,
    bool onCredit,
    double paid,
  )
  onSubmit;

  const OrderForm({super.key, required this.product, required this.onSubmit});

  @override
  State<OrderForm> createState() => _OrderFormState();
}

class _OrderFormState extends State<OrderForm> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _location = TextEditingController();
  final _kg = TextEditingController();
  final _paid = TextEditingController();
  bool onCredit = false;
  double totalPrice = 0;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _location.dispose();
    _kg.dispose();
    _paid.dispose();
    super.dispose();
  }

  void _recalculate() {
    final quantity = double.tryParse(_kg.text) ?? 0;
    final effectivePrice = widget.product.effectivePriceFor(quantity);
    setState(() => totalPrice = quantity * effectivePrice);
  }

  InputDecoration _fieldDecoration({
    required String label,
    required IconData icon,
    String? helperText,
  }) {
    return InputDecoration(
      labelText: label,
      helperText: helperText,
      prefixIcon: Icon(icon, color: AppUi.primary),
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
        borderSide: const BorderSide(color: AppUi.primary, width: 1.4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final unitLabel = widget.product.unit.toLowerCase() == 'pc' ? 'Pc' : 'Kg';
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        12,
        24,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 46,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              Text(
                'Order ${widget.product.name}',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                decoration: _fieldDecoration(
                  label: 'Your Name',
                  icon: Icons.person_outline,
                ),
                validator: (v) => v!.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                decoration: _fieldDecoration(
                  label: 'Phone Number',
                  icon: Icons.phone_outlined,
                ),
                keyboardType: TextInputType.phone,
                validator: (v) => v!.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _location,
                decoration: _fieldDecoration(
                  label: 'Location',
                  icon: Icons.location_on_outlined,
                ),
                validator: (v) => v!.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _kg,
                decoration: _fieldDecoration(
                  label: 'Quantity ($unitLabel)',
                  icon: Icons.scale_outlined,
                ),
                keyboardType: TextInputType.number,
                onChanged: (_) => _recalculate(),
                validator: (v) {
                  final value = double.tryParse(v ?? '') ?? 0;
                  if (value <= 0) return 'Enter quantity';
                  if (widget.product.unit.toLowerCase() == 'pc' &&
                      value != value.roundToDouble()) {
                    return 'Use a whole number of pieces';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('Buy on Credit?'),
                subtitle: const Text('Pay later at delivery'),
                value: onCredit,
                onChanged: (v) => setState(() => onCredit = v),
              ),
              if (!onCredit) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _paid,
                  decoration: _fieldDecoration(
                    label: 'Amount (Optional)',
                    icon: Icons.money,
                  ),
                  keyboardType: TextInputType.number,
                ),
              ],
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Estimated Total:',
                    style: TextStyle(fontSize: 16),
                  ),
                  Text(
                    '${moneyLabel(totalPrice)} FRW',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: AppUi.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SliverToBoxAdapter(child: Container()), // Dummy for spacing
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isSubmitting
                      ? null
                      : () async {
                          if (_formKey.currentState!.validate()) {
                            setState(() => _isSubmitting = true);
                            final ok = await widget.onSubmit(
                              _name.text,
                              _phone.text,
                              _location.text,
                              double.tryParse(_kg.text) ?? 0,
                              onCredit,
                              double.tryParse(_paid.text) ?? 0,
                            );
                            if (context.mounted && ok) Navigator.pop(context);
                            setState(() => _isSubmitting = false);
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppUi.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: _isSubmitting
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Confirm Order'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
