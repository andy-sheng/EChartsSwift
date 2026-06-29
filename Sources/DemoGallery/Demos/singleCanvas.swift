import ZRenderKit
// Migrated from zrender test/singleCanvas.html
extension DemoRegistry {
    static let demo_singleCanvas: Demo = Demo(
        name: "singleCanvas", category: "Rendering",
        summary: "Single-canvas grid of repeated draggable image tiles"
    ) { zr in
        // singleCanvas.html builds a 20×20 grid of identical `zrender.Image` tiles onto one
        // canvas: `new zrender.Image({ position:[i*50,j*50], scale:[1,1],
        // style:{ x:0, y:0, image:'asset/test.png', width:50, height:50 }, draggable:true })`.
        // The upstream PNG (`asset/test.png`) can't resolve here, so we substitute the same
        // self-contained 20×20 base64 PNG tile dragOrigin.swift uses; the native painter's
        // loadCGImage decodes the data-URI and scales it to 50×50. We mirror the i*50/j*50,
        // 50×50, draggable layout (scale [1,1] is identity → no scaleX/scaleY). The grid is
        // capped to fit the 1200×600 stage (20 cols × 12 rows) instead of the full 20×20.
        let tile = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABQAAAAUCAYAAACNiR0NAAAAd0lEQVR4nGP8dSLiPwMURK3IY6AUMFFsAq0NZAwpOAb3MjUAEzUNI8nA1f2WlHt5NR5DQguPk+bC1QRchEueiYHKgIkuBq4mMgKwqWMiJcCJUcfEQGXARDcDQwl4G5c8I7F5GRQBxIQtEzGG4XMRA7kGEgsGv4EAElwhSajUA98AAAAASUVORK5CYII="

        let cols = 20
        let rows = 12
        for i in 0..<cols {
            for j in 0..<rows {
                // mirror style:{ x:0, y:0, image, width:50, height:50 }
                var ist = ImageStyleProps()
                ist.image = .url(tile)
                ist.x = 0; ist.y = 0
                ist.width = 50; ist.height = 50
                let img = ZRImage()
                img.useStyle(ist)
                img.x = Double(i) * 50          // position: [i*50, j*50]
                img.y = Double(j) * 50
                img.draggable = .true           // every tile is draggable (the test's whole point)
                zr.add(img)
            }
        }
    }
}
