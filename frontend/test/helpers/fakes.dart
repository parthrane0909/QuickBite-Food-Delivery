/// Test doubles: in-memory repositories implementing the SAME interfaces
/// the app uses (no HTTP in tests; the real API contract is exercised by
/// integration tests on the emulator and by the DTO contract test).
/// Fixtures mirror the verified backend JSON shapes.
library;

import 'dart:async';

import 'package:quickbite/core/network/api_exception.dart';
import 'package:quickbite/core/storage/token_storage.dart';
import 'package:quickbite/data/dto/admin_dto.dart';
import 'package:quickbite/data/dto/auth_dto.dart';
import 'package:quickbite/data/dto/catalog_dto.dart';
import 'package:quickbite/data/dto/notification_dto.dart';
import 'package:quickbite/data/dto/order_dto.dart';
import 'package:quickbite/data/dto/paged.dart';
import 'package:quickbite/data/repositories/admin_repository.dart';
import 'package:quickbite/data/repositories/auth_repository.dart';
import 'package:quickbite/data/repositories/catalog_repository.dart';
import 'package:quickbite/data/repositories/order_repository.dart';
import 'package:quickbite/domain/order_status.dart';
import 'package:quickbite/state/providers.dart';
// Riverpod 3 exports the `Override` type only from `misc.dart` (it is the
// documented surface for test doubles).
import 'package:riverpod/misc.dart' show Override;

// ------------------------------- fixtures ---------------------------------

Restaurant fixtureRestaurant({
  String id = 'rest_bella_napoli',
  String name = 'Bella Napoli',
}) =>
    Restaurant(
      id: id,
      name: name,
      description: 'Wood-fired pizza and handmade pasta',
      currency: 'INR',
      isAvailable: true,
    );

MenuItem fixtureMenuItem({
  String id = 'item_margherita_pizza',
  String name = 'Margherita Pizza',
  int priceMinor = 35000,
  bool isAvailable = true,
  String restaurantId = 'rest_bella_napoli',
}) =>
    MenuItem(
      id: id,
      restaurantId: restaurantId,
      name: name,
      description: 'San Marzano tomato, mozzarella, basil',
      priceMinor: priceMinor,
      currency: 'INR',
      isAvailable: isAvailable,
      sortOrder: 0,
    );

Session fixtureSession({
  String role = 'customer',
  String email = 'alice@quickbite.dev',
}) =>
    Session(
      accessToken: 'test-token',
      tokenType: 'bearer',
      expiresIn: 900,
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 15)),
      user: UserSummary(
        id: 'user-1',
        email: email,
        fullName: role == 'admin' ? 'Admin User' : 'Alice Customer',
        role: role,
      ),
    );

OrderDetail fixtureOrderDetail({
  String id = 'order-1',
  OrderStatus status = OrderStatus.pending,
  String? failureReason,
  String? failureCode,
}) =>
    OrderDetail(
      id: id,
      restaurantId: 'rest_bella_napoli',
      restaurantName: 'Bella Napoli',
      status: status,
      currency: 'INR',
      totalAmountMinor: 35000,
      version: status == OrderStatus.pending ? 1 : 2,
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
      deliveryAddress: '42 Test Street, Bengaluru',
      failureReason: failureReason,
      failureCode: failureCode,
      items: const [],
    );

OrderHistoryEntry fixtureHistoryEntry({
  int version = 1,
  OrderStatus status = OrderStatus.pending,
  OrderStatus? fromStatus,
}) =>
    OrderHistoryEntry(
      version: version,
      status: status,
      fromStatus: fromStatus,
      source: 'checkout',
      changedAt: DateTime.now().toUtc(),
    );

NotificationEntry fixtureNotification({
  int seq = 1,
  String type = 'order.created',
}) =>
    NotificationEntry(
      id: 'notif-$seq',
      seq: seq,
      orderId: 'order-1',
      type: type,
      message: 'Your order was created and is queued for processing.',
      createdAt: DateTime.now().toUtc(),
    );

OrderSummary fixtureOrderSummary({
  String id = 'order-1',
  OrderStatus status = OrderStatus.pending,
  String restaurantName = 'Bella Napoli',
  int totalAmountMinor = 35000,
}) =>
    OrderSummary(
      id: id,
      restaurantId: 'rest_bella_napoli',
      restaurantName: restaurantName,
      status: status,
      currency: 'INR',
      totalAmountMinor: totalAmountMinor,
      version: 1,
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
    );

