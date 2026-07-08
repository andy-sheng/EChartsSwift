// Ported from zrender/src/tool/parseSVG.ts — keep in sync with upstream
/*
* The zrender SVG-DOM → zrender-element parser. Upstream reads a browser SVG DOM (parseXML → Document)
* and walks it, producing a tree of zrender `Group`/`Path`/`Rect`/`Circle`/... elements with transforms
* and styles. NativePainter has no DOM, so this port parses the XML with Foundation `XMLParser` into a
* tiny read-only DOM (`ZRXMLNode`, mirroring the DOM surface parseSVG uses: `nodeName` / `nodeType` /
* `getAttribute` / `firstChild` / `nextSibling` / `textContent`) and then follows upstream faithfully.
*
* PORT SCOPE / DEFERRALS (noted where they occur):
*   - `d` attribute parsing is delegated to the ported `createFromString` (tool/ToolPath.swift), which
*     already supports the full SVG path grammar (M/L/H/V/C/S/Q/T/A/Z), so no command subset is dropped.
*   - <image> is parsed (href/x/y/width/height) into a `ZRImage`.
*   - <text>/<tspan> are parsed into `Group`+`TSpan`; the font string is computed as upstream.
*   - gradients (<lineargradient>/<radialgradient> + <stop>) are parsed; <pattern> is TODO upstream too.
*/

import Foundation

// upstream imports mapped:
//   Group / ZRImage(Image) / Circle / Rect / Ellipse / Line / Polygon / Polyline / TSpan  -> ZRenderKit graphics.
//   import * as matrix from '../core/matrix';                    -> matrix.* (ZRenderKit).
//   import { createFromString } from './path';                   -> createFromString (tool/ToolPath.swift).
//   import LinearGradient / RadialGradient / Gradient            -> ZRenderKit gradients.
//   import { parseXML } from './parseXML';                        -> `parseXML` (implemented below via XMLParser;
//                                                                     upstream's parseXML is a DOMParser wrapper).
//   import * as colorTool from './color';                        -> color.* (tool/color.swift).

// =====================================================================================================
// A minimal read-only XML DOM, built from a string via Foundation `XMLParser`. Only the surface used by
// `SVGParser` is exposed. `parseXML` returns the root <svg> element node (upstream returns the root
// `SVGElement`).
// =====================================================================================================

public final class ZRXMLNode {
    // upstream DOM: nodeType 1 == element, 3 == text.
    public static let ELEMENT_NODE = 1
    public static let TEXT_NODE = 3

    public let nodeType: Int
    // Element tag (as written) for elements; "#text" for text nodes.
    public let nodeName: String
    public var attributes: [String: String] = [:]
    public var childNodes: [ZRXMLNode] = []
    // Text payload for text nodes.
    public var textValue: String = ""
    // Parent + sibling links (weak parent to avoid a retain cycle).
    public weak var parentNode: ZRXMLNode?
    fileprivate var _indexInParent: Int = 0

    init(nodeType: Int, nodeName: String) {
        self.nodeType = nodeType
        self.nodeName = nodeName
    }

    // upstream: xmlNode.getAttribute(name) -> string | null
    public func getAttribute(_ name: String) -> String? {
        return attributes[name]
    }

    // upstream: xmlNode.firstChild
    public var firstChild: ZRXMLNode? {
        return childNodes.first
    }

    // upstream: xmlNode.nextSibling
    public var nextSibling: ZRXMLNode? {
        guard let parent = parentNode else { return nil }
        let next = _indexInParent + 1
        return next < parent.childNodes.count ? parent.childNodes[next] : nil
    }

    // upstream: xmlNode.textContent — concatenation of all descendant text. For a text node it is the
    //   text itself (parseSVG only reads `textContent` off type-3 nodes, but support both faithfully).
    public var textContent: String {
        if nodeType == ZRXMLNode.TEXT_NODE {
            return textValue
        }
        var s = ""
        for c in childNodes {
            s += c.textContent
        }
        return s
    }

    fileprivate func appendChild(_ child: ZRXMLNode) {
        child.parentNode = self
        child._indexInParent = childNodes.count
        childNodes.append(child)
    }
}

// upstream: import { parseXML } from './parseXML';  — a DOMParser wrapper returning the root element.
//   Here: drive Foundation's SAX `XMLParser` to build the `ZRXMLNode` tree and return the root element.
public func parseXML(_ xml: Any?) -> ZRXMLNode? {
    // Already parsed (Document/SVGElement in upstream). Here: accept a prebuilt ZRXMLNode.
    if let node = xml as? ZRXMLNode {
        return node
    }
    guard let str = xml as? String else {
        return nil
    }
    guard let data = str.data(using: .utf8) else {
        return nil
    }
    let builder = XMLTreeBuilder()
    let parser = XMLParser(data: data)
    parser.shouldProcessNamespaces = false   // keep prefixes like `xlink:href`
    parser.delegate = builder
    parser.parse()
    return builder.root
}

private final class XMLTreeBuilder: NSObject, XMLParserDelegate {
    var root: ZRXMLNode?
    private var stack: [ZRXMLNode] = []

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String]) {
        let node = ZRXMLNode(nodeType: ZRXMLNode.ELEMENT_NODE, nodeName: qName ?? elementName)
        node.attributes = attributeDict
        if let parent = stack.last {
            parent.appendChild(node)
        }
        else {
            root = node
        }
        stack.append(node)
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard let parent = stack.last else { return }
        // Merge adjacent text into a single trailing text node (mirrors a DOM text node).
        if let last = parent.childNodes.last, last.nodeType == ZRXMLNode.TEXT_NODE {
            last.textValue += string
        }
        else {
            let text = ZRXMLNode(nodeType: ZRXMLNode.TEXT_NODE, nodeName: "#text")
            text.textValue = string
            parent.appendChild(text)
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        if !stack.isEmpty {
            stack.removeLast()
        }
    }
}

// =====================================================================================================
// Result / named-item types (mirror `SVGParserResult` / `SVGParserResultNamedItem`).
// =====================================================================================================

// upstream: type SVGNodeTagLower = 'g' | 'rect' | ... modeled as a String.
public typealias SVGNodeTagLower = String

