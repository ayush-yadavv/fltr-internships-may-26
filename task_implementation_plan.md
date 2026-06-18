# Implementation Plan — Flutter Shop Bug Fixes & Feature Completion

## Overview

Five interconnected tasks to fix three cart bugs, complete the Save For Later feature, and fill in skipped tests. All changes are minimal and targeted — no architectural changes or dependency swaps.

---

## Task 1 — Fix Race Condition in `incrementQuantity`

### Root Cause Analysis

In [cart_providers.dart](file:///run/media/ayush-yadav/New%20Volume/Projects/fltr-internships-may-26/lib/features/cart/providers/cart_providers.dart#L56-L69), `incrementQuantity` has two critical bugs that cause the race condition:

```dart
Future<void> incrementQuantity(String productId) async {
  final item = state.requireValue.items                // ① captures stale item
      .firstWhere((i) => i.productId == productId);

  await _cartRepository.persistCart(state.requireValue); // ② awaits BEFORE updating state

  state = AsyncData(state.requireValue.copyWith(        // ③ reads state.requireValue again
    items: state.requireValue.items                      //    which may have been mutated
        .map((i) => i.productId == productId             //    by a concurrent call
            ? i.copyWith(quantity: item.quantity + 1)     // ④ uses stale `item.quantity`
            : i)
        .toList(),
  ));
}
```

**Why rapid taps break it:**
1. The `await _cartRepository.persistCart(...)` introduces a 300ms delay (see [app_constants.dart](file:///run/media/ayush-yadav/New%20Volume/Projects/fltr-internships-may-26/lib/core/constants/app_constants.dart#L5), `persistDelay`).
2. During that 300ms, `item.quantity` was captured *before* the await. All three rapid calls capture quantity = 1, and each sets it to `1 + 1 = 2`.
3. Additionally, it uses `item.quantity + 1` (from the stale capture at line 57-58) instead of `i.quantity + 1` (from the current item in the map), so even sequential calls have issues.

### Fix

Rewrite `incrementQuantity` to:
1. **Capture current state into a local** variable immediately.
2. **Update state synchronously first**, then persist asynchronously — matching the pattern used by `addItem` and `removeItem`.
3. Use `i.quantity + 1` inside the `.map()` (the current item's quantity, not a stale capture).
4. Also update `total` (leads into Task 2).

#### [MODIFY] [cart_providers.dart](file:///run/media/ayush-yadav/New%20Volume/Projects/fltr-internships-may-26/lib/features/cart/providers/cart_providers.dart) — `incrementQuantity` (lines 56–69)

Replace with:
```dart
Future<void> incrementQuantity(String productId) async {
  final current = state.requireValue;
  final item = current.items.firstWhere((i) => i.productId == productId);

  final next = current.copyWith(
    items: current.items
        .map((i) => i.productId == productId
            ? i.copyWith(quantity: i.quantity + 1)
            : i)
        .toList(),
    total: current.total + item.price,
  );

  state = AsyncData(next);
  await _cartRepository.persistCart(next);
}
```

**Key changes:**
- `current` snapshot prevents stale reads across the `await` boundary.
- State is set *before* persisting — identical to `addItem`/`removeItem` pattern.
- Uses `i.quantity + 1` (not `item.quantity + 1`) to avoid stale capture.
- Updates `total` (fixes Task 2's increment path).

---

## Task 2 — Fix Cart Total Drift

### Root Cause Analysis

`CartState.total` is manually maintained as a separate field. Two methods fail to keep it in sync:

| Method | Total update? | Bug |
|---|---|---|
| [addItem](file:///run/media/ayush-yadav/New%20Volume/Projects/fltr-internships-may-26/lib/features/cart/providers/cart_providers.dart#L19-L42) | ✅ `total + item.price` | None |
| [removeItem](file:///run/media/ayush-yadav/New%20Volume/Projects/fltr-internships-may-26/lib/features/cart/providers/cart_providers.dart#L44-L54) | ✅ `total - (price × quantity)` | Relies on `total` being correct — cascading error from increment/decrement |
| [incrementQuantity](file:///run/media/ayush-yadav/New%20Volume/Projects/fltr-internships-may-26/lib/features/cart/providers/cart_providers.dart#L56-L69) | ❌ **Missing** | `total` is never updated |
| [decrementQuantity](file:///run/media/ayush-yadav/New%20Volume/Projects/fltr-internships-may-26/lib/features/cart/providers/cart_providers.dart#L71-L88) | ❌ **Missing** | `total` is never updated |

**Example of negative total:**
1. Add item ($10) → total = $10, qty = 1
2. Increment 2× → total = $10 (unchanged!), qty = 3
3. Remove item → total = $10 - ($10 × 3) = **-$20** ❌

### Fix

#### [MODIFY] [cart_providers.dart](file:///run/media/ayush-yadav/New%20Volume/Projects/fltr-internships-may-26/lib/features/cart/providers/cart_providers.dart) — `incrementQuantity` (lines 56–69)

Add `total: current.total + item.price` to the `copyWith` call. *(Already included in Task 1 fix above.)*

#### [MODIFY] [cart_providers.dart](file:///run/media/ayush-yadav/New%20Volume/Projects/fltr-internships-may-26/lib/features/cart/providers/cart_providers.dart) — `decrementQuantity` (lines 71–88)

Replace with:
```dart
Future<void> decrementQuantity(String productId) async {
  final current = state.requireValue;
  final item = current.items.firstWhere((i) => i.productId == productId);

  if (item.quantity <= 1) {
    await removeItem(productId);
    return;
  }

  final next = current.copyWith(
    items: current.items
        .map((i) => i.productId == productId
            ? i.copyWith(quantity: i.quantity - 1)
            : i)
        .toList(),
    total: current.total - item.price,
  );

  state = AsyncData(next);
  await _cartRepository.persistCart(next);
}
```

**Key changes:**
- Adds `total: current.total - item.price` to the `copyWith` call.
- Persists the **updated** state (`next`) instead of the stale `current`.

---

## Task 3 — Persist Quantity Changes After Increment/Decrement

### Root Cause Analysis

Looking at the original `incrementQuantity`:

```dart
await _cartRepository.persistCart(state.requireValue);  // persists BEFORE state update
state = AsyncData(state.requireValue.copyWith(...));     // state updated AFTER
```

The persist call saves the **old** state (before the increment). After the app restarts, `loadCart()` reads the old quantities. The state update happens *after* the persist, so the new quantity is only in memory and is lost on restart.

`decrementQuantity` has a similar issue: it persists `current` (the pre-decrement snapshot) instead of the updated state.

### Fix

Both methods are already fixed in Tasks 1 and 2 above:
- **`incrementQuantity`**: State is updated first into `next`, then `_cartRepository.persistCart(next)` is called with the **new** state.
- **`decrementQuantity`**: Same pattern — persist `next` instead of `current`.

> **IMPORTANT:** No additional code changes needed for Task 3. The fixes in Tasks 1 and 2 resolve persistence by ensuring `persistCart` is called with the updated state object.

---

## Task 4 — Complete the Save For Later Feature

Three files need implementation following the existing patterns.

### 4a. Repository Layer

#### [MODIFY] [saved_repository.dart](file:///run/media/ayush-yadav/New%20Volume/Projects/fltr-internships-may-26/lib/features/saved/data/saved_repository.dart) — `removeItem` (line 46–48)

Replace the TODO stub with:
```dart
Future<void> removeItem(String productId) async {
  final items = getSavedItems();
  final updated = items.where((i) => i.productId != productId).toList();
  await _persist(updated);
}
```

**Pattern followed:** Mirrors `saveItem` — load current list, filter, and persist.

#### [MODIFY] [saved_repository.dart](file:///run/media/ayush-yadav/New%20Volume/Projects/fltr-internships-may-26/lib/features/saved/data/saved_repository.dart) — `moveToCart` (line 50–52)

Replace the TODO stub with:
```dart
Future<void> moveToCart(String productId) async {
  final items = getSavedItems();
  final updated = items.where((i) => i.productId != productId).toList();
  await _persist(updated);
}
```

**Design note:** The repository only manages its own domain (saved items storage). It removes the item from the saved list. The *notifier* layer is responsible for coordinating the cross-feature action of adding to cart.

---

### 4b. Notifier Layer

#### [MODIFY] [saved_providers.dart](file:///run/media/ayush-yadav/New%20Volume/Projects/fltr-internships-may-26/lib/features/saved/providers/saved_providers.dart) — `removeFromSaved` (lines 38–40)

Replace the TODO stub with:
```dart
Future<void> removeFromSaved(String productId) async {
  final current = state.valueOrNull ?? [];
  await _savedRepository.removeItem(productId);
  state = AsyncData(
    current.where((i) => i.productId != productId).toList(),
  );
}
```

**Pattern followed:** Matches `saveForLater` — call repository, then update local state.

#### [MODIFY] [saved_providers.dart](file:///run/media/ayush-yadav/New%20Volume/Projects/fltr-internships-may-26/lib/features/saved/providers/saved_providers.dart) — `moveToCart` (lines 42–44)

Replace the TODO stub with:
```dart
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
```

**Cross-feature coordination:** Uses `ref.read(cartNotifierProvider.notifier)` to add the item to the cart (the import for `cart_providers.dart` already exists in the file with a `// ignore: unused_import` comment).

---

### 4c. Presentation Layer

#### [MODIFY] [saved_item_tile.dart](file:///run/media/ayush-yadav/New%20Volume/Projects/fltr-internships-may-26/lib/features/saved/presentation/widgets/saved_item_tile.dart) — `trailing` (lines 41–42)

Replace the `// TODO: add action buttons` and `SizedBox.shrink()` with action buttons that match the cart tile's pattern:

```dart
trailing: Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    IconButton(
      icon: const Icon(Icons.add_shopping_cart),
      tooltip: 'Move to cart',
      onPressed: () => ref
          .read(savedNotifierProvider.notifier)
          .moveToCart(item.productId),
    ),
    IconButton(
      icon: const Icon(Icons.delete_outline),
      color: Colors.red[400],
      tooltip: 'Remove',
      onPressed: () => ref
          .read(savedNotifierProvider.notifier)
          .removeFromSaved(item.productId),
    ),
  ],
),
```

**Imports to add** at the top of the file:
```dart
import '../../providers/saved_providers.dart';
```

---

## Task 5 — Fill in Skipped Tests

### 5a. Cart Notifier Tests

#### [MODIFY] [cart_notifier_test.dart](file:///run/media/ayush-yadav/New%20Volume/Projects/fltr-internships-may-26/test/features/cart/cart_notifier_test.dart)

**Test 1 — Rapid increment race condition** (lines 94–103):
Remove `skip`, implement body:
```dart
test('rapid incrementQuantity calls should result in the correct quantity', () async {
  await container.read(cartNotifierProvider.future);
  await container.read(cartNotifierProvider.notifier).addItem(testItem);

  // Fire 3 increments in quick succession
  await container.read(cartNotifierProvider.notifier).incrementQuantity('p1');
  await container.read(cartNotifierProvider.notifier).incrementQuantity('p1');
  await container.read(cartNotifierProvider.notifier).incrementQuantity('p1');

  final state = container.read(cartNotifierProvider).requireValue;
  expect(state.items.first.quantity, 4); // 1 initial + 3 increments
});
```

**Test 2 — Total after increment** (lines 105–113):
Remove `skip`, implement body:
```dart
test('total should reflect quantity after incrementQuantity', () async {
  await container.read(cartNotifierProvider.future);
  await container.read(cartNotifierProvider.notifier).addItem(testItem);

  await container.read(cartNotifierProvider.notifier).incrementQuantity('p1');
  await container.read(cartNotifierProvider.notifier).incrementQuantity('p1');

  final state = container.read(cartNotifierProvider).requireValue;
  expect(state.total, closeTo(30.0, 0.01)); // $10 × 3
});
```

**Test 3 — No negative total** (lines 115–124):
Remove `skip`, implement body:
```dart
test('total should not go negative after incrementing then removing', () async {
  await container.read(cartNotifierProvider.future);
  await container.read(cartNotifierProvider.notifier).addItem(testItem);

  await container.read(cartNotifierProvider.notifier).incrementQuantity('p1');
  await container.read(cartNotifierProvider.notifier).incrementQuantity('p1');

  await container.read(cartNotifierProvider.notifier).removeItem('p1');

  final state = container.read(cartNotifierProvider).requireValue;
  expect(state.items, isEmpty);
  expect(state.total, closeTo(0.0, 0.01));
});
```

**Test 4 — Persistence survives restart** (lines 126–135):
Remove `skip`, implement body:
```dart
test('quantity changes should survive an app restart', () async {
  await container.read(cartNotifierProvider.future);
  await container.read(cartNotifierProvider.notifier).addItem(testItem);
  await container.read(cartNotifierProvider.notifier).incrementQuantity('p1');

  // Capture what was persisted
  final captured = verify(() => mockRepo.persistCart(captureAny())).captured;
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
});
```

**Additional Test 5 — decrementQuantity updates total correctly** (NEW):
```dart
test('decrementQuantity updates total correctly', () async {
  await container.read(cartNotifierProvider.future);
  await container.read(cartNotifierProvider.notifier).addItem(testItem);

  // Increment to qty 3 (total = $30)
  await container.read(cartNotifierProvider.notifier).incrementQuantity('p1');
  await container.read(cartNotifierProvider.notifier).incrementQuantity('p1');

  // Decrement once → qty 2 (total = $20)
  await container.read(cartNotifierProvider.notifier).decrementQuantity('p1');

  final state = container.read(cartNotifierProvider).requireValue;
  expect(state.items.first.quantity, 2);
  expect(state.total, closeTo(20.0, 0.01));
});
```

**Additional Test 6 — decrementQuantity at qty 1 removes item and zeros total** (NEW):
```dart
test('decrementQuantity at quantity 1 removes the item and zeros total', () async {
  await container.read(cartNotifierProvider.future);
  await container.read(cartNotifierProvider.notifier).addItem(testItem);

  await container.read(cartNotifierProvider.notifier).decrementQuantity('p1');

  final state = container.read(cartNotifierProvider).requireValue;
  expect(state.items, isEmpty);
  expect(state.total, closeTo(0.0, 0.01));
});
```

**Additional Test 7 — decrementQuantity persists across restart** (NEW):
```dart
test('decrement quantity changes should survive an app restart', () async {
  await container.read(cartNotifierProvider.future);
  await container.read(cartNotifierProvider.notifier).addItem(testItem);

  // Increment to qty 3, then decrement to qty 2
  await container.read(cartNotifierProvider.notifier).incrementQuantity('p1');
  await container.read(cartNotifierProvider.notifier).incrementQuantity('p1');
  await container.read(cartNotifierProvider.notifier).decrementQuantity('p1');

  // Capture what was persisted
  final captured = verify(() => mockRepo.persistCart(captureAny())).captured;
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
```

---

### 5b. Saved Notifier Tests

#### [MODIFY] [saved_notifier_test.dart](file:///run/media/ayush-yadav/New%20Volume/Projects/fltr-internships-may-26/test/features/saved/saved_notifier_test.dart)

**Imports to add** at the top of the file:
```dart
import 'package:flutter_shop/features/cart/data/cart_repository.dart';
import 'package:flutter_shop/features/cart/data/cart_state.dart';
import 'package:flutter_shop/features/cart/providers/cart_providers.dart';
```

**Mock class to add** after the existing mock:
```dart
class MockCartRepository extends Mock implements CartRepository {}
```

**Fallback value registration** in `setUpAll`:
```dart
registerFallbackValue(const CartState());
```

**Test 1 — removeFromSaved** (lines 95–101):
Remove `skip`, implement body:
```dart
test('removeFromSaved removes the item from state', () async {
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
});
```

**Test 2 — moveToCart** (lines 103–111):
Remove `skip`, implement body:
```dart
test('moveToCart removes item from saved and adds it to cart', () async {
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
});
```

**Test 3 — Persistence across restarts** (lines 113–119):
Remove `skip`, implement body:
```dart
test('saved items persist across app restarts', () async {
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
});
```

---

## Summary of Files Changed

| File | Tasks | Change Type |
|---|---|---|
| [cart_providers.dart](file:///run/media/ayush-yadav/New%20Volume/Projects/fltr-internships-may-26/lib/features/cart/providers/cart_providers.dart) | 1, 2, 3 | Fix `incrementQuantity` and `decrementQuantity` |
| [saved_repository.dart](file:///run/media/ayush-yadav/New%20Volume/Projects/fltr-internships-may-26/lib/features/saved/data/saved_repository.dart) | 4 | Implement `removeItem`, `moveToCart` |
| [saved_providers.dart](file:///run/media/ayush-yadav/New%20Volume/Projects/fltr-internships-may-26/lib/features/saved/providers/saved_providers.dart) | 4 | Implement `removeFromSaved`, `moveToCart` |
| [saved_item_tile.dart](file:///run/media/ayush-yadav/New%20Volume/Projects/fltr-internships-may-26/lib/features/saved/presentation/widgets/saved_item_tile.dart) | 4 | Add action buttons |
| [cart_notifier_test.dart](file:///run/media/ayush-yadav/New%20Volume/Projects/fltr-internships-may-26/test/features/cart/cart_notifier_test.dart) | 5 | Implement 4 skipped tests + 3 new edge-case tests |
| [saved_notifier_test.dart](file:///run/media/ayush-yadav/New%20Volume/Projects/fltr-internships-may-26/test/features/saved/saved_notifier_test.dart) | 5 | Implement 3 skipped tests |

**Total files modified: 6** — No new files, no deletions, no architecture changes.

---

## Verification Plan

### Automated Tests
```bash
flutter test test/features/cart/cart_notifier_test.dart
flutter test test/features/saved/saved_notifier_test.dart
flutter test
```

### Manual Verification
1. Run the app, rapidly tap "+" on a cart item — quantity should increment correctly each time.
2. Verify the total always matches `Σ(price × quantity)` after any combination of add/increment/decrement/remove.
3. Increment a cart item quantity, kill the app, relaunch — quantity should persist.
4. Save an item, then tap "Remove" — item should disappear from saved list.
5. Save an item, then tap "Move to cart" — item should move to cart and disappear from saved list.
