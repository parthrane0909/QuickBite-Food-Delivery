/// Catalog DTOs — verified against `GET /restaurants` and
/// `GET /restaurants/{id}/menu` (docs/api.md). The contract carries NO
/// ratings, delivery estimates or cuisine chips; the UI must not fabricate
/// them. `image_asset` is an optional local asset name the API may provide;
/// when null the app renders deterministic original placeholder art.
library;

class Restaurant {
  const Restaurant({
    required this.id,
    required this.name,
    required this.currency,
    required this.isAvailable,
    this.description,
    this.imageAsset,
  });

  final String id;
  final String name;
  final String? description;
  final String currency;
  final bool isAvailable;
  final String? imageAsset;

  factory Restaurant.fromJson(Map<String, dynamic> json) => Restaurant(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        currency: json['currency'] as String,
        isAvailable: json['is_available'] as bool,
        imageAsset: json['image_asset'] as String?,
      );
}

class MenuItem {
  const MenuItem({
    required this.id,
    required this.restaurantId,
    required this.name,
    required this.priceMinor,
    required this.currency,
    required this.isAvailable,
    required this.sortOrder,
    this.description,
    this.imageAsset,
  });

  final String id;
  final String restaurantId;
  final String name;
  final String? description;

  /// Integer minor units (1250 = ₹12.50) — authoritative server price.
  final int priceMinor;
  final String currency;
  final bool isAvailable;
  final String? imageAsset;
  final int sortOrder;

  factory MenuItem.fromJson(Map<String, dynamic> json) => MenuItem(
        id: json['id'] as String,
        restaurantId: json['restaurant_id'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        priceMinor: json['price_amount_minor'] as int,
        currency: json['currency'] as String,
        isAvailable: json['is_available'] as bool,
        imageAsset: json['image_asset'] as String?,
        sortOrder: json['sort_order'] as int,
      );
}