public final class SVGParserResultNamedItem {
    public var name: String
    // If a tag has no name attribute but its ancestor <g> is named, `namedFrom` is set to that item.
    public var namedFrom: SVGParserResultNamedItem?
    public var svgNodeTagLower: SVGNodeTagLower
    public var el: Element

    init(name: String, namedFrom: SVGParserResultNamedItem?, svgNodeTagLower: SVGNodeTagLower, el: Element) {
        self.name = name
        self.namedFrom = namedFrom
        self.svgNodeTagLower = svgNodeTagLower
        self.el = el
    }
}

// upstream: { scale, x, y }
public struct SVGViewBoxTransform {
    public var x: Double
    public var y: Double
    public var scale: Double
}

// upstream: interface SVGParserResult
public struct SVGParserResult {
    public var root: Group
    // viewport width/height (nil == not specified, upstream `null`).
    public var width: Double?
    public var height: Double?
    // declared viewBox rect, if any.
    public var viewBoxRect: RectLike?
    public var viewBoxTransform: SVGViewBoxTransform?
    public var named: [SVGParserResultNamedItem]

    public init(root: Group, width: Double?, height: Double?, viewBoxRect: RectLike?,
                viewBoxTransform: SVGViewBoxTransform?, named: [SVGParserResultNamedItem]) {
        self.root = root
        self.width = width
        self.height = height
        self.viewBoxRect = viewBoxRect
        self.viewBoxTransform = viewBoxTransform
        self.named = named
    }
}

// upstream: interface SVGParserOption
public struct SVGParserOption {
    public var width: Double?
    public var height: Double?
    public var ignoreViewBox: Bool?
    public var ignoreRootClip: Bool?
    public init(width: Double? = nil, height: Double? = nil,
                ignoreViewBox: Bool? = nil, ignoreRootClip: Bool? = nil) {
        self.width = width
        self.height = height
        self.ignoreViewBox = ignoreViewBox
        self.ignoreRootClip = ignoreRootClip
    }
}

// =====================================================================================================
// Inheritable / self style attribute maps (upstream INHERITABLE_STYLE_ATTRIBUTES_MAP / SELF_...).
// =====================================================================================================

private let INHERITABLE_STYLE_ATTRIBUTES_MAP: [String: String] = [
    "fill": "fill",
    "stroke": "stroke",
    "stroke-width": "lineWidth",
    "opacity": "opacity",
    "fill-opacity": "fillOpacity",
    "stroke-opacity": "strokeOpacity",
    "stroke-dasharray": "lineDash",
    "stroke-dashoffset": "lineDashOffset",
    "stroke-linecap": "lineCap",
    "stroke-linejoin": "lineJoin",
    "stroke-miterlimit": "miterLimit",
    "font-family": "fontFamily",
    "font-size": "fontSize",
    "font-style": "fontStyle",
    "font-weight": "fontWeight",
    "text-anchor": "textAlign",
    "visibility": "visibility",
    "display": "display"
]
private let INHERITABLE_STYLE_ATTRIBUTES_MAP_KEYS = Array(INHERITABLE_STYLE_ATTRIBUTES_MAP.keys)

private let SELF_STYLE_ATTRIBUTES_MAP: [String: String] = [
    "alignment-baseline": "textBaseline",
    "stop-color": "stopColor"
]
private let SELF_STYLE_ATTRIBUTES_MAP_KEYS = Array(SELF_STYLE_ATTRIBUTES_MAP.keys)

// upstream: type DefsUsePending = [Displayable, 'fill' | 'stroke', DefsId][];
private typealias DefsUsePending = [(Displayable, String, String)]

// upstream: DefsMap = { [id]: LinearGradientObject | RadialGradientObject | PatternObject }.
// A def is a gradient paint server or a tiled <pattern>. Modeled as a tagged enum (no untagged
// unions in Swift).
private enum SVGPaintServer {
    case gradient(Gradient)
    case pattern(Pattern)
}

// -----------------------------------------------------------------------------------------------
// Renderer seam (CONVENTIONS §9) for the SVG `<pattern>` paint server.
//
// Upstream's `patternParser` is a TODO (commented out in parseSVG.ts). This port implements it, but
// a `<pattern>` defines a *tiled graphic* and the port's `ZRenderKit.Pattern` fill only carries an
// *image* (the `string`/data-URI arm — see Graphic/Pattern.swift); the native renderer likewise
// tiles a decoded `CGImage` (CGRenderer.tilePattern), it cannot tile an arbitrary element tree.
//
// ZRenderKit has no pixel backend (the split keeps pixel-pushing in NativePainter), so rasterizing
// the pattern's content group to an image tile is delegated across the renderer seam: a backend
// installs `svgPatternRasterizer`, which rasterizes a `Group` of `width`×`height` points to a PNG
// `data:` URI. When no backend is installed the `<pattern>` resolves to `nil` (the shape gets no
// fill) — the same observable result as upstream's unimplemented TODO.
//
// DEVIATION: this rasterizes the tile eagerly while parsing, so a `<pattern>` whose *content* itself
// references another paint server via `fill="url(#id)"` (resolved later in `applyDefs`) will not pick
// up that nested paint; direct color fills in pattern content work. `patternUnits`/`patternTransform`
// (objectBoundingBox coordinates, tile transforms) are not applied — width/height are read as user
// (pixel) units.
public var svgPatternRasterizer: ((Group, Double, Double) -> String?)?

// =====================================================================================================
// SVGParser
// =====================================================================================================

private final class SVGParser {

    // upstream: private _defs: DefsMap = {}  (id -> Gradient/Pattern)
    private var _defs: [String: SVGPaintServer] = [:]
    // upstream: private _defsUsePending: DefsUsePending;
    private var _defsUsePending: DefsUsePending = []
    private var _root: Group?

    private var _textX: Double = 0
    private var _textY: Double = 0

    // upstream stores `__inheritedStyle` / `__selfStyle` directly on the element. Foundation `final class`
    //   elements can't carry ad-hoc stored props, so the parser side-tables them by object identity.
    private var _inheritedStyleMap: [ObjectIdentifier: [String: String]] = [:]
    private var _selfStyleMap: [ObjectIdentifier: [String: String]] = [:]

