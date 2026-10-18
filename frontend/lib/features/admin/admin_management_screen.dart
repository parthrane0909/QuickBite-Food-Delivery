/// Responsive, API-backed admin management lists and safe edit forms.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../data/dto/paged.dart';
import '../../core/network/api_exception.dart';
import '../../data/repositories/admin_management_repository.dart';
import '../../state/providers.dart';
import '../../ui/layout/adaptive_layout.dart';
import '../../ui/widgets/food_image.dart';

enum AdminSection { restaurants, menu, customers, drivers }

class AdminManagementScreen extends ConsumerStatefulWidget {
  const AdminManagementScreen({
    super.key,
    required this.section,
    this.restaurantId,
  });
  final AdminSection section;
  final String? restaurantId;

  @override
  ConsumerState<AdminManagementScreen> createState() =>
      _AdminManagementScreenState();
}

class _AdminManagementScreenState extends ConsumerState<AdminManagementScreen> {
  final _search = TextEditingController();
  late Future<Paged<AdminRow>> _rows;
  int _page = 1;
  int _total = 0;
  List<AdminRow> _items = [];
  bool _busy = false;

  String get _title => switch (widget.section) {
    AdminSection.restaurants => 'Restaurants',
    AdminSection.menu => 'Menu management',
    AdminSection.customers => 'Customers',
    AdminSection.drivers => 'Drivers',
  };

  @override
  void initState() {
    super.initState();
    _rows = _load();
  }

  Future<Paged<AdminRow>> _load({int page = 1}) async {
    final repo = ref.read(adminManagementRepositoryProvider);
    final result = switch (widget.section) {
      AdminSection.restaurants => await repo.restaurants(
        page: page,
        search: _search.text,
      ),
      AdminSection.menu => await repo.menu(
        widget.restaurantId!,
        page: page,
        search: _search.text,
      ),
      AdminSection.customers => await repo.customers(
        page: page,
        search: _search.text,
      ),
      AdminSection.drivers => await repo.drivers(page: page),
    };
    if (mounted) {
      setState(() {
        _page = result.page;
        _total = result.total;
        _items = page == 1 ? result.items : [..._items, ...result.items];
      });
    }
    return result;
  }

