---
name: swiftui-layout-pitfalls
description: MANDATORY for any view combining ScrollView, VStack, AsyncImage, or a custom Layout. Use before writing a ScrollView-based screen under Views/.
---

# SwiftUI Layout Pitfalls

## RULES — Follow these with no exceptions

1. **Use `.containerRelativeFrame(.horizontal, alignment: .leading)` to pin a VStack's width inside a ScrollView** when it contains async or variable-width content (images, chips, flow layouts). This is the **only** reliable fix for the symmetric-clipping bug.
2. **`.frame(maxWidth: .infinity)` does NOT cap width.** It *accepts up to* infinity. It tells the parent "I'll grow as wide as you offer." It does not constrain wide children.
3. **Custom `Layout` protocol `sizeThatFits` MUST return a finite size** during the measurement pass (`.unspecified` proposal). Returning `.infinity` for width or height poisons the parent chain and produces silent layout corruption.
4. **`AsyncImage` must be explicitly framed** before it loads — otherwise the natural size of the loaded image bleeds up through the parent VStack. Use `.frame(maxWidth: .infinity).frame(height: X)` or `.aspectRatio(contentMode: .fill).frame(height: X).clipped()`.
5. **Never return `proposal.width ?? .infinity` as a layout's own reported width.** Use a finite fallback (e.g., the sum of subview widths, or a concrete number).

---

## When to invoke

- Building a screen with `ScrollView { VStack { ... } }`.
- Adding `AsyncImage` to an existing layout.
- Writing or modifying a custom `Layout` (FlowLayout, WaterfallLayout, etc.).
- Debugging "my content is clipped on the left and right" or "the layout breaks only on certain posts".

## The clipping problem

```swift
// ❌ Classic symmetric-clipping bug
ScrollView {
    VStack(alignment: .leading, spacing: 12) {
        Text(post.title)
        AsyncImage(url: post.imageURL.asBackendURL)  // no frame!
        Text(post.body)
    }
    .padding()
}
```

**What happens:** A `VStack` inside a `ScrollView` sizes to the **max intrinsic width of its children**. `AsyncImage` with no `.frame` proposes its natural image width once it loads — often 2000+ px. The VStack grows to 2000 px. The ScrollView centers the oversized content. Result: symmetric edge clipping on load.

**Why `.frame(maxWidth: .infinity)` doesn't fix it:**

```swift
VStack {
    AsyncImage(url: url).frame(maxWidth: .infinity)
}
.frame(maxWidth: .infinity)  // ❌ still broken
```

`.frame(maxWidth: .infinity)` just tells the layout "I'm willing to be wide." It doesn't cap width. The AsyncImage natural size still wins during re-layout.

**The fix:**

```swift
// ✅
ScrollView {
    VStack(alignment: .leading, spacing: 12) {
        Text(post.title)
        AsyncImage(url: post.imageURL.asBackendURL) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            Color.gray.opacity(0.2)
        }
        .frame(height: 240)
        .clipped()
        Text(post.body)
    }
    .containerRelativeFrame(.horizontal, alignment: .leading)
    .padding()
}
```

`.containerRelativeFrame(.horizontal)` **pins** the width to the ScrollView's viewport. The children can no longer stretch the VStack wider than the screen.

## Custom `Layout` protocol — finite-size rule

```swift
// ❌ The Trays FlowLayout bug
struct FlowLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? .infinity, height: rowsHeight)
        //                                ^^^^^^^^^ poisons the parent
    }
}
```

When SwiftUI measures with a `.unspecified` proposal (proposal.width is `nil`), returning `.infinity` tells the parent chain "I'm infinite wide." The parent VStack adopts that and the ScrollView centers infinite content.

```swift
// ✅
func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let width = proposal.width ?? maxNaturalRowWidth(subviews: subviews)
    return CGSize(width: width, height: rowsHeight(width: width, subviews: subviews))
}
```

Always return finite values during measurement. If you don't know the width yet, compute it from subviews.

## Common pitfalls

### "I added `.frame(maxWidth: .infinity)` and it still clips"

Right — it doesn't cap width. It accepts infinity. You need `.containerRelativeFrame(.horizontal)` to actually pin.

### "Works on some posts, breaks on others"

Classic signal of a variable-width child (images, chips, links) stretching the VStack. Switch to `.containerRelativeFrame`. This is exactly the Trays PostDetail-with-tools bug.

### AsyncImage reflows content after load

Pin the frame **before** load:

```swift
AsyncImage(url: url) { $0.resizable().scaledToFill() }
    placeholder: { Color.gray.opacity(0.15) }
    .frame(height: 240)
    .clipped()
```

The placeholder takes the same frame — no reflow when the image arrives.

### FlowLayout / chip row collapses in one column

Usually means `sizeThatFits` returned `.zero` or the width proposal wasn't honored. Log the proposal and subview sizes — verify finite values come out.

### `.containerRelativeFrame` "not found"

Requires iOS 17+. If `project.yml` sets `deploymentTarget.iOS: "17.0"` (per `ios-project-structure`), you're fine.

## Template reference

No dedicated template. Apply the pattern directly in feature views.

## Related skills

- `swiftui-async-image-with-backend-paths` — the `.asBackendURL` helper used above.
- `swiftui-navigation-foundations` — many navigation-pushed detail views hit this bug.
