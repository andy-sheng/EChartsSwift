import ZRenderKit
// Migrated from zrender test/state.html
extension DemoRegistry {
    static let demo_state: Demo = Demo(
        name: "state", category: "Paint", summary: "Normal vs emphasis state styling (recolor + enlarge + rotate + shadow)"
    ) { zr in
        // state.html toggles named states (moveRight / moveDown / rotate / enlarge / changeFill / shadow)
        // on ONE rect. The state machinery (ensureState/useState/toggleState) is a Phase-2 no-op in this
        // port, so we render the two endpoints side by side: the NORMAL rect and the combined EMPHASIS
        // rect (changeFill=green + enlarge + rotate + shadow, shifted right to evoke moveRight).

        // normal: red 100x100, flat (no shadow)
        zr.add(styled(rect(110, 45, 100, 100), fill: "#c23531"))
        zr.add(text("normal", 160, 158, "#333", size: 16, align: .center))

        // emphasis: green, enlarged 110x110, rotated, with a soft drop shadow.
        // Shape centered on the element origin so rotation/origin default (0,0) spins around its center.
        var st = PathStyleProps()
        st.fill = .string("#2f9e44")
        st.shadowBlur = 20
        st.shadowColor = "rgba(0, 0, 0, 0.5)"
        st.shadowOffsetX = 4
        st.shadowOffsetY = 6
        let emph = rect(-55, -55, 110, 110)
        emph.useStyle(st)
        emph.x = 490; emph.y = 90; emph.rotation = 0.35
        zr.add(emph)
        zr.add(text("emphasis", 490, 176, "#333", size: 16, align: .center))
    }
}