  void _refresh() => setState(() {
    _rows = _load();
  });

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_title),
      leading: IconButton(
        tooltip: 'Admin dashboard',
        onPressed: () => context.go('/admin'),
        icon: const Icon(Icons.arrow_back_rounded),
      ),
      actions: [
        if (widget.section != AdminSection.drivers)
          IconButton(
            tooltip:
                'Add ${widget.section == AdminSection.restaurants ? 'restaurant' : 'menu item'}',
            onPressed: _busy ? null : _edit,
            icon: const Icon(Icons.add_rounded),
          ),
        TextButton.icon(
          onPressed: () => context.go('/restaurants'),
          icon: const Icon(Icons.storefront_outlined),
          label: const Text('Shop as customer'),
        ),
        const SizedBox(width: 8),
      ],
    ),
    body: ContentFrame(
      child: FutureBuilder<Paged<AdminRow>>(
        future: _rows,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off_outlined, size: 42),
                  const SizedBox(height: 12),
                  Text(snapshot.error.toString()),
                  TextButton(
                    onPressed: _refresh,
                    child: const Text('Try again'),
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.screenPadding),
              children: [
                if (widget.section != AdminSection.drivers)
                  TextField(
                    controller: _search,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) {
                      _items = [];
                      _refresh();
                    },
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search_rounded),
                      hintText: 'Search ${_title.toLowerCase()}',
                      suffixIcon: IconButton(
                        tooltip: 'Search',
                        onPressed: () {
                          _items = [];
                          _refresh();
                        },
                        icon: const Icon(Icons.arrow_forward_rounded),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                if (snapshot.connectionState == ConnectionState.waiting &&
                    _items.isEmpty)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(40),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (_items.isEmpty)
                  const _EmptyAdminState()
                else
                  ..._items.map(_buildRow),
                if (_items.length < _total)
                  Center(
                    child: TextButton.icon(
                      onPressed: _busy
                          ? null
                          : () async {
                              setState(() => _busy = true);
                              try {
                                await _load(page: _page + 1);
                              } finally {
                                if (mounted) setState(() => _busy = false);
                              }
                            },
                      icon: const Icon(Icons.expand_more_rounded),
                      label: Text('Load more (${_items.length} of $_total)'),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    ),
  );

  Widget _buildRow(AdminRow row) {
    final title = switch (widget.section) {
      AdminSection.restaurants => row['name'] as String? ?? 'Restaurant',
      AdminSection.menu => row['name'] as String? ?? 'Menu item',
      AdminSection.customers => row['full_name'] as String? ?? 'Customer',
      AdminSection.drivers => row['driver_name'] as String? ?? 'Driver',
    };
    final subtitle = switch (widget.section) {
      AdminSection.restaurants =>
        '${row['cuisine'] ?? 'Cuisine not set'} · ${row['menu_item_count'] ?? 0} items · ${row['order_count'] ?? 0} orders · ${row['customer_count'] ?? 0} customers · ${_money(row['accepted_order_value_minor'])} accepted order value · ${row['is_available'] == true ? 'Active' : 'Inactive'}',
      AdminSection.menu =>
        '${_money(row['price_amount_minor'])} · ${row['is_available'] == true ? 'Available' : 'Unavailable'} · ${row['description'] ?? ''}',
      AdminSection.customers =>
        '${row['email']} · ${row['order_count'] ?? 0} orders · last activity ${row['last_order_at'] ?? 'no orders yet'} · ${row['is_active'] == true ? 'Active' : 'Inactive'}',
      AdminSection.drivers =>
        '${row['assigned_orders'] ?? 0} assigned orders · last assignment ${row['last_assigned_at'] ?? 'not recorded'}',
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Text(subtitle, maxLines: 3, overflow: TextOverflow.ellipsis),
        ),
        trailing: switch (widget.section) {
          AdminSection.restaurants => Wrap(
            children: [
              IconButton(
                tooltip: 'Manage menu',
                onPressed: () =>
                    context.push('/admin/restaurants/${row['id']}/menu'),
                icon: const Icon(Icons.restaurant_menu_rounded),
              ),
              IconButton(
                tooltip: 'Edit restaurant',
                onPressed: () => _edit(row),
                icon: const Icon(Icons.edit_outlined),
              ),
            ],
          ),
          AdminSection.menu => Wrap(
            children: [
              IconButton(
                tooltip: 'Preview menu item',
                onPressed: () => _previewMenuItem(row),
                icon: const Icon(Icons.visibility_outlined),
              ),
              IconButton(
                tooltip: 'Edit menu item',
                onPressed: () => _edit(row),
                icon: const Icon(Icons.edit_outlined),
              ),
            ],
          ),
          AdminSection.customers => Wrap(
            children: [
              IconButton(
                tooltip: 'View customer orders',
                onPressed: () => _showCustomerOrders(row),
                icon: const Icon(Icons.receipt_long_outlined),
              ),
              IconButton(
                tooltip: 'Edit customer',
                onPressed: () => _edit(row),
                icon: const Icon(Icons.edit_outlined),
              ),
            ],
          ),
          AdminSection.drivers => const Icon(Icons.delivery_dining_rounded),
        },
      ),
    );
  }

  Future<void> _edit([AdminRow? row]) async {
    final section = widget.section;
    if (section == AdminSection.drivers) return;
    final isCreate = row == null;
    final fields = switch (section) {
      AdminSection.restaurants => const [
        ('name', 'Restaurant name'),
        ('cuisine', 'Cuisine'),
        ('description', 'Description'),
        ('image_asset', 'Image asset path'),
      ],
      AdminSection.menu => const [
        ('name', 'Dish name'),
        ('description', 'Description'),
        ('price_amount_minor', 'Price in INR paise'),
        ('image_asset', 'Image asset path'),
        ('sort_order', 'Display order'),
      ],
      AdminSection.customers =>
        isCreate
            ? const [
                ('full_name', 'Customer name'),
                ('email', 'Email address'),
                ('password', 'Temporary password (12+ characters)'),
              ]
            : const [
                ('full_name', 'Customer name'),
                ('email', 'Email address'),
              ],
      AdminSection.drivers => const <(String, String)>[],
    };
    final controllers = {
      for (final field in fields)
        field.$1: TextEditingController(text: '${row?[field.$1] ?? ''}'),
    };
    var available =
        row == null ||
        (section == AdminSection.customers
            ? row['is_active'] != false
            : row['is_available'] != false);
    final wasAvailable = available;
    final form = GlobalKey<FormState>();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(
            '${isCreate ? 'Add' : 'Edit'} ${section == AdminSection.restaurants
                ? 'restaurant'
                : section == AdminSection.menu
                ? 'menu item'
                : 'customer'}',
          ),
          content: SizedBox(
            width: 480,
            child: Form(
              key: form,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final field in fields)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: TextFormField(
                          controller: controllers[field.$1],
                          obscureText: field.$1 == 'password',
                          maxLines: field.$1 == 'description' ? 3 : 1,
                          keyboardType: {
                            'price_amount_minor': TextInputType.number,
                            'sort_order': TextInputType.number,
                          }[field.$1],
                          decoration: InputDecoration(labelText: field.$2),
                          validator: (value) =>
                              ((value ?? '').trim().isEmpty ||
                                      (field.$1 == 'password' &&
                                          (value?.length ?? 0) < 12)) &&
                                  field.$1 != 'description' &&
                                  field.$1 != 'image_asset' &&
                                  field.$1 != 'cuisine'
                              ? (field.$1 == 'password'
                                    ? 'Use at least 12 characters'
                                    : 'Required')
                              : null,
                        ),
                      ),
                    if (section != AdminSection.customers)
                      SwitchListTile(
                        value: available,
                        title: Text(
                          section == AdminSection.menu
                              ? 'Available to order'
                              : 'Restaurant active',
                        ),
                        onChanged: (value) =>
                            setDialogState(() => available = value),
                      ),
                    if (section == AdminSection.customers)
                      SwitchListTile(
                        value: available,
                        title: const Text('Customer account active'),
                        onChanged: (value) =>
                            setDialogState(() => available = value),
                      ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (form.currentState!.validate()) {
                  Navigator.pop(dialogContext, true);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    var confirmed = true;
    if (saved == true && row != null && wasAvailable && !available && mounted) {
      confirmed =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(
                section == AdminSection.customers
                    ? 'Deactivate this customer?'
                    : 'Deactivate this listing?',
              ),
              content: const Text(
                'This is a soft deactivation. Historical orders and price records remain available.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Deactivate'),
                ),
              ],
            ),
          ) ??
          false;
    }
    if (saved == true && confirmed && mounted) {
      setState(() => _busy = true);
      try {
        final values = <String, dynamic>{};
        for (final entry in controllers.entries) {
          if (entry.value.text.isNotEmpty ||
              entry.key == 'description' ||
              entry.key == 'image_asset') {
            values[entry.key] = entry.value.text.isEmpty
                ? null
                : entry.value.text.trim();
          }
        }
        if (section == AdminSection.restaurants) {
          values['is_available'] = available;
        }
        if (section == AdminSection.menu) {
          values['is_available'] = available;
          values['currency'] = 'INR';
          values['price_amount_minor'] =
              int.tryParse(controllers['price_amount_minor']!.text) ?? -1;
          values['sort_order'] =
              int.tryParse(controllers['sort_order']!.text) ?? 0;
        }
        if (section == AdminSection.customers) {
          values['is_active'] = available;
        }
        final repository = ref.read(adminManagementRepositoryProvider);
        if (section == AdminSection.restaurants) {
          if (isCreate) {
            await repository.createRestaurant(values);
          } else {
            await repository.updateRestaurant(
              row['id'] as String,
              values,
              expectedUpdatedAt: row['updated_at'] as String?,
            );
          }
        } else if (section == AdminSection.menu) {
          if (isCreate) {
            await repository.createMenuItem(widget.restaurantId!, values);
          } else {
            await repository.updateMenuItem(
              row['id'] as String,
              values,
              expectedUpdatedAt: row['updated_at'] as String?,
            );
          }
        } else if (isCreate) {
          await repository.createCustomer(values);
        } else {
          await repository.updateCustomer(
            row['id'] as String,
            values,
            expectedUpdatedAt: row['updated_at'] as String?,
          );
        }
        _items = [];
        _refresh();
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Saved successfully')));
        }
      } on ApiException catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(error.message)));
        }
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
    for (final controller in controllers.values) {
      controller.dispose();
    }
  }

  Future<void> _previewMenuItem(AdminRow row) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      contentPadding: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 210,
              width: double.infinity,
              child: FoodImage(
                itemId: row['id'] as String,
                assetName: row['image_asset'] as String?,
                expand: true,
                rounded: false,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row['name'] as String,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(_money(row['price_amount_minor'])),
                  const SizedBox(height: 8),
                  Text(row['description'] as String? ?? 'No description'),
                  const SizedBox(height: 12),
                  Text(
                    row['is_available'] == true
                        ? 'Available to order'
                        : 'Unavailable',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        FilledButton.icon(
          onPressed: () {
            Navigator.pop(context);
            _edit(row);
          },
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Edit item'),
        ),
      ],
    ),
  );

  Future<void> _showCustomerOrders(AdminRow customer) async {
    try {
      final result = await ref
          .read(adminManagementRepositoryProvider)
          .customerOrders(customer['id'] as String);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('${customer['full_name']} · Orders'),
          content: SizedBox(
            width: 520,
            child: ListView(
              shrinkWrap: true,
              children: [
                ListTile(
                  leading: Icon(
                    customer['is_active'] == true
                        ? Icons.verified_user_outlined
                        : Icons.block_outlined,
                  ),
                  title: Text(customer['email'] as String? ?? ''),
                  subtitle: Text(
                    customer['is_active'] == true
                        ? 'Active account'
                        : 'Inactive account',
                  ),
                ),
                if (result.items.isEmpty)
                  const ListTile(title: Text('No orders yet')),
                for (final order in result.items)
                  ListTile(
                    title: Text(
                      '${order['restaurant_name']} · ${order['status']}',
                    ),
                    subtitle: Text(
                      '${_money(order['total_amount_minor'])} · ${order['created_at']}',
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      this.context.push('/admin/orders/${order['id']}');
                    },
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }
}

class AdminOrderDetailScreen extends ConsumerWidget {
  const AdminOrderDetailScreen({super.key, required this.orderId});
  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(
      title: const Text('Order inspection'),
      leading: IconButton(
        tooltip: 'Back to admin',
        onPressed: () => context.go('/admin'),
        icon: const Icon(Icons.arrow_back_rounded),
      ),
      actions: [
        TextButton(
          onPressed: () => context.go('/restaurants'),
          child: const Text('Shop as customer'),
        ),
      ],
    ),
    body: FutureBuilder<AdminRow>(
      future: ref.read(adminManagementRepositoryProvider).order(orderId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Could not load order: ${snapshot.error}'));
        }
        final order = snapshot.data;
        if (order == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = order['items'] as List<dynamic>? ?? [];
        final history = order['history'] as List<dynamic>? ?? [];
        return ContentFrame(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                '${order['status']} · ${order['id']}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Customer: ${order['customer_name']} · ${order['customer_email']}',
                      ),
                      Text(
                        'Restaurant: ${order['restaurant_name']} · ${order['restaurant_cuisine'] ?? ''}',
                      ),
                      Text('Address: ${order['delivery_address']}'),
                      Text('Driver: ${order['driver_name'] ?? 'Not assigned'}'),
                      Text(
                        'Created: ${order['created_at']} · Updated: ${order['updated_at']}',
                      ),
                      if (order['failure_reason'] != null)
                        Text('Failure: ${order['failure_reason']}'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Ordered items',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              for (final item in items)
                Card(
                  child: ListTile(
                    title: Text(item['item_name'] as String),
                    subtitle: Text(
                      '${item['quantity']} × ${_money(item['price_amount_minor'])}',
                    ),
                    trailing: Text(_money(item['line_total_minor'])),
                  ),
                ),
              ListTile(
                title: const Text('Total'),
                trailing: Text(
                  _money(order['total_amount_minor']),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Status history',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              for (final entry in history)
                ListTile(
                  leading: const Icon(
                    Icons.circle,
                    size: 12,
                    color: AppColors.primary,
                  ),
                  title: Text(entry['status'] as String),
                  subtitle: Text('${entry['source']} · ${entry['changed_at']}'),
                ),
            ],
          ),
        );
      },
    ),
  );
}

class _EmptyAdminState extends StatelessWidget {
  const _EmptyAdminState();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(40),
    child: Column(
      children: [
        Icon(Icons.inbox_outlined, size: 44),
        SizedBox(height: 8),
        Text('No records found'),
      ],
    ),
  );
}

String _money(dynamic minor) {
  final value = minor is int ? minor : int.tryParse('$minor') ?? 0;
  return '₹${(value ~/ 100)}.${(value % 100).toString().padLeft(2, '0')}';
}