    func parse(_ xml: Any?, _ optIn: SVGParserOption?) -> SVGParserResult {
        let opt = optIn ?? SVGParserOption()

        let svg = parseXML(xml)
        // upstream (__DEV__): if (!svg) throw new Error('Illegal svg');
        guard let svg = svg else {
            return SVGParserResult(root: Group(), width: nil, height: nil,
                                   viewBoxRect: nil, viewBoxTransform: nil, named: [])
        }

        self._defsUsePending = []
        var root = Group()
        self._root = root
        var named: [SVGParserResultNamedItem] = []

        // parse view port
        let viewBox = svg.getAttribute("viewBox") ?? ""

        // If width/height not specified, means "100%" of `opt.width/height`.
        let width = svgParseFloat(svg.getAttribute("width") ?? (opt.width.map { numToStr($0) }))
        let height = svgParseFloat(svg.getAttribute("height") ?? (opt.height.map { numToStr($0) }))
        // If width/height not specified, set as nil for output.
        let widthOpt: Double? = width.isNaN ? nil : width
        let heightOpt: Double? = height.isNaN ? nil : height

        // Apply inline style on svg element. (upstream passes `null` defsUsePending here; the root
        //   svg element almost never carries a url(#id) fill, but route the real pending list anyway.)
        parseAttributes(svg, root, &self._defsUsePending, true, false)

        var child = svg.firstChild
        while let c = child {
            self._parseNode(c, root, &named, nil, false, false)
            child = c.nextSibling
        }

        applyDefs(self._defs, self._defsUsePending)
        self._defsUsePending = []

        var viewBoxRect: RectLike?
        var viewBoxTransform: SVGViewBoxTransform?

        if !viewBox.isEmpty {
            let viewBoxArr = splitNumberSequence(viewBox)
            // Some invalid case like viewBox: 'none'.
            if viewBoxArr.count >= 4 {
                viewBoxRect = BoundingRect(
                    svgParseFloat(viewBoxArr[0]),
                    svgParseFloat(viewBoxArr[1]),
                    svgParseFloat(viewBoxArr[2]),
                    svgParseFloat(viewBoxArr[3])
                )
            }
        }

        if let vbr = viewBoxRect, widthOpt != nil, heightOpt != nil {
            viewBoxTransform = makeViewBoxTransform(
                vbr, BoundingRect(0, 0, widthOpt!, heightOpt!)
            )

            if !(opt.ignoreViewBox ?? false) {
                // Keep the output group with no transform; wrap it in an extra group carrying the
                // viewBox transform (upstream comment preserved).
                let elRoot = root
                root = Group()
                _ = root.add(elRoot)
                elRoot.scaleX = viewBoxTransform!.scale
                elRoot.scaleY = viewBoxTransform!.scale
                elRoot.x = viewBoxTransform!.x
                elRoot.y = viewBoxTransform!.y
            }
        }

        // Some shapes might overflow the viewport, which should be clipped despite whether the viewBox
        // is used, as the SVG does.
        if !(opt.ignoreRootClip ?? false), widthOpt != nil, heightOpt != nil {
            var shape = RectShape()
            shape.x = 0; shape.y = 0; shape.width = widthOpt!; shape.height = heightOpt!
            root.setClipPath(Rect(["shape": shape as PathShape]))
        }

        return SVGParserResult(
            root: root,
            width: widthOpt,
            height: heightOpt,
            viewBoxRect: viewBoxRect,
            viewBoxTransform: viewBoxTransform,
            named: named
        )
    }

    private func _parseNode(
        _ xmlNode: ZRXMLNode,
        _ parentGroup: Group,
        _ named: inout [SVGParserResultNamedItem],
        _ namedFrom: SVGParserResultNamedItem?,
        _ isInDefsIn: Bool,
        _ isInTextIn: Bool
    ) {
        var isInDefs = isInDefsIn
        var isInText = isInTextIn

        let nodeName = xmlNode.nodeName.lowercased()

        var el: Element?
        var namedFromForSub = namedFrom

        if nodeName == "defs" {
            isInDefs = true
        }
        if nodeName == "text" {
            isInText = true
        }

        if nodeName == "defs" || nodeName == "switch" {
            // Just make <switch> displayable. Do not support the full feature of it.
            el = parentGroup
        }
        else {
            // In <defs>, elements will not be rendered.
            if !isInDefs {
                if let parser = nodeParsers[nodeName] {
                    let newEl = parser(self, xmlNode, parentGroup)
                    el = newEl

                    // Do not support empty string.
                    let nameAttr = xmlNode.getAttribute("name")
                    if let nameAttr = nameAttr, !nameAttr.isEmpty {
                        let newNamed = SVGParserResultNamedItem(
                            name: nameAttr, namedFrom: nil, svgNodeTagLower: nodeName, el: newEl
                        )
                        named.append(newNamed)
                        if nodeName == "g" {
                            namedFromForSub = newNamed
                        }
                    }
                    else if let namedFrom = namedFrom {
                        named.append(SVGParserResultNamedItem(
                            name: namedFrom.name, namedFrom: namedFrom, svgNodeTagLower: nodeName, el: newEl
                        ))
                    }

                    _ = parentGroup.add(newEl)
                }
            }

            // Whether gradients/patterns are declared in <defs> or not, they all work.
            if let parser = paintServerParsers[nodeName] {
                let def = parser(self, xmlNode)
                if let id = xmlNode.getAttribute("id"), let def = def {
                    self._defs[id] = def
                }
            }
        }

        // If xmlNode is <g>, <text>, <tspan>, <defs>, <switch>, el will be a group; traverse children.
        if let elGroup = el as? Group {
            var child = xmlNode.firstChild
            while let c = child {
                if c.nodeType == ZRXMLNode.ELEMENT_NODE {
                    self._parseNode(c, elGroup, &named, namedFromForSub, isInDefs, isInText)
                }
                // Plain text rather than a tagged node.
                else if c.nodeType == ZRXMLNode.TEXT_NODE && isInText {
                    self._parseText(c, elGroup)
                }
                child = c.nextSibling
            }
        }
    }

