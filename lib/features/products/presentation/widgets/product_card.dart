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

    final isInCart =
        cartState?.items.any((i) => i.productId == product.id) ?? false;
    final isSaved = savedState?.any((i) => i.productId == product.id) ?? false;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 4 / 3,
            child: Image.network(
              product.imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  const ColoredBox(color: Color(0xFFE0E0E0)),
            ),
          ),
          Expanded(
            child: Padding(
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
                  const Spacer(),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: isInCart
                              ? null
                              : () {
                                  ref
                                      .read(cartNotifierProvider.notifier)
                                      .addItem(
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
                          child: Text(isInCart ? 'In Cart' : 'Add to Cart'),
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
          ),
        ],
      ),
    );
  }
}
