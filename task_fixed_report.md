# Flutter Shop — Task Fixed Report

**Author:** Ayush Yadav  
**Date:** 18 June 2026  
**Test Results:** ✅ 21/21 passing · 0 skipped · 0 failed  
**Files Modified:** 6  

---

## Table of Contents

1. [Task 1 — Incorrect quantity when tapping "+" rapidly](#task-1--incorrect-quantity-when-tapping--rapidly)
2. [Task 2 — Cart total is wrong after certain operations](#task-2--cart-total-is-wrong-after-certain-operations)
3. [Task 3 — Quantity changes are lost after restarting the app](#task-3--quantity-changes-are-lost-after-restarting-the-app)
4. [Task 4 — Complete the Save For Later feature](#task-4--complete-the-save-for-later-feature)
5. [Task 5 — Fill in the missing tests](#task-5--fill-in-the-missing-tests)
6. [Files Changed Summary](#files-changed-summary)
7. [Test Results](#test-results)

---

## Task 1 — Incorrect quantity when tapping "+" rapidly

### Symptom

Tapping the "+" button on a cart item several times in quick succession results in a lower quantity than expected. For example, tapping "+" three times sometimes only increments by one.

### Root Cause

Three bugs in `CartNotifier.incrementQuantity` (`lib/features/cart/providers/cart_providers.dart`, lines 56–69):

**Bug A — Stale item capture before `await`:**  
The method captures `item.quantity` at line 57–58 *before* the `await _cartRepository.persistCart(...)` call at line 60. `persistCart` has an artificial 300ms delay (`AppConstants.persistDelay`). During this delay, all concurrent calls read the same base quantity (e.g., `1`), so each call computes `1 + 1 = 2` instead of incrementing sequentially.

**Bug B — Stale quantity reference in `.map()`:**  
The map callback uses `item.quantity + 1` (the stale capture) instead of `i.quantity + 1` (the current item's quantity from the list), compounding the race condition.

**Bug C — State updated *after* the `await`:**  
The `state = AsyncData(...)` assignment happens after `await _cartRepository.persistCart(...)`, meaning the state is not visible to subsequent calls during the 300ms window.

### Fix

Rewrote `incrementQuantity` to follow the same pattern as `addItem` and `removeItem`:

```dart
Future<void> incrementQuantity(String productId) async {
  final current = state.requireValue;                    // ① snapshot state
  final item = current.items.firstWhere((i) => i.productId == productId);

  final next = current.copyWith(
    items: current.items
        .map((i) => i.productId == productId
            ? i.copyWith(quantity: i.quantity + 1)        // ② use i.quantity, not item.quantity
            : i)
        .toList(),
    total: current.total + item.price,                    // ③ update total (Task 2)
  );

  state = AsyncData(next);                                // ④ set state BEFORE await
  await _cartRepository.persistCart(next);                // ⑤ persist the UPDATED state (Task 3)
}
```

**Key changes:**
- `current` captures state into a local variable — prevents stale reads across `await`.
- Uses `i.quantity + 1` inside `.map()` — reads the current item's quantity, not the stale capture.
- Sets `state` synchronously *before* persisting — subsequent calls see the updated quantity immediately.

---

## Task 2 — Cart total is wrong after certain operations

### Symptom

The displayed cart total occasionally does not match the sum of `(price × quantity)` for all items. In some cases it goes negative. The issue appears after changing quantities and then removing items.

### Root Cause

`CartState.total` is a manually maintained field. The `addItem` and `removeItem` methods update it correctly, but `incrementQuantity` and `decrementQuantity` **never update `total`** at all.

This causes a cascading error:

| Step | Quantity | Actual `total` | Expected `total` |
|------|----------|----------------|------------------|
| `addItem($10)` | 1 | $10 ✅ | $10 |
| `incrementQuantity` | 2 | $10 ❌ | $20 |
| `incrementQuantity` | 3 | $10 ❌ | $30 |
| `removeItem` (subtracts `$10 × 3`) | 0 | **-$20** ❌ | $0 |

`removeItem` correctly subtracts `price × quantity`, but since `total` was never updated during increments, the subtraction drives it negative.

### Fix

Added `total` updates to both methods:

**`incrementQuantity`:**
```dart
total: current.total + item.price,
```

**`decrementQuantity`:**
```dart
total: current.total - item.price,
```

This ensures `total` stays in sync with the actual sum of `(price × quantity)` across all operations.

---

## Task 3 — Quantity changes are lost after restarting the app

### Symptom

Adding a new item to the cart persists correctly across restarts. However, increasing or decreasing the quantity of an existing item is lost when the app is killed and relaunched — the quantity always resets.

### Root Cause

**`incrementQuantity`** called `persistCart` *before* updating state:

```dart
// BEFORE (broken):
await _cartRepository.persistCart(state.requireValue);   // persists OLD state
state = AsyncData(state.requireValue.copyWith(...));     // updates state AFTER
```

The old (pre-increment) state is saved to `SharedPreferences`. On restart, `loadCart()` reads the old quantities.

**`decrementQuantity`** had a similar issue — it persisted `current` (the pre-decrement snapshot) instead of the updated state:

```dart
// BEFORE (broken):
state = AsyncData(current.copyWith(...));
await _cartRepository.persistCart(current);   // persists OLD state, not updated
```

### Fix

Both methods now persist the **updated** `next` state *after* setting it:

```dart
state = AsyncData(next);                       // update state first
await _cartRepository.persistCart(next);       // persist the NEW state
```

> **Note:** No additional code changes were needed beyond the fixes already applied in Tasks 1 and 2. The `incrementQuantity` and `decrementQuantity` rewrites resolve all three tasks simultaneously.

---

## Task 4 — Complete the Save For Later feature

### What Was Already Implemented (≈40%)

- Bookmark button on product cards saves items via `SavedNotifier.saveForLater`
- Items appear in the Saved tab via `SavedScreen`
- `SavedRepository.saveItem` and `SavedRepository._persist` work correctly

### What Was Missing

- **Remove from saved** — users could not remove an item from the saved list
- **Move to cart** — users could not move a saved item back into the cart

### Changes Made

#### 4a. Repository Layer — `lib/features/saved/data/saved_repository.dart`

**`removeItem`** — Loads saved items, filters out the target, persists:

```dart
Future<void> removeItem(String productId) async {
  final items = getSavedItems();
  final updated = items.where((i) => i.productId != productId).toList();
  await _persist(updated);
}
```

**`moveToCart`** — Same as `removeItem` at the repository level. The repository only manages saved items storage (its own domain). Cross-feature coordination (adding to cart) is handled by the notifier layer:

```dart
Future<void> moveToCart(String productId) async {
  final items = getSavedItems();
  final updated = items.where((i) => i.productId != productId).toList();
  await _persist(updated);
}
```

#### 4b. Notifier Layer — `lib/features/saved/providers/saved_providers.dart`

**`removeFromSaved`** — Delegates to repository, then updates local state:

```dart
Future<void> removeFromSaved(String productId) async {
  final current = state.valueOrNull ?? [];
  await _savedRepository.removeItem(productId);
  state = AsyncData(
    current.where((i) => i.productId != productId).toList(),
  );
}
```

**`moveToCart`** — Converts `SavedItem` → `CartItem`, adds to cart via `cartNotifierProvider`, removes from saved:

```dart
Future<void> moveToCart(String productId) async {
  final current = state.valueOrNull ?? [];
  final item = current.firstWhere((i) => i.productId == productId);

  final cartItem = CartItem(
    productId: item.productId,
    name: item.name,
    price: item.price,
    imageUrl: item.imageUrl,
    quantity: item.quantity,
  );

  await ref.read(cartNotifierProvider.notifier).addItem(cartItem);
  await _savedRepository.moveToCart(productId);
  state = AsyncData(
    current.where((i) => i.productId != productId).toList(),
  );
}
```

**Design decision:** The import for `cart_providers.dart` was already present in the file (with a `// ignore: unused_import` comment), confirming this cross-feature coordination was the intended approach.

#### 4c. Presentation Layer — `lib/features/saved/presentation/widgets/saved_item_tile.dart`

Replaced the `// TODO: add action buttons` placeholder with two `IconButton` widgets in a `Row`:

- **Move to cart** — `Icons.add_shopping_cart` icon, calls `savedNotifierProvider.notifier.moveToCart`
- **Remove** — `Icons.delete_outline` icon (red), calls `savedNotifierProvider.notifier.removeFromSaved`

Added import: `import '../../providers/saved_providers.dart';`

The button style matches the existing `CartItemTile` pattern (using `IconButton` with the same icon style and coloring conventions).

---

## Task 5 — Fill in the missing tests

### 5a. Cart Notifier Tests — `test/features/cart/cart_notifier_test.dart`

**4 previously-skipped tests implemented (skip annotations removed):**

| # | Test Name | What It Verifies |
|---|-----------|-----------------|
| 1 | `rapid incrementQuantity calls should result in the correct quantity` | 3 sequential increments → qty = 4 (Task 1 fix) |
| 2 | `total should reflect quantity after incrementQuantity` | Add $10 item, increment 2× → total = $30 (Task 2 fix) |
| 3 | `total should not go negative after incrementing then removing` | Increment 2×, remove → total = $0, not negative (Task 2 fix) |
| 4 | `quantity changes should survive an app restart` | Increment, capture persisted state, re-create container → qty = 2 (Task 3 fix) |

**3 new edge-case tests added for `decrementQuantity` coverage:**

| # | Test Name | What It Verifies |
|---|-----------|-----------------|
| 5 | `decrementQuantity updates total correctly` | Increment to qty 3, decrement once → qty = 2, total = $20 |
| 6 | `decrementQuantity at quantity 1 removes the item and zeros total` | Decrement at qty 1 → item removed, total = $0 |
| 7 | `decrement quantity changes should survive an app restart` | Increment 2×, decrement 1×, restart → qty = 2, total = $20 |

### 5b. Saved Notifier Tests — `test/features/saved/saved_notifier_test.dart`

**3 previously-skipped tests implemented (skip annotations removed):**

| # | Test Name | What It Verifies |
|---|-----------|-----------------|
| 1 | `removeFromSaved removes the item from state` | Save item, remove → state is empty, `mockRepo.removeItem` called once |
| 2 | `moveToCart removes item from saved and adds it to cart` | Save item, move to cart → saved is empty, cart has the item |
| 3 | `saved items persist across app restarts` | Save item, simulate restart with stubbed repo → item still present |

**Additional setup changes:**
- Added imports: `cart_repository.dart`, `cart_state.dart`, `cart_providers.dart`
- Added `MockCartRepository` class
- Added `registerFallbackValue(const CartState())` in `setUpAll`

---

## Files Changed Summary

| File | Tasks | Change Description |
|------|-------|--------------------|
| `lib/features/cart/providers/cart_providers.dart` | 1, 2, 3 | Rewrote `incrementQuantity` and `decrementQuantity` |
| `lib/features/saved/data/saved_repository.dart` | 4 | Implemented `removeItem` and `moveToCart` |
| `lib/features/saved/providers/saved_providers.dart` | 4 | Implemented `removeFromSaved` and `moveToCart` |
| `lib/features/saved/presentation/widgets/saved_item_tile.dart` | 4 | Added Move-to-cart and Remove action buttons |
| `test/features/cart/cart_notifier_test.dart` | 5 | Implemented 4 skipped tests + 3 new edge-case tests |
| `test/features/saved/saved_notifier_test.dart` | 5 | Implemented 3 skipped tests + added cart mock setup |

**Total:** 6 files modified · 0 new files · 0 deleted files · 0 architecture changes

---

## Test Results

```
$ flutter test
00:10 +21: All tests passed!
```

| Test Suite | Tests | Status |
|-----------|-------|--------|
| `cart_notifier_test.dart` | 11 (4 existing + 4 unskipped + 3 new) | ✅ All passing |
| `saved_notifier_test.dart` | 6 (3 existing + 3 unskipped) | ✅ All passing |
| `product_repository_test.dart` | 4 (existing, unchanged) | ✅ All passing |
| **Total** | **21** | **✅ All passing** |
