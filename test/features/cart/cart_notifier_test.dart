import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_shop/features/cart/data/cart_repository.dart';
import 'package:flutter_shop/features/cart/data/cart_state.dart';
import 'package:flutter_shop/features/cart/data/models/cart_item.dart';
import 'package:flutter_shop/features/cart/providers/cart_providers.dart';

class MockCartRepository extends Mock implements CartRepository {}

void main() {
  setUpAll(() {
    registerFallbackValue(const CartState());
  });

  late ProviderContainer container;
  late MockCartRepository mockRepo;

  const testItem = CartItem(
    productId: 'p1',
    name: 'Test Headphones',
    price: 10.00,
    imageUrl: 'https://example.com/img.jpg',
  );

  const testItem2 = CartItem(
    productId: 'p2',
    name: 'Test Keyboard',
    price: 20.00,
    imageUrl: 'https://example.com/img2.jpg',
  );

  setUp(() {
    mockRepo = MockCartRepository();
    when(() => mockRepo.loadCart()).thenReturn(const CartState());
    when(() => mockRepo.persistCart(any())).thenAnswer((_) async {});

    container = ProviderContainer(
      overrides: [
        cartRepositoryProvider.overrideWithValue(mockRepo),
      ],
    );
  });

  tearDown(() => container.dispose());

  group('CartNotifier', () {
    test('initial state is empty', () async {
      final state = await container.read(cartNotifierProvider.future);
      expect(state.items, isEmpty);
      expect(state.total, 0.0);
    });

    test('addItem adds a new product to the cart', () async {
      await container.read(cartNotifierProvider.future);
      await container.read(cartNotifierProvider.notifier).addItem(testItem);

      final state = container.read(cartNotifierProvider).requireValue;
      expect(state.items.length, 1);
      expect(state.items.first.productId, 'p1');
      expect(state.items.first.quantity, 1);
    });

    test('addItem with an existing productId increases quantity, not count',
        () async {
      await container.read(cartNotifierProvider.future);
      await container.read(cartNotifierProvider.notifier).addItem(testItem);
      await container.read(cartNotifierProvider.notifier).addItem(testItem);

      final state = container.read(cartNotifierProvider).requireValue;
      expect(state.items.length, 1);
      expect(state.items.first.quantity, 2);
    });

    test('removeItem removes the item from the cart', () async {
      await container.read(cartNotifierProvider.future);
      await container.read(cartNotifierProvider.notifier).addItem(testItem);
      await container.read(cartNotifierProvider.notifier).removeItem('p1');

      final state = container.read(cartNotifierProvider).requireValue;
      expect(state.items, isEmpty);
    });

    test('addItem updates total correctly for new items', () async {
      await container.read(cartNotifierProvider.future);
      await container.read(cartNotifierProvider.notifier).addItem(testItem);
      await container.read(cartNotifierProvider.notifier).addItem(testItem2);

      final state = container.read(cartNotifierProvider).requireValue;
      expect(state.total, closeTo(30.0, 0.01));
    });

    test(
      'rapid incrementQuantity calls should result in the correct quantity',
      () async {
        await container.read(cartNotifierProvider.future);
        await container.read(cartNotifierProvider.notifier).addItem(testItem);

        // Fire 3 increments in quick succession
        await container
            .read(cartNotifierProvider.notifier)
            .incrementQuantity('p1');
        await container
            .read(cartNotifierProvider.notifier)
            .incrementQuantity('p1');
        await container
            .read(cartNotifierProvider.notifier)
            .incrementQuantity('p1');

        final state = container.read(cartNotifierProvider).requireValue;
        expect(state.items.first.quantity, 4); // 1 initial + 3 increments
      },
    );

    test(
      'total should reflect quantity after incrementQuantity',
      () async {
        await container.read(cartNotifierProvider.future);
        await container.read(cartNotifierProvider.notifier).addItem(testItem);

        await container
            .read(cartNotifierProvider.notifier)
            .incrementQuantity('p1');
        await container
            .read(cartNotifierProvider.notifier)
            .incrementQuantity('p1');

        final state = container.read(cartNotifierProvider).requireValue;
        expect(state.total, closeTo(30.0, 0.01)); // $10 × 3
      },
    );

    test(
      'total should not go negative after incrementing then removing',
      () async {
        await container.read(cartNotifierProvider.future);
        await container.read(cartNotifierProvider.notifier).addItem(testItem);

        await container
            .read(cartNotifierProvider.notifier)
            .incrementQuantity('p1');
        await container
            .read(cartNotifierProvider.notifier)
            .incrementQuantity('p1');

        await container.read(cartNotifierProvider.notifier).removeItem('p1');

        final state = container.read(cartNotifierProvider).requireValue;
        expect(state.items, isEmpty);
        expect(state.total, closeTo(0.0, 0.01));
      },
    );

    test(
      'quantity changes should survive an app restart',
      () async {
        await container.read(cartNotifierProvider.future);
        await container.read(cartNotifierProvider.notifier).addItem(testItem);
        await container
            .read(cartNotifierProvider.notifier)
            .incrementQuantity('p1');

        // Capture what was persisted
        final captured =
            verify(() => mockRepo.persistCart(captureAny())).captured;
        final lastPersisted = captured.last as CartState;

        // Simulate restart: new container, repository returns persisted state
        when(() => mockRepo.loadCart()).thenReturn(lastPersisted);
        container.dispose();
        container = ProviderContainer(
          overrides: [cartRepositoryProvider.overrideWithValue(mockRepo)],
        );

        final state = await container.read(cartNotifierProvider.future);
        expect(state.items.first.quantity, 2);
        expect(state.total, closeTo(20.0, 0.01));
      },
    );

    test('decrementQuantity updates total correctly', () async {
      await container.read(cartNotifierProvider.future);
      await container.read(cartNotifierProvider.notifier).addItem(testItem);

      // Increment to qty 3 (total = $30)
      await container
          .read(cartNotifierProvider.notifier)
          .incrementQuantity('p1');
      await container
          .read(cartNotifierProvider.notifier)
          .incrementQuantity('p1');

      // Decrement once → qty 2 (total = $20)
      await container
          .read(cartNotifierProvider.notifier)
          .decrementQuantity('p1');

      final state = container.read(cartNotifierProvider).requireValue;
      expect(state.items.first.quantity, 2);
      expect(state.total, closeTo(20.0, 0.01));
    });

    test('decrementQuantity at quantity 1 removes the item and zeros total',
        () async {
      await container.read(cartNotifierProvider.future);
      await container.read(cartNotifierProvider.notifier).addItem(testItem);

      await container
          .read(cartNotifierProvider.notifier)
          .decrementQuantity('p1');

      final state = container.read(cartNotifierProvider).requireValue;
      expect(state.items, isEmpty);
      expect(state.total, closeTo(0.0, 0.01));
    });

    test('decrement quantity changes should survive an app restart', () async {
      await container.read(cartNotifierProvider.future);
      await container.read(cartNotifierProvider.notifier).addItem(testItem);

      // Increment to qty 3, then decrement to qty 2
      await container
          .read(cartNotifierProvider.notifier)
          .incrementQuantity('p1');
      await container
          .read(cartNotifierProvider.notifier)
          .incrementQuantity('p1');
      await container
          .read(cartNotifierProvider.notifier)
          .decrementQuantity('p1');

      // Capture what was persisted
      final captured =
          verify(() => mockRepo.persistCart(captureAny())).captured;
      final lastPersisted = captured.last as CartState;

      // Simulate restart
      when(() => mockRepo.loadCart()).thenReturn(lastPersisted);
      container.dispose();
      container = ProviderContainer(
        overrides: [cartRepositoryProvider.overrideWithValue(mockRepo)],
      );

      final state = await container.read(cartNotifierProvider.future);
      expect(state.items.first.quantity, 2);
      expect(state.total, closeTo(20.0, 0.01));
    });
  });
}