    @discardableResult
    private func _parseText(_ xmlNode: ZRXMLNode, _ parentGroup: Group) -> TSpan {
        var initStyle = TSpanStyleProps()
        initStyle.text = xmlNode.textContent
        let text = TSpan()
        text.useStyle(initStyle)
        text.silent = true
        text.x = self._textX
        text.y = self._textY

        inheritStyle(parentGroup, text)

        parseAttributes(xmlNode, text, &self._defsUsePending, false, false)

        applyTextAlignment(text, parentGroup)

        // Font is computed from the (typed) TSpan style fields populated by parseAttributes.
        var textStyle = text.tspanStyle!
        let fontSize = textStyle.fontSize
        if let fontSize = fontSize, fontSize < 9 {
            // PENDING
            textStyle.fontSize = 9
            text.scaleX *= fontSize / 9
            text.scaleY *= fontSize / 9
        }

        // Make font (mirrors upstream join of fontStyle/fontWeight/fontSize/fontFamily).
        if textStyle.fontSize != nil || textStyle.fontFamily != nil {
            let fs = textStyle.fontStyle.map { $0.rawValue } ?? ""
            let fw = fontWeightToString(textStyle.fontWeight)
            let px = (textStyle.fontSize ?? 12)
            let fam = textStyle.fontFamily ?? "sans-serif"
            textStyle.font = [fs, fw, numToStr(px) + "px", fam]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }
        text.useStyle(textStyle)

        if let rect = text.getBoundingRect() {
            self._textX += rect.width
        }

        _ = parentGroup.add(text)

        return text
    }

    // -------------------------------------------------------------------------------------------------
    // nodeParsers (upstream static internalField block).
    // -------------------------------------------------------------------------------------------------
    private lazy var nodeParsers: [String: (SVGParser, ZRXMLNode, Group) -> Element] = [
        "g": { this, xmlNode, parentGroup in
            let g = Group()
            this.inheritStyle(parentGroup, g)
            this.parseAttributes(xmlNode, g, &this._defsUsePending, false, false)
            return g
        },
        "rect": { this, xmlNode, parentGroup in
            let rect = Rect()
            this.inheritStyle(parentGroup, rect)
            this.parseAttributes(xmlNode, rect, &this._defsUsePending, false, false)
            var shape = RectShape()
            shape.x = svgParseFloat(xmlNode.getAttribute("x") ?? "0")
            shape.y = svgParseFloat(xmlNode.getAttribute("y") ?? "0")
            shape.width = svgParseFloat(xmlNode.getAttribute("width") ?? "0")
            shape.height = svgParseFloat(xmlNode.getAttribute("height") ?? "0")
            _ = rect.setShape(shape)
            rect.silent = true
            return rect
        },
        "circle": { this, xmlNode, parentGroup in
            let circle = Circle()
            this.inheritStyle(parentGroup, circle)
            this.parseAttributes(xmlNode, circle, &this._defsUsePending, false, false)
            var shape = CircleShape()
            shape.cx = svgParseFloat(xmlNode.getAttribute("cx") ?? "0")
            shape.cy = svgParseFloat(xmlNode.getAttribute("cy") ?? "0")
            shape.r = svgParseFloat(xmlNode.getAttribute("r") ?? "0")
            _ = circle.setShape(shape)
            circle.silent = true
            return circle
        },
        "line": { this, xmlNode, parentGroup in
            let line = Line()
            this.inheritStyle(parentGroup, line)
            this.parseAttributes(xmlNode, line, &this._defsUsePending, false, false)
            var shape = LineShape()
            shape.x1 = svgParseFloat(xmlNode.getAttribute("x1") ?? "0")
            shape.y1 = svgParseFloat(xmlNode.getAttribute("y1") ?? "0")
            shape.x2 = svgParseFloat(xmlNode.getAttribute("x2") ?? "0")
            shape.y2 = svgParseFloat(xmlNode.getAttribute("y2") ?? "0")
            _ = line.setShape(shape)
            line.silent = true
            return line
        },
        "ellipse": { this, xmlNode, parentGroup in
            let ellipse = Ellipse()
            this.inheritStyle(parentGroup, ellipse)
            this.parseAttributes(xmlNode, ellipse, &this._defsUsePending, false, false)
            var shape = EllipseShape()
            shape.cx = svgParseFloat(xmlNode.getAttribute("cx") ?? "0")
            shape.cy = svgParseFloat(xmlNode.getAttribute("cy") ?? "0")
            shape.rx = svgParseFloat(xmlNode.getAttribute("rx") ?? "0")
            shape.ry = svgParseFloat(xmlNode.getAttribute("ry") ?? "0")
            _ = ellipse.setShape(shape)
            ellipse.silent = true
            return ellipse
        },
        "polygon": { this, xmlNode, parentGroup in
            let pointsStr = xmlNode.getAttribute("points")
            var shape = PolygonShape()
            shape.points = pointsStr != nil ? parsePoints(pointsStr!) : []
            let polygon = Polygon(["shape": shape as PathShape])
            polygon.silent = true
            this.inheritStyle(parentGroup, polygon)
            this.parseAttributes(xmlNode, polygon, &this._defsUsePending, false, false)
            return polygon
        },
        "polyline": { this, xmlNode, parentGroup in
            let pointsStr = xmlNode.getAttribute("points")
            var shape = PolylineShape()
            shape.points = pointsStr != nil ? parsePoints(pointsStr!) : []
            let polyline = Polyline(["shape": shape as PathShape])
            polyline.silent = true
            this.inheritStyle(parentGroup, polyline)
            this.parseAttributes(xmlNode, polyline, &this._defsUsePending, false, false)
            return polyline
        },
        "image": { this, xmlNode, parentGroup in
            let img = ZRImage()
            this.inheritStyle(parentGroup, img)
            this.parseAttributes(xmlNode, img, &this._defsUsePending, false, false)
            var style = img.imageStyle ?? ImageStyleProps()
            if let href = xmlNode.getAttribute("xlink:href") ?? xmlNode.getAttribute("href") {
                style.image = .url(href)
            }
            style.x = svgParseFloat(xmlNode.getAttribute("x") ?? "0")
            style.y = svgParseFloat(xmlNode.getAttribute("y") ?? "0")
            style.width = svgParseFloat(xmlNode.getAttribute("width") ?? "0")
            style.height = svgParseFloat(xmlNode.getAttribute("height") ?? "0")
            img.useStyle(style)
            img.silent = true
            return img
        },
        "text": { this, xmlNode, parentGroup in
            let x = xmlNode.getAttribute("x") ?? "0"
            let y = xmlNode.getAttribute("y") ?? "0"
            let dx = xmlNode.getAttribute("dx") ?? "0"
            let dy = xmlNode.getAttribute("dy") ?? "0"
            this._textX = svgParseFloat(x) + svgParseFloat(dx)
            this._textY = svgParseFloat(y) + svgParseFloat(dy)
            let g = Group()
            this.inheritStyle(parentGroup, g)
            this.parseAttributes(xmlNode, g, &this._defsUsePending, false, true)
            return g
        },
        "tspan": { this, xmlNode, parentGroup in
            let x = xmlNode.getAttribute("x")
            let y = xmlNode.getAttribute("y")
            if let x = x { this._textX = svgParseFloat(x) }
            if let y = y { this._textY = svgParseFloat(y) }
            let dx = xmlNode.getAttribute("dx") ?? "0"
            let dy = xmlNode.getAttribute("dy") ?? "0"
            let g = Group()
            this.inheritStyle(parentGroup, g)
            this.parseAttributes(xmlNode, g, &this._defsUsePending, false, true)
            this._textX += svgParseFloat(dx)
            this._textY += svgParseFloat(dy)
            return g
        },
        "path": { this, xmlNode, parentGroup in
            // TODO svg fill rule.
            let d = xmlNode.getAttribute("d") ?? ""
            let path = createFromString(d)
            this.inheritStyle(parentGroup, path)
            this.parseAttributes(xmlNode, path, &this._defsUsePending, false, false)
            path.silent = true
            return path
        }
    ]

