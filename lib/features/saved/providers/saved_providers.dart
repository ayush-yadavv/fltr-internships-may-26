import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/saved_item.dart';
import '../data/saved_repository.dart';
import '../../cart/data/models/cart_item.dart';
// ignore: unused_import — needed when implementing moveToCart
import '../../cart/providers/cart_providers.dart';

final savedNotifierProvider =
    AsyncNotifierProvider<SavedNotifier, List<SavedItem>>(SavedNotifier.new);

class SavedNotifier extends AsyncNotifier<List<SavedItem>> {
  late SavedRepository _savedRepository;

  @override
  Future<List<SavedItem>> build() async {
    _savedRepository = ref.read(savedRepositoryProvider);
    return _savedRepository.getSavedItems();
  }

  Future<void> saveForLater(CartItem cartItem) async {
    final current = state.valueOrNull ?? [];
    if (current.any((i) => i.productId == cartItem.productId)) return;

    await _savedRepository.saveItem(cartItem);
    state = AsyncData([
      ...current,
      SavedItem(
        productId: cartItem.productId,
        name: cartItem.name,
        price: cartItem.price,
        imageUrl: cartItem.imageUrl,
        quantity: cartItem.quantity,
      ),
    ]);
  }

  Future<void> removeFromSaved(String productId) async {
    final current = state.valueOrNull ?? [];
    await _savedRepository.removeItem(productId);
    state = AsyncData(
      current.where((i) => i.productId != productId).toList(),
    );
  }

  Future<void> moveToCart(String productId) async {
    final current = state.valueOrNull ?? [];
    final item = current.firstWhere((i) => i.productId == productId);

    // Convert SavedItem → CartItem for the cart notifier
    final cartItem = CartItem(
      productId: item.productId,
      name: item.name,
      price: item.price,
      imageUrl: item.imageUrl,
      quantity: item.quantity,
    );

    // Add to cart via the cart notifier
    await ref.read(cartNotifierProvider.notifier).addItem(cartItem);

    // Remove from saved
    await _savedRepository.moveToCart(productId);
    state = AsyncData(
      current.where((i) => i.productId != productId).toList(),
    );
  }
}
