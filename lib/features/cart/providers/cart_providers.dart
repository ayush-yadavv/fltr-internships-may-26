import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/cart_repository.dart';
import '../data/cart_state.dart';
import '../data/models/cart_item.dart';

final cartNotifierProvider =
    AsyncNotifierProvider<CartNotifier, CartState>(CartNotifier.new);

class CartNotifier extends AsyncNotifier<CartState> {
  late CartRepository _cartRepository;

  @override
  Future<CartState> build() async {
    _cartRepository = ref.read(cartRepositoryProvider);
    return _cartRepository.loadCart();
  }

  Future<void> addItem(CartItem item) async {
    final current = state.requireValue;
    final existingIndex =
        current.items.indexWhere((i) => i.productId == item.productId);

    final CartState next;
    if (existingIndex >= 0) {
      final updatedItems = [...current.items];
      updatedItems[existingIndex] = updatedItems[existingIndex]
          .copyWith(quantity: updatedItems[existingIndex].quantity + 1);
      next = current.copyWith(
        items: updatedItems,
        total: updatedItems.fold<double>(
  0.0,
  (sum, i) => sum + (i.price * i.quantity),
)
      );

    //   state = AsyncData(next);
    // await _cartRepository.persistCart(next);
    } else {
      next = current.copyWith(
        items: [...current.items, item],
       total: current.total + item.price,

       

      );
    
    }

    state = AsyncData(
      
    next
      
      );

    await _cartRepository.persistCart(next);
  }

  Future<void> removeItem(String productId) async {
    final current = state.requireValue;
    final item =
        current.items.firstWhere((i) => i.productId == productId);
    final next = current.copyWith(
      items: current.items.where((i) => i.productId != productId).toList(),
      total: current.total - (item.price * item.quantity),
    );
    state = AsyncData(next);
    await _cartRepository.persistCart(next);
  }

 Future<void> incrementQuantity(String productId) async {
  state = AsyncData(
    state.requireValue.copyWith(
      items: state.requireValue.items.map((i) {
        return i.productId == productId
            ? i.copyWith(quantity: i.quantity + 1)
            : i;
      }).toList(),
    ),
  );

  await _cartRepository.persistCart(state.requireValue);

  
}

  Future<void> decrementQuantity(String productId) async {
    final current = state.requireValue;
    final item = current.items.firstWhere((i) => i.productId == productId);

    if (item.quantity <= 1) {
      await removeItem(productId);
      return;
    }

    state = AsyncData(current.copyWith(
      items: current.items
          .map((i) => i.productId == productId
              ? i.copyWith(quantity: i.quantity - 1)
              : i)
          .toList(),
    ));
    await _cartRepository.persistCart(current);
  }
}
