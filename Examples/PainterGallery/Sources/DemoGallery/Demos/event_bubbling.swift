import ZRenderKit
// Migrated from zrender test/event_bubbling.html
extension DemoRegistry {
    static let demo_event_bubbling: Demo = Demo(
        name: "event_bubbling", category: "Interaction",
        summary: "Nested Groups + click handlers; bubbling stops where g3 cancels it"
    ) { zr in
        // upstream: new Circle({ scale: [1, 1], shape: { cx: 0, cy: 0, r: 100 } })
        // The circle sits at its group's local origin (scale [1,1] is a no-op).
        let circle0 = circle(0, 0, 78)
        styled(circle0, fill: "#5470c6", stroke: "#22337a", lineWidth: 2)

        // g1 holds the circle and is positioned; then g1 ⊂ g2 ⊂ g3 ⊂ g4 — a 4-deep nest.
        let g1 = Group(); g1.add(circle0)
        g1.x = 340; g1.y = 112              // upstream position: [100, 100]
        let g2 = Group(); g2.add(g1)
        let g3 = Group(); g3.add(g2)
        let g4 = Group(); g4.add(g3)

        // A click on the circle bubbles up the parent chain: Circle → g1 → g2 → g3 → g4.
        // g3 cancels the bubble (returning `true` ≡ upstream `e.cancelBubble = true`), so
        // g4 never fires. The upstream handlers only console.log'd, so these are no-ops.
        circle0.on("click") { _, _ in nil }     // upstream logs 'Circle'
        g1.on("click") { _, _ in nil }          // upstream logs 'Group 1'
        g3.on("click") { _, _ in true }         // 'Group 3' + e.cancelBubble = true
        g4.on("click") { _, _ in nil }          // 'Group 4' should not be triggered

        zr.add(g4)

        // Caption: the bubble path (handlers don't paint, so label the intent statically).
        zr.add(text("click bubbles  Circle → g1 → g3 (cancels) → g4", 340, 14,
                    "#333", size: 14, align: .center))
    }
}
