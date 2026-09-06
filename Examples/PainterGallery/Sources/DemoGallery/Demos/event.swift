import ZRenderKit
// Migrated from zrender test/event.html
extension DemoRegistry {
    static let demo_event: Demo = Demo(
        name: "event", category: "Interaction",
        summary: "Circles with live mouse handlers via Element.on (hover + drag)"
    ) { zr in
        // event.html wires per-element listeners: a draggable blue circle1 swaps the DOM
        // cursor on mouseover/mouseout, and circle2 recolors on dragenter/dragleave/drop
        // (`this.setStyle('fill', …)`), chained `.on(...).on(...).on(...)`. Element.on is
        // public and chainable (returns Self); the handlers fire live in the gallery GUI.
        // The static frame is just the two circles.

        // Recolor helper — mirrors the HTML's `this.setStyle('fill', color)`. Path's
        // setStyle(key,value) only covers common style keys (not `fill`), so we rebuild a
        // PathStyleProps and useStyle it (the same approach the shared `styled` helper uses).
        // Using the handler's `thisCtx` (defaults to the element, matching JS `this`) avoids
        // capturing the circle strongly inside its own listener (no retain cycle).
        func setFill(_ ctx: AnyObject?, _ color: String) {
            guard let p = ctx as? Path else { return }
            var st = PathStyleProps(); st.fill = .string(color); p.useStyle(st)
        }

        // circle1 — blue, draggable. The HTML's mouseover/mouseout swap the DOM cursor
        // ('move' / 'default'); there is no DOM cursor in this port, so the hover is made
        // visible by darkening the fill on mouseover and restoring blue on mouseout.
        let circle1 = styled(circle(140, 100, 40), fill: "#1e50ff")
        circle1.draggable = .true
        circle1.on("mouseover") { ctx, _ in setFill(ctx, "#0a2a99"); return nil }
        circle1.on("mouseout")  { ctx, _ in setFill(ctx, "#1e50ff"); return nil }

        // circle2 — the drop target. dragenter → red, dragleave → black, drop → green,
        // chained exactly as the HTML.
        let circle2 = styled(circle(440, 100, 80), fill: "#000000")
        circle2.on("dragenter") { ctx, _ in setFill(ctx, "#ee0000"); return nil }
               .on("dragleave") { ctx, _ in setFill(ctx, "#000000"); return nil }
               .on("drop")      { ctx, _ in setFill(ctx, "#2f9e44"); return nil }

        zr.add(circle2)
        zr.add(circle1)

        // Labels (not in the HTML) so the interaction reads in the static thumbnail.
        zr.add(text("drag me", 140, 93, "#ffffff", size: 12, align: .center))
        zr.add(text("drop target", 440, 92, "#ffffff", size: 14, align: .center))
    }
}
