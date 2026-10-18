/// Catalog repository: restaurant listing and restaurant menus with the
/// contract's pagination (page/page_size, max 100). The catalog contract
/// has no filters beyond pagination — the client must not invent any.
library;

import '../dto/catalog_dto.dart';
import '../dto/paged.dart';
import '../../core/network/api_client.dart';

class CatalogRepository {
  const CatalogRepository(this._client);

  final ApiClient _client;

  Future<Paged<Restaurant>> restaurants({
    int page = 1,
    int pageSize = 20,
    String? search,
    String? cuisine,
  }) async {
    final query = {'page': '$page', 'page_size': '$pageSize'};
    if (search?.trim().isNotEmpty == true) query['search'] = search!.trim();
    if (cuisine?.trim().isNotEmpty == true) query['cuisine'] = cuisine!.trim();
    final json = await _client.get('restaurants', query: query);
    return Paged.fromJson(json, Restaurant.fromJson);
  }

  /// Menu pagination matches the contract exactly: `page` + `page_size`
  /// (ascending by sort_order then id). No other query params exist.
  Future<Paged<MenuItem>> menu(
    String restaurantId, {
    int page = 1,
    int pageSize = 20,
  }) async {
    final json = await _client.get(
      'restaurants/$restaurantId/menu',
      query: {'page': '$page', 'page_size': '$pageSize'},
    );
    return Paged.fromJson(json, MenuItem.fromJson);
  }

  Future<List<String>> cuisines() async {
    final json = await _client.get('restaurants/cuisines');
    return (json['items'] as List<dynamic>).cast<String>();
  }

  /// Fetches one item directly so browser/app deep links are independent of
  /// which page of a large restaurant menu is currently loaded.
  Future<MenuItem> menuItem(String restaurantId, String itemId) async {
    final json = await _client.get('restaurants/$restaurantId/menu/$itemId');
    return MenuItem.fromJson(json);
  }
}
