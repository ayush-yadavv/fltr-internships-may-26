import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_shop/features/cart/data/cart_repository.dart';
import 'package:flutter_shop/features/cart/data/cart_state.dart';
import 'package:flutter_shop/features/cart/data/models/cart_item.dart';
import 'package:flutter_shop/features/cart/providers/cart_providers.dart';
import 'package:flutter_shop/features/saved/data/models/saved_item.dart';
import 'package:flutter_shop/features/saved/data/saved_repository.dart';
import 'package:flutter_shop/features/saved/providers/saved_providers.dart';

class MockSavedRepository extends Mock implements SavedRepository {}

class MockCartRepository extends Mock implements CartRepository {}

void main() {
  setUpAll(() {
    registerFallbackValue(const CartItem(
      productId: '',
      name: '',
      price: 0,
      imageUrl: '',
    ));
    registerFallbackValue(const CartState());
  });

  late ProviderContainer container;
  late MockSavedRepository mockRepo;

  const testCartItem = CartItem(
    productId: 's1',
    name: 'Saved Headphones',
    price: 25.00,
    imageUrl: 'https://example.com/img.jpg',
  );

  const expectedSavedItem = SavedItem(
    productId: 's1',
    name: 'Saved Headphones',
    price: 25.00,
    imageUrl: 'https://example.com/img.jpg',
  );

  setUp(() {
    mockRepo = MockSavedRepository();
    when(() => mockRepo.getSavedItems()).thenReturn([]);
    when(() => mockRepo.saveItem(any())).thenAnswer((_) async {});
    when(() => mockRepo.removeItem(any())).thenAnswer((_) async {});
    when(() => mockRepo.moveToCart(any())).thenAnswer((_) async {});

    container = ProviderContainer(
      overrides: [
        savedRepositoryProvider.overrideWithValue(mockRepo),
      ],
    );
  });

  tearDown(() => container.dispose());

  group('SavedNotifier', () {
    test('loads saved items from repository on init', () async {
      when(() => mockRepo.getSavedItems()).thenReturn([expectedSavedItem]);

      // Re-create container after stubbing the return value.
      container.dispose();
      container = ProviderContainer(
        overrides: [savedRepositoryProvider.overrideWithValue(mockRepo)],
      );

      final state = await container.read(savedNotifierProvider.future);
      expect(state.length, 1);
      expect(state.first.productId, 's1');
    });

    test('saveForLater adds the item to state', () async {
      await container.read(savedNotifierProvider.future);
      await container
          .read(savedNotifierProvider.notifier)
          .saveForLater(testCartItem);

      final state = container.read(savedNotifierProvider).requireValue;
      expect(state.length, 1);
      expect(state.first.productId, 's1');
      expect(state.first.price, 25.00);
    });

    test('saveForLater does not add a duplicate product', () async {
      await container.read(savedNotifierProvider.future);
      await container
          .read(savedNotifierProvider.notifier)
          .saveForLater(testCartItem);
      await container
          .read(savedNotifierProvider.notifier)
          .saveForLater(testCartItem);

      final state = container.read(savedNotifierProvider).requireValue;
      expect(state.length, 1);
    });

    test(
      'removeFromSaved removes the item from state',
      () async {
        await container.read(savedNotifierProvider.future);
        await container
            .read(savedNotifierProvider.notifier)
            .saveForLater(testCartItem);

        await container
            .read(savedNotifierProvider.notifier)
            .removeFromSaved('s1');

        final state = container.read(savedNotifierProvider).requireValue;
        expect(state, isEmpty);
        verify(() => mockRepo.removeItem('s1')).called(1);
      },
    );

    test(
      'moveToCart removes item from saved and adds it to cart',
      () async {
        final mockCartRepo = MockCartRepository();
        when(() => mockCartRepo.loadCart()).thenReturn(const CartState());
        when(() => mockCartRepo.persistCart(any())).thenAnswer((_) async {});

        container.dispose();
        container = ProviderContainer(
          overrides: [
            savedRepositoryProvider.overrideWithValue(mockRepo),
            cartRepositoryProvider.overrideWithValue(mockCartRepo),
          ],
        );

        await container.read(savedNotifierProvider.future);
        await container.read(cartNotifierProvider.future);

        await container
            .read(savedNotifierProvider.notifier)
            .saveForLater(testCartItem);

        await container
            .read(savedNotifierProvider.notifier)
            .moveToCart('s1');

        final savedState = container.read(savedNotifierProvider).requireValue;
        expect(savedState, isEmpty);

        final cartState = container.read(cartNotifierProvider).requireValue;
        expect(cartState.items.length, 1);
        expect(cartState.items.first.productId, 's1');
      },
    );

    test(
      'saved items persist across app restarts',
      () async {
        await container.read(savedNotifierProvider.future);
        await container
            .read(savedNotifierProvider.notifier)
            .saveForLater(testCartItem);

        // Simulate restart: repo now returns the saved item
        when(() => mockRepo.getSavedItems()).thenReturn([expectedSavedItem]);
        container.dispose();
        container = ProviderContainer(
          overrides: [savedRepositoryProvider.overrideWithValue(mockRepo)],
        );

        final state = await container.read(savedNotifierProvider.future);
        expect(state.length, 1);
        expect(state.first.productId, 's1');
      },
    );
  });
}