    // -------------------------------------------------------------------------------------------------
    // paintServerParsers (gradients + <pattern>).
    // -------------------------------------------------------------------------------------------------
    private lazy var paintServerParsers: [String: (SVGParser, ZRXMLNode) -> SVGPaintServer?] = [
        "lineargradient": { _, xmlNode in
            let x1 = Double(parseIntJS(xmlNode.getAttribute("x1") ?? "0"))
            let y1 = Double(parseIntJS(xmlNode.getAttribute("y1") ?? "0"))
            let x2 = Double(parseIntJS(xmlNode.getAttribute("x2") ?? "10"))
            let y2 = Double(parseIntJS(xmlNode.getAttribute("y2") ?? "0"))
            let gradient = LinearGradient(x1, y1, x2, y2)
            parsePaintServerUnit(xmlNode, gradient)
            parseGradientColorStops(xmlNode, gradient)
            return .gradient(gradient)
        },
        "radialgradient": { _, xmlNode in
            let cx = Double(parseIntJS(xmlNode.getAttribute("cx") ?? "0"))
            let cy = Double(parseIntJS(xmlNode.getAttribute("cy") ?? "0"))
            let r = Double(parseIntJS(xmlNode.getAttribute("r") ?? "0"))
            let gradient = RadialGradient(cx, cy, r)
            parsePaintServerUnit(xmlNode, gradient)
            parseGradientColorStops(xmlNode, gradient)
            return .gradient(gradient)
        },
        // A `<pattern>` defines a tiled graphic referenced via `fill="url(#id)"`. Upstream leaves this
        // as a TODO; the port rasterizes the pattern content group to an image tile through the
        // `svgPatternRasterizer` renderer seam (see the seam declaration above for the deviations).
        "pattern": { this, xmlNode in
            return this._parsePattern(xmlNode)
        }
    ]

    // Build the pattern's content group (its child SVG elements) and rasterize it to an image tile
    // Pattern via the renderer seam. Returns nil when the tile can't be produced (no seam installed,
    // zero size, empty rasterization) — the referencing shape then gets no fill, matching upstream's
    // unimplemented `<pattern>` TODO.
    fileprivate func _parsePattern(_ xmlNode: ZRXMLNode) -> SVGPaintServer? {
        // Tile size: read width/height as user (pixel) units (DEVIATION: patternUnits /
        // objectBoundingBox coordinates are not resolved).
        let width = svgParseFloat(xmlNode.getAttribute("width") ?? "0")
        let height = svgParseFloat(xmlNode.getAttribute("height") ?? "0")
        if width.isNaN || height.isNaN || width <= 0 || height <= 0 {
            return nil
        }

        // Parse the pattern's children into a detached content group. `_parseNode` renders direct-color
        // fills immediately (isInDefs=false); any nested `url(#id)` fill is deferred to `applyDefs` and
        // therefore not reflected in the eagerly rasterized tile (noted deviation).
        let contentGroup = Group()
        var throwaway: [SVGParserResultNamedItem] = []
        var child = xmlNode.firstChild
        while let c = child {
            if c.nodeType == ZRXMLNode.ELEMENT_NODE {
                self._parseNode(c, contentGroup, &throwaway, nil, false, false)
            }
            child = c.nextSibling
        }

        guard let rasterize = svgPatternRasterizer,
              let dataURI = rasterize(contentGroup, width, height) else {
            return nil
        }

        let pattern = Pattern(dataURI, .repeat)
        // <pattern x/y> offset (DEVIATION: patternTransform is ignored). The seam rasterizes at
        // exactly width×height points, so the tile is tiled at native size (repeat).
        pattern.x = svgParseFloat(xmlNode.getAttribute("x") ?? "0")
        pattern.y = svgParseFloat(xmlNode.getAttribute("y") ?? "0")
        return .pattern(pattern)
    }

    // -------------------------------------------------------------------------------------------------
    // inheritStyle / parseAttributes / applyTextAlignment  — operate on the parser's style side-tables.
    // -------------------------------------------------------------------------------------------------

    fileprivate func inheritStyle(_ parent: Element, _ child: Element) {
        let parentStyle = _inheritedStyleMap[ObjectIdentifier(parent)]
        if let parentStyle = parentStyle {
            var childStyle = _inheritedStyleMap[ObjectIdentifier(child)] ?? [:]
            // defaults(child, parent): keep child's own, fill in missing from parent.
            for (k, v) in parentStyle where childStyle[k] == nil {
                childStyle[k] = v
            }
            _inheritedStyleMap[ObjectIdentifier(child)] = childStyle
        }
    }

