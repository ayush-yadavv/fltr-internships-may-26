import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../services/storage_service.dart';
import '../../cart/data/models/cart_item.dart';
import 'models/saved_item.dart';

final savedRepositoryProvider = Provider<SavedRepository>((ref) {
  return SavedRepository(ref.watch(storageServiceProvider));
});

class SavedRepository {
  final StorageService _storage;

  SavedRepository(this._storage);

  List<SavedItem> getSavedItems() {
    final raw = _storage.getString(AppConstants.savedStorageKey);
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((e) => SavedItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveItem(CartItem cartItem) async {
    final items = getSavedItems();
    if (items.any((i) => i.productId == cartItem.productId)) return;

    final newItem = SavedItem(
      productId: cartItem.productId,
      name: cartItem.name,
      price: cartItem.price,
      imageUrl: cartItem.imageUrl,
      quantity: cartItem.quantity,
    );
    await _persist([...items, newItem]);
  }

  Future<void> removeItem(String productId) async {

  final items = getSavedItems();

  final updatedItems = items
      .where((item) => item.productId != productId)
      .toList();

  await _persist(updatedItems);

  
    
  }

  Future<void> moveToCart(String productId) async {
    // TODO: implement
    
  }

  Future<void> _persist(List<SavedItem> items) async {
    final encoded = jsonEncode(items.map((e) => e.toJson()).toList());
    await _storage.setString(AppConstants.savedStorageKey, encoded);
  }
}