AdminOrderItem fixtureAdminOrderItem({
  String id = 'order-1',
  OrderStatus status = OrderStatus.pending,
  String customerEmail = 'alice@quickbite.dev',
}) =>
    AdminOrderItem(
      id: id,
      restaurantId: 'rest_bella_napoli',
      restaurantName: 'Bella Napoli',
      status: status,
      currency: 'INR',
      totalAmountMinor: 35000,
      version: 1,
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
      customerEmail: customerEmail,
    );

// ------------------------------ auth fake ---------------------------------

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({
    this.session,
    this.meUser,
    this.loginError,
    this.meError,
    this.token,
  });

  /// Seeded token: when non-null the app restores a session on launch.
  String? token;

  Session? session;
  UserSummary? meUser;
  ApiException? loginError;
  ApiException? meError;

  int loginCalls = 0;
  int meCalls = 0;

  @override
  Future<Session> login({required String email, required String password}) async {
    loginCalls++;
    final error = loginError;
    if (error != null) throw error;
    return session ?? fixtureSession();
  }

  @override
  Future<UserSummary> me() async {
    meCalls++;
    final error = meError;
    if (error != null) throw error;
    final user = meUser;
    if (user != null) return user;
    return (session ?? fixtureSession()).user;
  }
}

// ----------------------------- catalog fake -------------------------------

class FakeCatalogRepository implements CatalogRepository {
  FakeCatalogRepository({
    List<Restaurant>? restaurantList,
    List<MenuItem>? menuItemList,
    this.restaurantsError,
    this.menuError,
  })  : restaurantList = restaurantList ?? [fixtureRestaurant()],
        menuItemList = menuItemList ?? [fixtureMenuItem()];

  List<Restaurant> restaurantList;
  List<MenuItem> menuItemList;
  ApiException? restaurantsError;
  ApiException? menuError;

  /// When set, the corresponding call suspends until the completer fires —
  /// lets tests observe real loading states.
  Completer<void>? restaurantsGate;
  Completer<void>? menuGate;

  int restaurantCalls = 0;
  int menuCalls = 0;

  @override
  Future<Paged<Restaurant>> restaurants({int page = 1, int pageSize = 20}) async {
    restaurantCalls++;
    final gate = restaurantsGate;
    if (gate != null) await gate.future;
    final error = restaurantsError;
    if (error != null) throw error;
    return Paged<Restaurant>(
      items: restaurantList,
      page: page,
      pageSize: pageSize,
      total: restaurantList.length,
    );
  }

  @override
  Future<Paged<MenuItem>> menu(String restaurantId, {int page = 1, int pageSize = 20}) async {
    menuCalls++;
    final gate = menuGate;
    if (gate != null) await gate.future;
    final error = menuError;
    if (error != null) throw error;
    return Paged<MenuItem>(
      items: menuItemList,
      page: page,
      pageSize: pageSize,
      total: menuItemList.length,
    );
  }
}

// ------------------------------ orders fake -------------------------------

class CheckoutCall {
  CheckoutCall({
    required this.idempotencyKey,
    required this.restaurantId,
    required this.deliveryAddress,
    required this.items,
  });

  final String idempotencyKey;
  final String restaurantId;
  final String deliveryAddress;
  final List<CheckoutItem> items;
}

class FakeOrderRepository implements OrderRepository {
  FakeOrderRepository({
    this.orderList = const [],
    this.detail,
    this.historyEntries = const [],
    this.notificationEntries = const [],
  });

  List<OrderSummary> orderList;
  OrderDetail? detail;
  List<OrderHistoryEntry> historyEntries;
  List<NotificationEntry> notificationEntries;

  /// FIFO of scripted checkout outcomes (CheckoutAccepted or ApiException).
  final List<Object> checkoutScript = <Object>[];
  final List<CheckoutCall> checkoutCalls = <CheckoutCall>[];

  /// Observability for tests: which statuses the server was asked to filter.
  final List<String?> orderStatusFilters = <String?>[];
  int orderCalls = 0;
  int historyCalls = 0;
  int notificationCalls = 0;

  /// When set, [order] fails with this error (polling/backoff tests).
  ApiException? orderError;