    fileprivate func parseAttributes(
        _ xmlNode: ZRXMLNode,
        _ el: Element,
        _ defsUsePending: inout DefsUsePending,
        _ onlyInlineStyle: Bool,
        _ isTextGroup: Bool
    ) {
        let oid = ObjectIdentifier(el)
        var inheritedStyle = _inheritedStyleMap[oid] ?? [:]
        var selfStyle: [String: String] = [:]

        if xmlNode.nodeType == ZRXMLNode.ELEMENT_NODE {
            parseTransformAttribute(xmlNode, el)
            parseInlineStyle(xmlNode, &inheritedStyle, &selfStyle)
            if !onlyInlineStyle {
                parseAttributeStyle(xmlNode, &inheritedStyle, &selfStyle)
            }
        }

        _inheritedStyleMap[oid] = inheritedStyle

        // Apply the resolved inheritedStyle onto the concrete element's typed style.
        applyResolvedStyle(el, inheritedStyle, &defsUsePending)

        // Because selfStyle only supports textBaseline, only text group needs it.
        if isTextGroup {
            _selfStyleMap[oid] = selfStyle
        }
    }

    // upstream parseAttributes tail: translate the inheritedStyle string bag onto disp.style.
    private func applyResolvedStyle(
        _ el: Element,
        _ inheritedStyle: [String: String],
        _ defsUsePending: inout DefsUsePending
    ) {
        // fill / stroke (may be url(#id) → pending; 'none' → nil).
        var fill: ZRColor?? = .some(nil)      // outer nil == "not set"; inner nil == cleared/pending
        var stroke: ZRColor?? = .some(nil)
        var fillSet = false
        var strokeSet = false
        if let disp = el as? Displayable {
            if let f = inheritedStyle["fill"] {
                fill = .some(getFillStrokeStyle(disp, "fill", f, &defsUsePending))
                fillSet = true
            }
            if let s = inheritedStyle["stroke"] {
                stroke = .some(getFillStrokeStyle(disp, "stroke", s, &defsUsePending))
                strokeSet = true
            }
        }

        func numAttr(_ key: String) -> Double? {
            if let v = inheritedStyle[key] { return svgParseFloat(v) }
            return nil
        }

        if let path = el as? Path {
            var style = path.pathStyle ?? PathStyleProps()
            if fillSet, case let .some(v) = fill { style.fill = v }
            if strokeSet, case let .some(v) = stroke { style.stroke = v }
            if let v = numAttr("lineWidth") { style.lineWidth = v }
            if let v = numAttr("opacity") { style.opacity = v }
            if let v = numAttr("fillOpacity") { style.fillOpacity = v }
            if let v = numAttr("strokeOpacity") { style.strokeOpacity = v }
            if let v = numAttr("miterLimit") { style.miterLimit = v }
            if let v = numAttr("lineDashOffset") { style.lineDashOffset = v }
            if let v = inheritedStyle["lineCap"] { style.lineCap = v }
            if let v = inheritedStyle["lineJoin"] { style.lineJoin = v }
            if let dash = inheritedStyle["lineDash"] {
                style.lineDash = .values(splitNumberSequence(dash).map { svgParseFloat($0) })
            }
            path.useStyle(style)
        }
        else if let text = el as? TSpan {
            var style = text.tspanStyle ?? TSpanStyleProps()
            if fillSet, case let .some(v) = fill { style.fill = v }
            if strokeSet, case let .some(v) = stroke { style.stroke = v }
            if let v = numAttr("lineWidth") { style.lineWidth = v }
            if let v = numAttr("opacity") { style.opacity = v }
            if let v = numAttr("fontSize") { style.fontSize = v }
            if let v = inheritedStyle["fontFamily"] { style.fontFamily = v }
            if let v = inheritedStyle["fontStyle"] { style.fontStyle = FontStyle(rawValue: v) }
            if let v = inheritedStyle["fontWeight"] { style.fontWeight = parseFontWeight(v) }
            if let v = inheritedStyle["textAlign"] { style.textAlign = v }
            text.useStyle(style)
        }
        // Group / ZRImage: only visibility/display + inheritance (tracked in the maps) matter.

        // visibility / display map to invisible / ignore on any Displayable.
        if let disp = el as? Displayable {
            let vis = inheritedStyle["visibility"]
            if vis == "hidden" || vis == "collapse" {
                disp.invisible = true
            }
        }
        if inheritedStyle["display"] == "none" {
            el.ignore = true
        }
    }

    fileprivate func applyTextAlignment(_ text: TSpan, _ parentGroup: Group) {
        var style = text.tspanStyle ?? TSpanStyleProps()
        let parentSelfStyle = _selfStyleMap[ObjectIdentifier(parentGroup)]
        if let parentSelfStyle = parentSelfStyle {
            let textBaseline = parentSelfStyle["textBaseline"]
            var zrTextBaseline = textBaseline
            if textBaseline == nil || textBaseline == "auto" {
                zrTextBaseline = "alphabetic"
            }
            else if textBaseline == "baseline" {
                zrTextBaseline = "alphabetic"
            }
            else if textBaseline == "before-edge" || textBaseline == "text-before-edge" {
                zrTextBaseline = "top"
            }
            else if textBaseline == "after-edge" || textBaseline == "text-after-edge" {
                zrTextBaseline = "bottom"
            }
            else if textBaseline == "central" || textBaseline == "mathematical" {
                zrTextBaseline = "middle"
            }
            style.textBaseline = zrTextBaseline
        }

        let parentInheritedStyle = _inheritedStyleMap[ObjectIdentifier(parentGroup)]
        if let parentInheritedStyle = parentInheritedStyle {
            let textAlign = parentInheritedStyle["textAlign"]
            if var zrTextAlign = textAlign {
                if textAlign == "middle" {
                    zrTextAlign = "center"
                }
                style.textAlign = zrTextAlign
            }
        }
        text.useStyle(style)
    }
}

// upstream: applyDefs — resolve pending url(#id) fills/strokes to the parsed paint server.
private func applyDefs(_ defs: [String: SVGPaintServer], _ defsUsePending: DefsUsePending) {
    for item in defsUsePending {
        let (el, method, id) = item
        guard let def = defs[id] else { continue }
        let color: ZRColor?
        switch def {
        case .gradient(let grad):
            if let lg = grad as? LinearGradient { color = .linearGradient(lg) }
            else if let rg = grad as? RadialGradient { color = .radialGradient(rg) }
            else { color = nil }
        case .pattern(let pattern):
            color = .pattern(pattern)
        }
        guard let color = color else { continue }
        if let path = el as? Path {
            var s = path.pathStyle ?? PathStyleProps()
            if method == "fill" { s.fill = color } else { s.stroke = color }
            path.useStyle(s)
        }
        else if let text = el as? TSpan {
            var s = text.tspanStyle ?? TSpanStyleProps()
            if method == "fill" { s.fill = color } else { s.stroke = color }
            text.useStyle(s)
        }
    }
}

