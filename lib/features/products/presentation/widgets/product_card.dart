import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../cart/data/models/cart_item.dart';
import '../../../cart/providers/cart_providers.dart';
import '../../../saved/providers/saved_providers.dart';
import '../../data/models/product.dart';

class ProductCard extends ConsumerWidget {
  final Product product;

  const ProductCard({super.key, required this.product});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cartState = ref.watch(cartNotifierProvider).valueOrNull;
    final savedState = ref.watch(savedNotifierProvider).valueOrNull;

    final cartItem =
        cartState?.items.where((i) => i.productId == product.id).firstOrNull;
    final isInCart = cartItem != null;
    final isSaved = savedState?.any((i) => i.productId == product.id) ?? false;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SizedBox(
              width: double.infinity,
              child: Image.network(
                product.imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    const ColoredBox(color: Color(0xFFE0E0E0)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  style: Theme.of(context).textTheme.titleSmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '\$${product.price.toStringAsFixed(2)}',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: Colors.green[700]),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: isInCart
                          ? Container(
                              height: 40,
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .secondaryContainer,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.remove, size: 20),
                                    visualDensity: VisualDensity.compact,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSecondaryContainer,
                                    onPressed: () => ref
                                        .read(cartNotifierProvider.notifier)
                                        .decrementQuantity(product.id),
                                  ),
                                  Text(
                                    '${cartItem.quantity}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSecondaryContainer,
                                        ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.add, size: 20),
                                    visualDensity: VisualDensity.compact,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSecondaryContainer,
                                    onPressed: () => ref
                                        .read(cartNotifierProvider.notifier)
                                        .incrementQuantity(product.id),
                                  ),
                                ],
                              ),
                            )
                          : FilledButton(
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(0, 40),
                              ),
                              onPressed: () {
                                ref.read(cartNotifierProvider.notifier).addItem(
                                      CartItem(
                                        productId: product.id,
                                        name: product.name,
                                        price: product.price,
                                        imageUrl: product.imageUrl,
                                      ),
                                    );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content:
                                        Text('${product.name} added to cart'),
                                    duration: const Duration(seconds: 1),
                                  ),
                                );
                              },
                              child: const Text('Add to Cart'),
                            ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: Icon(
                        isSaved ? Icons.bookmark : Icons.bookmark_border,
                        color: isSaved ? Theme.of(context).primaryColor : null,
                      ),
                      tooltip: isSaved ? 'Remove from saved' : 'Save for later',
                      onPressed: () {
                        if (isSaved) {
                          ref
                              .read(savedNotifierProvider.notifier)
                              .removeFromSaved(product.id);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Item removed from saved'),
                              duration: Duration(seconds: 1),
                            ),
                          );
                        } else {
                          ref
                              .read(savedNotifierProvider.notifier)
                              .saveForLater(
                                CartItem(
                                  productId: product.id,
                                  name: product.name,
                                  price: product.price,
                                  imageUrl: product.imageUrl,
                                ),
                              );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Item saved for later'),
                              duration: Duration(seconds: 1),
                            ),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
