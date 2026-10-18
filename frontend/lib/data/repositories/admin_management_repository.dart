/// Authenticated repository for the admin management extension.
library;

import '../../core/network/api_client.dart';
import '../dto/paged.dart';

typedef AdminRow = Map<String, dynamic>;

class AdminManagementRepository {
  const AdminManagementRepository(this._client);
  final ApiClient _client;

  Future<Paged<AdminRow>> restaurants({
    int page = 1,
    int pageSize = 25,
    String? search,
    bool? active,
  }) async {
    final query = {'page': '$page', 'page_size': '$pageSize'};
    if (search?.trim().isNotEmpty == true) query['search'] = search!.trim();
    if (active != null) query['active'] = '$active';
    return Paged.fromJson(
      await _client.get('admin/restaurants', query: query),
      (e) => e,
    );
  }

  Future<AdminRow> createRestaurant(AdminRow values) =>
      _client.post('admin/restaurants', body: values);
  Future<AdminRow> updateRestaurant(
    String id,
    AdminRow values, {
    String? expectedUpdatedAt,
  }) => _client.patch(
    'admin/restaurants/$id',
    body: values,
    query: expectedUpdatedAt == null
        ? null
        : {'expected_updated_at': expectedUpdatedAt},
  );

  Future<Paged<AdminRow>> menu(
    String id, {
    int page = 1,
    int pageSize = 50,
    String? search,
  }) async {
    final query = {'page': '$page', 'page_size': '$pageSize'};
    if (search?.trim().isNotEmpty == true) query['search'] = search!.trim();
    return Paged.fromJson(
      await _client.get('admin/restaurants/$id/menu', query: query),
      (e) => e,
    );
  }

  Future<AdminRow> createMenuItem(String id, AdminRow values) =>
      _client.post('admin/restaurants/$id/menu', body: values);
  Future<AdminRow> updateMenuItem(
    String id,
    AdminRow values, {
    String? expectedUpdatedAt,
  }) => _client.patch(
    'admin/menu-items/$id',
    body: values,
    query: expectedUpdatedAt == null
        ? null
        : {'expected_updated_at': expectedUpdatedAt},
  );

  Future<Paged<AdminRow>> customers({
    int page = 1,
    int pageSize = 25,
    String? search,
  }) async {
    final query = {'page': '$page', 'page_size': '$pageSize'};
    if (search?.trim().isNotEmpty == true) query['search'] = search!.trim();
    return Paged.fromJson(
      await _client.get('admin/customers', query: query),
      (e) => e,
    );
  }

  Future<AdminRow> updateCustomer(
    String id,
    AdminRow values, {
    String? expectedUpdatedAt,
  }) => _client.patch(
    'admin/customers/$id',
    body: values,
    query: expectedUpdatedAt == null
        ? null
        : {'expected_updated_at': expectedUpdatedAt},
  );
  Future<AdminRow> createCustomer(AdminRow values) =>
      _client.post('admin/customers', body: values);
  Future<Paged<AdminRow>> customerOrders(String id) async =>
      Paged.fromJson(await _client.get('admin/customers/$id/orders'), (e) => e);
  Future<AdminRow> customer(String id) => _client.get('admin/customers/$id');

  Future<Paged<AdminRow>> drivers({int page = 1, int pageSize = 100}) async =>
      Paged.fromJson(
        await _client.get(
          'admin/drivers',
          query: {'page': '$page', 'page_size': '$pageSize'},
        ),
        (e) => e,
      );
  Future<AdminRow> order(String id) => _client.get('admin/orders/$id');
}