// upstream: parsePaintServerUnit
private func parsePaintServerUnit(_ xmlNode: ZRXMLNode, _ gradient: Gradient) {
    let gradientUnits = xmlNode.getAttribute("gradientUnits")
    if gradientUnits == "userSpaceOnUse" {
        gradient.global = true
    }
}

// upstream: parseGradientColorStops
private func parseGradientColorStops(_ xmlNode: ZRXMLNode, _ gradient: Gradient) {
    var stop = xmlNode.firstChild
    while let s = stop {
        if s.nodeType == ZRXMLNode.ELEMENT_NODE && s.nodeName.lowercased() == "stop" {
            let offsetStr = s.getAttribute("offset")
            var offset: Double
            if let offsetStr = offsetStr, offsetStr.contains("%") {
                offset = Double(parseIntJS(offsetStr)) / 100
            }
            else if let offsetStr = offsetStr {
                offset = svgParseFloat(offsetStr)
            }
            else {
                offset = 0
            }

            // <stop style="stop-color:red"/> has higher priority than <stop stop-color="red"/>.
            // (upstream passes the same object as both results; Swift forbids inout aliasing, so use
            //  two dicts and merge — `stopColor` lands in the SELF map, `stopOpacity` in neither.)
            var styleInh: [String: String] = [:]
            var styleSelf: [String: String] = [:]
            parseInlineStyle(s, &styleInh, &styleSelf)
            var styleVals = styleInh
            for (k, v) in styleSelf { styleVals[k] = v }
            var stopColor = styleVals["stopColor"]
                ?? s.getAttribute("stop-color")
                ?? "#000000"
            let stopOpacity = styleVals["stopOpacity"] ?? s.getAttribute("stop-opacity")
            if let stopOpacity = stopOpacity {
                if var rgba = color.parse(stopColor) {
                    let stopColorOpacity = rgba.count > 3 ? rgba[3] : 0
                    if stopColorOpacity != 0 {
                        rgba[3] *= color.parseCssFloat(.string(stopOpacity))
                        stopColor = color.stringify(rgba, "rgba") ?? stopColor
                    }
                }
            }

            gradient.colorStops.append(GradientColorStop(offset: offset, color: stopColor))
        }
        stop = s.nextSibling
    }
}

// upstream: parsePoints — number sequence → [[x, y], ...]. Here → [VectorArray] (poly shape points).
private func parsePoints(_ pointsString: String) -> [VectorArray] {
    let list = splitNumberSequence(pointsString)
    var points: [VectorArray] = []
    var i = 0
    while i < list.count {
        let x = svgParseFloat(list[i])
        let y = i + 1 < list.count ? svgParseFloat(list[i + 1]) : Double.nan
        points.append(VectorArray(x, y))
        i += 2
    }
    return points
}

// Support `fill:url(#someId)`.
private let urlRegex = try! NSRegularExpression(pattern: "^url\\(\\s*#(.*?)\\)")
// upstream: getFillStrokeStyle — resolve a fill/stroke string; url(#id) pushes a pending entry.
private func getFillStrokeStyle(
    _ el: Displayable, _ method: String, _ str: String, _ defsUsePending: inout DefsUsePending
) -> ZRColor? {
    let range = NSRange(str.startIndex..<str.endIndex, in: str)
    if let m = urlRegex.firstMatch(in: str, options: [], range: range), m.numberOfRanges > 1,
       let r = Range(m.range(at: 1), in: str) {
        let url = trimString(String(str[r]))
        defsUsePending.append((el, method, url))
        return nil
    }
    // SVG fill and stroke can be 'none'.
    if str == "none" {
        return nil
    }
    return .string(str)
}

// =====================================================================================================
// number/transform/inline-style parsing utilities (upstream file-private helpers).
// =====================================================================================================

// value can be like: '2e-4', 'l.5.9', 'M-10-10', 'l-2.43e-1,34.9983', '121-23-44-11'
private let numberReg = try! NSRegularExpression(pattern: "-?([0-9]*\\.)?[0-9]+([eE]-?[0-9]+)?")
private func splitNumberSequence(_ rawStr: String) -> [String] {
    let range = NSRange(rawStr.startIndex..<rawStr.endIndex, in: rawStr)
    var out: [String] = []
    numberReg.enumerateMatches(in: rawStr, options: [], range: range) { match, _, _ in
        if let match = match, let r = Range(match.range, in: rawStr) {
            out.append(String(rawStr[r]))
        }
    }
    return out
}

private let transformRegex = try! NSRegularExpression(
    pattern: "(translate|scale|rotate|skewX|skewY|matrix)\\(([\\-\\s0-9\\.eE,]*)\\)"
)
private let DEGREE_TO_ANGLE = Double.pi / 180

private func parseTransformAttribute(_ xmlNode: ZRXMLNode, _ node: Element) {
    guard var transform = xmlNode.getAttribute("transform") else { return }
    transform = transform.replacingOccurrences(of: ",", with: " ")
    var transformOps: [String] = []
    let range = NSRange(transform.startIndex..<transform.endIndex, in: transform)
    transformRegex.enumerateMatches(in: transform, options: [], range: range) { match, _, _ in
        guard let match = match,
              let tR = Range(match.range(at: 1), in: transform),
              let vR = Range(match.range(at: 2), in: transform) else { return }
        transformOps.append(String(transform[tR]))
        transformOps.append(String(transform[vR]))
    }

    var mt: MatrixArray?
    var i = transformOps.count - 1
    while i > 0 {
        let value = transformOps[i]
        let type = transformOps[i - 1]
        let valueArr = splitNumberSequence(value)
        func arg(_ idx: Int) -> Double { idx < valueArr.count ? svgParseFloat(valueArr[idx]) : Double.nan }
        if mt == nil { mt = matrix.create() }
        switch type {
        case "translate":
            let ty = valueArr.count > 1 ? svgParseFloat(valueArr[1]) : 0
            mt = matrix.translate(mt!, VectorArray(arg(0), ty))
        case "scale":
            let sy = valueArr.count > 1 ? svgParseFloat(valueArr[1]) : arg(0)
            mt = matrix.scale(mt!, VectorArray(arg(0), sy))
        case "rotate":
            // zrender uses a different hand in the coord system → negate the angle.
            let px = valueArr.count > 1 ? svgParseFloat(valueArr[1]) : 0
            let py = valueArr.count > 2 ? svgParseFloat(valueArr[2]) : 0
            mt = matrix.rotate(mt!, -arg(0) * DEGREE_TO_ANGLE, VectorArray(px, py))
        case "skewX":
            let sx = tan(arg(0) * DEGREE_TO_ANGLE)
            mt = matrix.mul([1, 0, sx, 1, 0, 0], mt!)
        case "skewY":
            let sy = tan(arg(0) * DEGREE_TO_ANGLE)
            mt = matrix.mul([1, sy, 0, 1, 0, 0], mt!)
        case "matrix":
            mt = [arg(0), arg(1), arg(2), arg(3), arg(4), arg(5)]
        default:
            break
        }
        i -= 2
    }
    if let mt = mt {
        node.setLocalTransform(mt)
    }
}

