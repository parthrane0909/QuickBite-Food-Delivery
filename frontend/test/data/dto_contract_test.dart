/// DTO contract tests (M5 §7): every model parses the VERIFIED backend JSON
/// shapes from docs/api.md — literal fixtures, no builders, so a field
/// rename on either side fails loudly here first. Strict status parsing and
/// money formatting (minor units) are pinned as well.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:quickbite/core/utils/money.dart';
import 'package:quickbite/data/dto/admin_dto.dart';
import 'package:quickbite/data/dto/auth_dto.dart';
import 'package:quickbite/data/dto/catalog_dto.dart';
import 'package:quickbite/data/dto/notification_dto.dart';
import 'package:quickbite/data/dto/order_dto.dart';
import 'package:quickbite/data/dto/paged.dart';
import 'package:quickbite/domain/order_status.dart';

void main() {
  group('Session (POST /auth/login response)', () {
    test('parses token, expiry metadata and the nested user', () {
      final session = Session.fromJson(const {
        'access_token': 'jwt-token',
        'token_type': 'bearer',
        'expires_in': 900,
        'expires_at': '2026-10-17T12:00:00Z',
        'role': 'customer', // top-level convenience field; user.role wins
        'user': {
          'id': 'usr_1',
          'email': 'alice@quickbite.dev',
          'full_name': 'Alice',
          'role': 'customer',
        },
      });
      expect(session.accessToken, 'jwt-token');
      expect(session.tokenType, 'bearer');
      expect(session.expiresIn, 900);
      expect(session.expiresAt, isNotNull);
      expect(session.user.email, 'alice@quickbite.dev');
      expect(session.user.fullName, 'Alice');
      expect(session.isAdmin, isFalse);
    });

    test('parses an admin session', () {
      final session = Session.fromJson(const {
        'access_token': 'jwt-token',
        'token_type': 'bearer',
        'expires_in': 900,
        'expires_at': '2026-10-17T12:00:00Z',
        'user': {
          'id': 'usr_2',
          'email': 'admin@quickbite.dev',
          'full_name': 'Admin',
          'role': 'admin',
        },
      });
      expect(session.isAdmin, isTrue);
    });
  });

  group('Restaurant / MenuItem (GET /restaurants, GET /restaurants/{id}/menu)', () {
    test('restaurant keeps minor-unit-free catalog fields', () {
      final restaurant = Restaurant.fromJson(const {
        'id': 'rest_bella_napoli',
        'name': 'Bella Napoli',
        'description': 'Wood-fired pizza',
        'currency': 'INR',
        'is_available': true,
        'image_asset': null,
        'created_at': '2026-10-17T10:00:00Z',
      });
      expect(restaurant.id, 'rest_bella_napoli');
      expect(restaurant.name, 'Bella Napoli');
      expect(restaurant.currency, 'INR');
      expect(restaurant.isAvailable, isTrue);
    });

    test('menu item maps price_amount_minor to priceMinor', () {
      final item = MenuItem.fromJson(const {
        'id': 'item_pizza',
        'restaurant_id': 'rest_bella_napoli',
        'name': 'Margherita Pizza',
        'description': 'Tomato, mozzarella, basil',
        'price_amount_minor': 35000,
        'currency': 'INR',
        'is_available': true,
        'image_asset': null,
        'sort_order': 0,
      });
      expect(item.priceMinor, 35000);
      expect(item.restaurantId, 'rest_bella_napoli');
      expect(item.isAvailable, isTrue);
      expect(item.sortOrder, 0);
    });
  });

  group('Orders', () {
    test('accepted (202) body parses; it is acceptance, not completion', () {
      final accepted = CheckoutAccepted.fromJson(const {
        'order_id': 'order_1',
        'status': 'PENDING',
        'currency': 'INR',
        'total_amount_minor': 70000,
        'version': 1,
        'message': 'Order accepted for asynchronous processing.',
      });
      expect(accepted.orderId, 'order_1');
      expect(accepted.status, OrderStatus.pending);
      expect(accepted.totalAmountMinor, 70000);
      expect(accepted.status.isSuccess, isFalse);
    });

    test('order summary parses every status the server can send', () {
      for (final status in OrderStatus.values) {
        final summary = OrderSummary.fromJson({
          'id': 'order_1',
          'restaurant_id': 'rest_1',
          'restaurant_name': 'Bella Napoli',
          'status': status.apiValue,
          'currency': 'INR',
          'total_amount_minor': 35000,
          'version': 2,
          'failure_code': null,
          'created_at': '2026-10-17T10:00:00Z',
          'updated_at': '2026-10-17T10:05:00Z',
        });
        expect(summary.status, status);
      }
    });

    test('order detail parses lines, address and failure fields', () {
      final detail = OrderDetail.fromJson(const {
        'id': 'order_1',
        'restaurant_id': 'rest_1',
        'restaurant_name': 'Bella Napoli',
        'status': 'PAYMENT_FAILED',
        'currency': 'INR',
        'total_amount_minor': 70000,
        'version': 3,
        'failure_code': 'PAYMENT_REJECTED',
        'created_at': '2026-10-17T10:00:00Z',
        'updated_at': '2026-10-17T10:05:00Z',
        'delivery_address': '42 Test Street, Bengaluru',
        'failure_reason': 'Your card was declined.',
        'driver_id': null,
        'items': [
          {
            'menu_item_id': 'item_pizza',
            'item_name': 'Margherita Pizza',
            'price_amount_minor': 35000,
            'currency': 'INR',
            'quantity': 2,
            'line_total_minor': 70000,
          },
        ],
      });
      expect(detail.status, OrderStatus.paymentFailed);
      expect(detail.failureReason, 'Your card was declined.');
      expect(detail.failureCode, 'PAYMENT_REJECTED');
      expect(detail.deliveryAddress, '42 Test Street, Bengaluru');
      expect(detail.items, hasLength(1));
      expect(detail.items.single.lineTotalMinor, 70000);
      expect(detail.items.single.quantity, 2);
    });

    test('history entry parses from_status and source', () {
      final entry = OrderHistoryEntry.fromJson(const {
        'version': 2,
        'status': 'PAID',
        'from_status': 'PENDING',
        'failure_code': null,
        'source': 'payment_worker',
        'changed_at': '2026-10-17T10:02:00Z',
      });
      expect(entry.version, 2);
      expect(entry.status, OrderStatus.paid);
      expect(entry.fromStatus, OrderStatus.pending);
      expect(entry.source, 'payment_worker');
    });

    test('history entry without from_status (v1) parses as null', () {
      final entry = OrderHistoryEntry.fromJson(const {
        'version': 1,
        'status': 'PENDING',
        'from_status': null,
        'failure_code': null,
        'source': 'checkout',
        'changed_at': '2026-10-17T10:00:00Z',
      });
      expect(entry.fromStatus, isNull);
    });
  });

  group('Notifications (GET /orders/{id}/notifications)', () {
    test('parses seq, type, message and version', () {
      final entry = NotificationEntry.fromJson(const {
        'id': 'notif_1',
        'seq': 1,
        'order_id': 'order_1',
        'type': 'payment.failed',
        'message': 'Payment could not be verified.',
        'order_version': 3,
        'created_at': '2026-10-17T10:03:00Z',
      });
      expect(entry.seq, 1);
      expect(entry.type, 'payment.failed');
      expect(entry.orderVersion, 3);
      expect(entry.isFailure, isTrue);
    });
  });

  group('Admin (GET /admin/orders, GET /admin/summary)', () {
    test('admin order item keeps every summary field plus customer_email', () {
      final item = AdminOrderItem.fromJson(const {
        'id': 'order_1',
        'restaurant_id': 'rest_1',
        'restaurant_name': 'Bella Napoli',
        'status': 'PENDING',
        'currency': 'INR',
        'total_amount_minor': 35000,
        'version': 1,
        'failure_code': null,
        'created_at': '2026-10-17T10:00:00Z',
        'updated_at': '2026-10-17T10:00:00Z',
        'customer_email': 'alice@quickbite.dev',
      });
      expect(item.customerEmail, 'alice@quickbite.dev');
      expect(item.restaurantName, 'Bella Napoli');
      expect(item.totalAmountMinor, 35000);
    });

    test('summary parses all six status counts incl. zeros', () {
      final summary = AdminSummary.fromJson(const {
        'orders_by_status': {
          'PENDING': 2,
          'PAID': 1,
          'CONFIRMED': 0,
          'DRIVER_ASSIGNED': 3,
          'PAYMENT_FAILED': 1,
          'FAILED': 0,
        },
        'pending_outbox_events': 5,
        'retry_backlog': 2,
        'quarantine_records': 1,
        'generated_at': '2026-10-17T11:00:00Z',
      });
      expect(summary.countFor(OrderStatus.pending), 2);
      expect(summary.countFor(OrderStatus.driverAssigned), 3);
      expect(summary.countFor(OrderStatus.confirmed), 0);
      expect(summary.countFor(OrderStatus.failed), 0);
      expect(summary.pendingOutboxEvents, 5);
      expect(summary.retryBacklog, 2);
      expect(summary.quarantineRecords, 1);
    });
  });

  group('Pagination envelope', () {
    test('parses items/page/page_size/total and computes hasMore', () {
      final page = Paged<NotificationEntry>.fromJson(
        const {
          'items': [
            {
              'id': 'notif_1',
              'seq': 1,
              'order_id': 'order_1',
              'type': 'order.created',
              'message': 'Created.',
              'order_version': 1,
              'created_at': '2026-10-17T10:00:00Z',
            },
          ],
          'page': 1,
          'page_size': 20,
          'total': 3,
        },
        NotificationEntry.fromJson,
      );
      expect(page.items, hasLength(1));
      expect(page.page, 1);
      expect(page.pageSize, 20);
      expect(page.total, 3);
      expect(page.hasMore, isTrue);
    });
  });

  group('OrderStatus strict parsing (contract violations fail loudly)', () {
    test('parses all six contract values', () {
      expect(OrderStatus.parse('PENDING'), OrderStatus.pending);
      expect(OrderStatus.parse('PAID'), OrderStatus.paid);
      expect(OrderStatus.parse('CONFIRMED'), OrderStatus.confirmed);
      expect(OrderStatus.parse('DRIVER_ASSIGNED'), OrderStatus.driverAssigned);
      expect(OrderStatus.parse('PAYMENT_FAILED'), OrderStatus.paymentFailed);
      expect(OrderStatus.parse('FAILED'), OrderStatus.failed);
    });

    test('throws FormatException on an unknown status', () {
      expect(
        () => OrderStatus.parse('DELIVERED'),
        throwsFormatException,
      );
    });

    test('terminal/success/failure classification matches the assignment', () {
      expect(OrderStatus.driverAssigned.isTerminal, isTrue);
      expect(OrderStatus.driverAssigned.isSuccess, isTrue);
      expect(OrderStatus.paymentFailed.isTerminal, isTrue);
      expect(OrderStatus.paymentFailed.isFailure, isTrue);
      expect(OrderStatus.failed.isFailure, isTrue);
      expect(OrderStatus.pending.isTerminal, isFalse);
      expect(OrderStatus.paid.isTerminal, isFalse);
      expect(OrderStatus.confirmed.isTerminal, isFalse);
    });
  });

  group('Money formatting (minor units only, server-authoritative)', () {
    test('formats INR with the ₹ symbol and two decimals', () {
      expect(formatMinor(35000, 'INR'), '₹350.00');
      expect(formatMinor(0, 'INR'), '₹0.00');
    });

    test('groups thousands', () {
      expect(formatMinor(1250000, 'INR'), '₹12,500.00');
    });

    test('formats USD with the \$ symbol', () {
      expect(formatMinor(35000, 'USD'), '\$350.00');
    });
  });
}
