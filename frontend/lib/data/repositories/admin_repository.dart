/// Admin repository — the two READ-ONLY admin endpoints (Milestone 5):
/// cross-customer order listing and aggregate summary counts. Admin
/// authorization is enforced server-side (403 for customers).
library;

import '../dto/admin_dto.dart';
import '../dto/paged.dart';
import '../../core/network/api_client.dart';

class AdminRepository {
  const AdminRepository(this._client);

  final ApiClient _client;

  Future<Paged<AdminOrderItem>> orders({
    int page = 1,
    int pageSize = 20,
    String? status,
  }) async {
    final query = <String, String>{'page': '$page', 'page_size': '$pageSize'};
    if (status != null && status.isNotEmpty) query['status'] = status;
    final json = await _client.get('admin/orders', query: query);
    return Paged.fromJson(json, AdminOrderItem.fromJson);
  }

  Future<AdminSummary> summary() async {
    final json = await _client.get('admin/summary');
    return AdminSummary.fromJson(json);
  }
}