private let styleRegex = try! NSRegularExpression(pattern: "([^\\s:;]+)\\s*:\\s*([^:;]+)")
private func parseInlineStyle(
    _ xmlNode: ZRXMLNode,
    _ inheritableStyleResult: inout [String: String],
    _ selfStyleResult: inout [String: String]
) {
    guard let style = xmlNode.getAttribute("style") else { return }
    let range = NSRange(style.startIndex..<style.endIndex, in: style)
    styleRegex.enumerateMatches(in: style, options: [], range: range) { match, _, _ in
        guard let match = match,
              let kR = Range(match.range(at: 1), in: style),
              let vR = Range(match.range(at: 2), in: style) else { return }
        let svgStlAttr = String(style[kR])
        let value = String(style[vR])
        if let zrKey = INHERITABLE_STYLE_ATTRIBUTES_MAP[svgStlAttr] {
            inheritableStyleResult[zrKey] = value
        }
        if let zrKey = SELF_STYLE_ATTRIBUTES_MAP[svgStlAttr] {
            selfStyleResult[zrKey] = value
        }
    }
}

private func parseAttributeStyle(
    _ xmlNode: ZRXMLNode,
    _ inheritableStyleResult: inout [String: String],
    _ selfStyleResult: inout [String: String]
) {
    for svgAttrName in INHERITABLE_STYLE_ATTRIBUTES_MAP_KEYS {
        if let attrValue = xmlNode.getAttribute(svgAttrName) {
            inheritableStyleResult[INHERITABLE_STYLE_ATTRIBUTES_MAP[svgAttrName]!] = attrValue
        }
    }
    for svgAttrName in SELF_STYLE_ATTRIBUTES_MAP_KEYS {
        if let attrValue = xmlNode.getAttribute(svgAttrName) {
            selfStyleResult[SELF_STYLE_ATTRIBUTES_MAP[svgAttrName]!] = attrValue
        }
    }
}

// upstream: makeViewBoxTransform (preserveAspectRatio 'xMidYMid').
public func makeViewBoxTransform(_ viewBoxRect: RectLike, _ boundingRect: RectLike) -> SVGViewBoxTransform {
    let scaleX = boundingRect.width / viewBoxRect.width
    let scaleY = boundingRect.height / viewBoxRect.height
    let scale = Swift.min(scaleX, scaleY)
    return SVGViewBoxTransform(
        x: -(viewBoxRect.x + viewBoxRect.width / 2) * scale + (boundingRect.x + boundingRect.width / 2),
        y: -(viewBoxRect.y + viewBoxRect.height / 2) * scale + (boundingRect.y + boundingRect.height / 2),
        scale: scale
    )
}

// upstream: export function parseSVG(xml, opt): SVGParserResult
public func parseSVG(_ xml: Any?, _ opt: SVGParserOption? = nil) -> SVGParserResult {
    let parser = SVGParser()
    return parser.parse(xml, opt)
}

// =====================================================================================================
// small JS-number helpers (parseFloat/parseInt semantics) — Swift's Double(_:) requires a FULL match.
// =====================================================================================================

// JS parseFloat: parse the leading numeric prefix; NaN if none.
func svgParseFloat(_ s: String?) -> Double {
    guard let s = s else { return Double.nan }
    let trimmed = s.drop(while: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" })
    var end = trimmed.startIndex
    var seenDigit = false
    var seenDot = false
    var seenExp = false
    var i = trimmed.startIndex
    while i < trimmed.endIndex {
        let c = trimmed[i]
        if c == "+" || c == "-" {
            // sign only valid at very start or right after an exponent char
            if i == trimmed.startIndex { /* ok */ }
            else {
                let prev = trimmed[trimmed.index(before: i)]
                if prev != "e" && prev != "E" { break }
            }
        }
        else if c.isNumber {
            seenDigit = true
        }
        else if c == "." {
            if seenDot || seenExp { break }
            seenDot = true
        }
        else if c == "e" || c == "E" {
            if seenExp || !seenDigit { break }
            seenExp = true
        }
        else {
            break
        }
        i = trimmed.index(after: i)
        end = i
    }
    if !seenDigit { return Double.nan }
    return Double(trimmed[trimmed.startIndex..<end]) ?? Double.nan
}

// JS parseInt (base 10): leading integer prefix; 0 if none (used with the '||' defaults upstream).
private func parseIntJS(_ s: String) -> Int {
    let v = svgParseFloat(s)
    return v.isNaN ? 0 : Int(v)
}

private func numToStr(_ v: Double) -> String {
    if v == v.rounded() && abs(v) < 1e15 {
        return String(Int(v))
    }
    return String(v)
}

private func trimString(_ s: String) -> String {
    return s.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func fontWeightToString(_ w: FontWeight?) -> String {
    guard let w = w else { return "" }
    switch w {
    case .normal: return "normal"
    case .bold: return "bold"
    case .bolder: return "bolder"
    case .lighter: return "lighter"
    case .number(let n): return numToStr(n)
    }
}

private func parseFontWeight(_ s: String) -> FontWeight {
    switch s {
    case "normal": return .normal
    case "bold": return .bold
    case "bolder": return .bolder
    case "lighter": return .lighter
    default:
        if let n = Double(s) { return .number(n) }
        return .normal
    }
}