  @override
  Future<CheckoutAccepted> checkout({
    required String idempotencyKey,
    required String restaurantId,
    required String deliveryAddress,
    required List<CheckoutItem> items,
  }) async {
    checkoutCalls.add(CheckoutCall(
      idempotencyKey: idempotencyKey,
      restaurantId: restaurantId,
      deliveryAddress: deliveryAddress,
      items: items,
    ));
    final outcome = checkoutScript.isEmpty
        ? CheckoutAccepted(
            orderId: 'order-1',
            status: OrderStatus.pending,
            currency: 'INR',
            totalAmountMinor:
                items.fold<int>(0, (sum, item) => sum + 35000 * item.quantity),
            version: 1,
            message: 'Order accepted for asynchronous processing.',
          )
        : checkoutScript.removeAt(0);
    if (outcome is Exception) throw outcome;
    return outcome as CheckoutAccepted;
  }

  @override
  Future<Paged<OrderSummary>> myOrders({
    int page = 1,
    int pageSize = 20,
    String? status,
  }) async {
    orderStatusFilters.add(status);
    final filtered = status == null
        ? orderList
        : orderList.where((order) => order.status.apiValue == status).toList();
    return Paged<OrderSummary>(
      items: filtered,
      page: page,
      pageSize: pageSize,
      total: filtered.length,
    );
  }

  @override
  Future<OrderDetail> order(String orderId) async {
    orderCalls++;
    final error = orderError;
    if (error != null) throw error;
    return detail ?? fixtureOrderDetail(id: orderId);
  }

  @override
  Future<List<OrderHistoryEntry>> history(String orderId) async {
    historyCalls++;
    return historyEntries;
  }

  @override
  Future<Paged<NotificationEntry>> notifications(
    String orderId, {
    int page = 1,
    int pageSize = 20,
  }) async {
    notificationCalls++;
    return Paged<NotificationEntry>(
      items: notificationEntries,
      page: page,
      pageSize: pageSize,
      total: notificationEntries.length,
    );
  }
}

// ------------------------------ admin fake --------------------------------

class FakeAdminRepository implements AdminRepository {
  FakeAdminRepository({
    this.orderItems = const [],
    this.summaryData,
    this.ordersError,
    this.summaryError,
  });

  List<AdminOrderItem> orderItems;
  AdminSummary? summaryData;
  ApiException? ordersError;
  ApiException? summaryError;

  int ordersCalls = 0;
  int summaryCalls = 0;
  final List<String?> statusFilters = <String?>[];

  @override
  Future<Paged<AdminOrderItem>> orders({
    int page = 1,
    int pageSize = 20,
    String? status,
  }) async {
    ordersCalls++;
    statusFilters.add(status);
    final error = ordersError;
    if (error != null) throw error;
    final filtered = status == null
        ? orderItems
        : orderItems.where((item) => item.status.apiValue == status).toList();
    return Paged<AdminOrderItem>(
      items: filtered,
      page: page,
      pageSize: pageSize,
      total: filtered.length,
    );
  }

  @override
  Future<AdminSummary> summary() async {
    summaryCalls++;
    final error = summaryError;
    if (error != null) throw error;
    return summaryData ??
        AdminSummary(
          ordersByStatus: const {
            'PENDING': 2,
            'PAID': 1,
            'CONFIRMED': 0,
            'DRIVER_ASSIGNED': 3,
            'PAYMENT_FAILED': 1,
            'FAILED': 0,
          },
          pendingOutboxEvents: 5,
          retryBacklog: 2,
          quarantineRecords: 1,
          generatedAt: DateTime.now().toUtc(),
        );
  }
}

// ------------------------------ overrides ---------------------------------

class TestBackend {
  TestBackend({
    FakeAuthRepository? auth,
    FakeCatalogRepository? catalog,
    FakeOrderRepository? orders,
    FakeAdminRepository? admin,
    InMemoryTokenStorage? storage,
  })  : auth = auth ?? FakeAuthRepository(),
        catalog = catalog ?? FakeCatalogRepository(),
        orders = orders ?? FakeOrderRepository(),
        admin = admin ?? FakeAdminRepository(),
        storage = storage ?? InMemoryTokenStorage();

  final FakeAuthRepository auth;
  final FakeCatalogRepository catalog;
  final FakeOrderRepository orders;
  final FakeAdminRepository admin;
  final InMemoryTokenStorage storage;

  List<Override> get overrides => [
        tokenStorageProvider.overrideWithValue(storage),
        authRepositoryProvider.overrideWithValue(auth),
        catalogRepositoryProvider.overrideWithValue(catalog),
        orderRepositoryProvider.overrideWithValue(orders),
        adminRepositoryProvider.overrideWithValue(admin),
      ];

  /// Seed a signed-in customer (or admin) session without hitting login.
  Future<void> signIn({String role = 'customer'}) async {
    auth.session = fixtureSession(role: role);
    await storage.writeToken('test-token');
  }
}
