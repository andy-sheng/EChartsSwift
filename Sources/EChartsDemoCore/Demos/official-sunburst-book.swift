// official-sunburst-book — replica of https://echarts.apache.org/examples/zh/editor.html?c=sunburst-book
// title: Book Records / titleCN: 书籍分布
//
// A 4-ring sunburst of one person's read books (虚构/非虚构 → genre → star rating → title), on a dark
// backgroundColor, with per-level absolute radii, a transparent star ring, shadowed sectors and
// tangential / outside labels.
//
// DEVIATIONS from the official source:
//   - The example's `data` is a bare literal that a top-level `for` loop then MUTATES (it stamps each
//     star node's `label`, gives every book `value: 1` + an `itemStyle`/`label`, and copies the root's
//     colour down onto each genre node). webOptionJS keeps the literal AND the loop verbatim, so the
//     reference pane runs the real thing; the Swift `option` carries the loop's OUTPUT, produced by
//     `sunburstBookDecorate()` below — a 1:1 port of that same loop. Raw literal and decoration are
//     kept separate here for exactly that reason.
//   - The upstream loop also accumulates a `bookScore` array that the option never reads (dead code in
//     the official source). It is kept verbatim in webOptionJS and simply not ported to Swift.
//   - Canvas is 820x520, not the usual 640x420: the level radii are ABSOLUTE pixels (r up to 145) and
//     the outermost level labels are `position: 'outside'` full Chinese book titles, which a 640x420
//     box clips. The official example itself declares `shotWidth: 820`.
//   - `export {};` dropped (a bare export is a SyntaxError in a classic script). Nothing else changed.

import EChartsKit   // SortParam — the value the series' `sort` comparator is handed (see sunburstBookSort).

private let sunburstBookColors = ["#FFAE57", "#FF7853", "#EA5151", "#CC3F57", "#9A2555"]
private let sunburstBookBgColor = "#2E2733"

// MARK: - the example's raw `data` literal, one genre per binding (keeps each literal small enough
// for the Swift type-checker to chew through).

private let sunburstBookNovel: [String: Any] = [
    "name": "小说",
    "children": [
        [
            "name": "5☆",
            "children": [
                ["name": "疼"] as [String: Any],
                ["name": "慈悲"] as [String: Any],
                ["name": "楼下的房客"] as [String: Any]
            ]
        ] as [String: Any],
        [
            "name": "4☆",
            "children": [
                ["name": "虚无的十字架"] as [String: Any],
                ["name": "无声告白"] as [String: Any],
                ["name": "童年的终结"] as [String: Any]
            ]
        ] as [String: Any],
        [
            "name": "3☆",
            "children": [
                ["name": "疯癫老人日记"] as [String: Any]
            ]
        ] as [String: Any]
    ]
]

private let sunburstBookOther: [String: Any] = [
    "name": "其他",
    "children": [
        [
            "name": "5☆",
            "children": [
                ["name": "纳博科夫短篇小说全集"] as [String: Any]
            ]
        ] as [String: Any],
        [
            "name": "4☆",
            "children": [
                ["name": "安魂曲"] as [String: Any],
                ["name": "人生拼图版"] as [String: Any]
            ]
        ] as [String: Any],
        [
            "name": "3☆",
            "children": [
                ["name": "比起爱你，我更需要你"] as [String: Any]
            ]
        ] as [String: Any]
    ]
]

private let sunburstBookDesign: [String: Any] = [
    "name": "设计",
    "children": [
        [
            "name": "5☆",
            "children": [
                ["name": "无界面交互"] as [String: Any]
            ]
        ] as [String: Any],
        [
            "name": "4☆",
            "children": [
                ["name": "数字绘图的光照与渲染技术"] as [String: Any],
                ["name": "日本建筑解剖书"] as [String: Any]
            ]
        ] as [String: Any],
        [
            "name": "3☆",
            "children": [
                // The upstream name carries a literal newline escape.
                ["name": "奇幻世界艺术\n&RPG地图绘制讲座"] as [String: Any]
            ]
        ] as [String: Any]
    ]
]

private let sunburstBookSocial: [String: Any] = [
    "name": "社科",
    "children": [
        [
            "name": "5☆",
            "children": [
                ["name": "痛点"] as [String: Any]
            ]
        ] as [String: Any],
        [
            "name": "4☆",
            "children": [
                ["name": "卓有成效的管理者"] as [String: Any],
                ["name": "进化"] as [String: Any],
                ["name": "后物欲时代的来临"] as [String: Any]
            ]
        ] as [String: Any],
        [
            "name": "3☆",
            "children": [
                ["name": "疯癫与文明"] as [String: Any]
            ]
        ] as [String: Any]
    ]
]

private let sunburstBookPsychology: [String: Any] = [
    "name": "心理",
    "children": [
        [
            "name": "5☆",
            "children": [
                ["name": "我们时代的神经症人格"] as [String: Any]
            ]
        ] as [String: Any],
        [
            "name": "4☆",
            "children": [
                ["name": "皮格马利翁效应"] as [String: Any],
                ["name": "受伤的人"] as [String: Any]
            ]
        ] as [String: Any],
        // childless on purpose upstream: a 3☆ ring slice with no books under it.
        ["name": "3☆"] as [String: Any],
        [
            "name": "2☆",
            "children": [
                ["name": "迷恋"] as [String: Any]
            ]
        ] as [String: Any]
    ]
]

private let sunburstBookHome: [String: Any] = [
    "name": "居家",
    "children": [
        [
            "name": "4☆",
            "children": [
                ["name": "把房子住成家"] as [String: Any],
                ["name": "只过必要生活"] as [String: Any],
                ["name": "北欧简约风格"] as [String: Any]
            ]
        ] as [String: Any]
    ]
]

private let sunburstBookPicture: [String: Any] = [
    "name": "绘本",
    "children": [
        [
            "name": "5☆",
            "children": [
                ["name": "设计诗"] as [String: Any]
            ]
        ] as [String: Any],
        [
            "name": "4☆",
            "children": [
                ["name": "假如生活糊弄了你"] as [String: Any],
                ["name": "博物学家的神秘动物图鉴"] as [String: Any]
            ]
        ] as [String: Any],
        [
            "name": "3☆",
            "children": [
                ["name": "方向"] as [String: Any]
            ]
        ] as [String: Any]
    ]
]

private let sunburstBookPhilosophy: [String: Any] = [
    "name": "哲学",
    "children": [
        [
            "name": "4☆",
            "children": [
                ["name": "人生的智慧"] as [String: Any]
            ]
        ] as [String: Any]
    ]
]

private let sunburstBookTech: [String: Any] = [
    "name": "技术",
    "children": [
        [
            "name": "5☆",
            "children": [
                ["name": "代码整洁之道"] as [String: Any]
            ]
        ] as [String: Any],
        [
            "name": "4☆",
            "children": [
                ["name": "Three.js 开发指南"] as [String: Any]
            ]
        ] as [String: Any]
    ]
]

private let sunburstBookRawData: [[String: Any]] = [
    [
        "name": "虚构",
        "itemStyle": ["color": sunburstBookColors[1]] as [String: Any],
        "children": [sunburstBookNovel, sunburstBookOther]
    ] as [String: Any],
    [
        "name": "非虚构",
        "itemStyle": ["color": sunburstBookColors[2]] as [String: Any],
        "children": [
            sunburstBookDesign, sunburstBookSocial, sunburstBookPsychology,
            sunburstBookHome, sunburstBookPicture, sunburstBookPhilosophy, sunburstBookTech
        ]
    ] as [String: Any]
]

// MARK: - the example's decoration pass, ported 1:1

/// Upstream's `itemStyle.starN` lookup: the rating ring's colour, by node name.
private func sunburstBookStarColor(_ name: String) -> String {
    switch name {
    case "5☆": return sunburstBookColors[0]
    case "4☆": return sunburstBookColors[1]
    case "3☆": return sunburstBookColors[2]
    case "2☆": return sunburstBookColors[3]
    default: return sunburstBookColors[0]   // upstream's switch falls through to undefined; unreachable here
    }
}

/// The official source's top-level `for (let j...)` loop: colour each star node's label, stamp every
/// book leaf with `value: 1` + the star's colour, and push the root's colour onto each genre node.
/// (Upstream's `bookScore` accumulator is dead code — the option never reads it — so it is not ported.)
private func sunburstBookDecorate(_ roots: [[String: Any]]) -> [[String: Any]] {
    var out: [[String: Any]] = []
    for root in roots {
        var root = root
        let rootColor = (root["itemStyle"] as? [String: Any])?["color"] as? String ?? ""
        var level1 = root["children"] as? [[String: Any]] ?? []
        for i in level1.indices {
            var genre = level1[i]
            var block = genre["children"] as? [[String: Any]] ?? []
            for s in block.indices {
                var star = block[s]
                let color = sunburstBookStarColor(star["name"] as? String ?? "")
                star["label"] = [
                    "color": color,
                    "downplay": ["opacity": 0.5] as [String: Any]
                ] as [String: Any]
                if var books = star["children"] as? [[String: Any]] {
                    let bookStyle: [String: Any] = ["opacity": 1.0, "color": color]
                    for b in books.indices {
                        books[b]["value"] = 1.0
                        books[b]["itemStyle"] = bookStyle
                        books[b]["label"] = ["color": color] as [String: Any]
                    }
                    star["children"] = books
                }
                block[s] = star
            }
            genre["children"] = block
            genre["itemStyle"] = ["color": rootColor] as [String: Any]
            level1[i] = genre
        }
        root["children"] = level1
        out.append(root)
    }
    return out
}

private let sunburstBookData: [[String: Any]] = sunburstBookDecorate(sunburstBookRawData)

/// The example's `series[0].sort` comparator, ported 1:1:
///
///     sort: function (a, b) {
///       if (a.depth === 1) { return b.getValue() - a.getValue(); }
///       else { return a.dataIndex - b.dataIndex; }
///     }
///
/// The two depth-1 nodes (虚构 / 非虚构) sort DESCENDING by value; every deeper ring keeps its source
/// (dataIndex) order — which is what pins 5☆ → 4☆ → 3☆ → 2☆ around each genre instead of re-ordering
/// the star rings by book count. Dropping it would silently change the chart, so it is carried into the
/// native option too: `sunburstLayout`'s `sunburstSort` takes the callback form of `sort`
/// (`sortOrder as? (SortParam, SortParam) -> Double`), so the type here must match that cast EXACTLY.
/// The option bag is never JSON-serialized for this demo (the web pane runs `webOptionJS`), so a Swift
/// closure can live in it.
private let sunburstBookSort: (SortParam, SortParam) -> Double = { a, b in
    if a.depth == 1 {
        return b.getValue() - a.getValue()
    } else {
        return a.dataIndex - b.dataIndex
    }
}

private let sunburstBookLevels: [[String: Any]] = [
    // levels[0] is the sunburst's centre (the "back to parent" disc), left at its defaults upstream.
    [:] as [String: Any],
    [
        "r0": 0.0, "r": 40.0,
        "label": ["rotate": 0.0] as [String: Any]
    ] as [String: Any],
    [
        "r0": 40.0, "r": 105.0
    ] as [String: Any],
    [
        "r0": 115.0, "r": 140.0,
        "itemStyle": [
            "shadowBlur": 2.0,
            "shadowColor": sunburstBookColors[2],
            "color": "transparent"
        ] as [String: Any],
        "label": [
            "rotate": "tangential",
            "fontSize": 10.0,
            "color": sunburstBookColors[0]
        ] as [String: Any]
    ] as [String: Any],
    [
        "r0": 140.0, "r": 145.0,
        "itemStyle": [
            "shadowBlur": 80.0,
            "shadowColor": sunburstBookColors[0]
        ] as [String: Any],
        "label": [
            "position": "outside",
            "textShadowBlur": 5.0,
            "textShadowColor": "#333"
        ] as [String: Any],
        "downplay": [
            "label": ["opacity": 0.5] as [String: Any]
        ] as [String: Any]
    ] as [String: Any]
]

extension EChartsDemoRegistry {
    static let official_sunburst_book = EChartsDemo(
        name: "official-sunburst-book", category: "sunburst",
        summary: "书籍分布 — Book Records",
        width: 820, height: 520,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
const colors = ['#FFAE57', '#FF7853', '#EA5151', '#CC3F57', '#9A2555'];
const bgColor = '#2E2733';

const itemStyle = {
  star5: {
    color: colors[0]
  },
  star4: {
    color: colors[1]
  },
  star3: {
    color: colors[2]
  },
  star2: {
    color: colors[3]
  }
};

const data = [
  {
    name: '虚构',
    itemStyle: {
      color: colors[1]
    },
    children: [
      {
        name: '小说',
        children: [
          {
            name: '5☆',
            children: [
              {
                name: '疼'
              },
              {
                name: '慈悲'
              },
              {
                name: '楼下的房客'
              }
            ]
          },
          {
            name: '4☆',
            children: [
              {
                name: '虚无的十字架'
              },
              {
                name: '无声告白'
              },
              {
                name: '童年的终结'
              }
            ]
          },
          {
            name: '3☆',
            children: [
              {
                name: '疯癫老人日记'
              }
            ]
          }
        ]
      },
      {
        name: '其他',
        children: [
          {
            name: '5☆',
            children: [
              {
                name: '纳博科夫短篇小说全集'
              }
            ]
          },
          {
            name: '4☆',
            children: [
              {
                name: '安魂曲'
              },
              {
                name: '人生拼图版'
              }
            ]
          },
          {
            name: '3☆',
            children: [
              {
                name: '比起爱你，我更需要你'
              }
            ]
          }
        ]
      }
    ]
  },
  {
    name: '非虚构',
    itemStyle: {
      color: colors[2]
    },
    children: [
      {
        name: '设计',
        children: [
          {
            name: '5☆',
            children: [
              {
                name: '无界面交互'
              }
            ]
          },
          {
            name: '4☆',
            children: [
              {
                name: '数字绘图的光照与渲染技术'
              },
              {
                name: '日本建筑解剖书'
              }
            ]
          },
          {
            name: '3☆',
            children: [
              {
                name: '奇幻世界艺术\n&RPG地图绘制讲座'
              }
            ]
          }
        ]
      },
      {
        name: '社科',
        children: [
          {
            name: '5☆',
            children: [
              {
                name: '痛点'
              }
            ]
          },
          {
            name: '4☆',
            children: [
              {
                name: '卓有成效的管理者'
              },
              {
                name: '进化'
              },
              {
                name: '后物欲时代的来临'
              }
            ]
          },
          {
            name: '3☆',
            children: [
              {
                name: '疯癫与文明'
              }
            ]
          }
        ]
      },
      {
        name: '心理',
        children: [
          {
            name: '5☆',
            children: [
              {
                name: '我们时代的神经症人格'
              }
            ]
          },
          {
            name: '4☆',
            children: [
              {
                name: '皮格马利翁效应'
              },
              {
                name: '受伤的人'
              }
            ]
          },
          {
            name: '3☆'
          },
          {
            name: '2☆',
            children: [
              {
                name: '迷恋'
              }
            ]
          }
        ]
      },
      {
        name: '居家',
        children: [
          {
            name: '4☆',
            children: [
              {
                name: '把房子住成家'
              },
              {
                name: '只过必要生活'
              },
              {
                name: '北欧简约风格'
              }
            ]
          }
        ]
      },
      {
        name: '绘本',
        children: [
          {
            name: '5☆',
            children: [
              {
                name: '设计诗'
              }
            ]
          },
          {
            name: '4☆',
            children: [
              {
                name: '假如生活糊弄了你'
              },
              {
                name: '博物学家的神秘动物图鉴'
              }
            ]
          },
          {
            name: '3☆',
            children: [
              {
                name: '方向'
              }
            ]
          }
        ]
      },
      {
        name: '哲学',
        children: [
          {
            name: '4☆',
            children: [
              {
                name: '人生的智慧'
              }
            ]
          }
        ]
      },
      {
        name: '技术',
        children: [
          {
            name: '5☆',
            children: [
              {
                name: '代码整洁之道'
              }
            ]
          },
          {
            name: '4☆',
            children: [
              {
                name: 'Three.js 开发指南'
              }
            ]
          }
        ]
      }
    ]
  }
];

for (let j = 0; j < data.length; ++j) {
  let level1 = data[j].children;
  for (let i = 0; i < level1.length; ++i) {
    let block = level1[i].children;
    let bookScore = [];
    let bookScoreId;
    for (let star = 0; star < block.length; ++star) {
      let style = (function (name) {
        switch (name) {
          case '5☆':
            bookScoreId = 0;
            return itemStyle.star5;
          case '4☆':
            bookScoreId = 1;
            return itemStyle.star4;
          case '3☆':
            bookScoreId = 2;
            return itemStyle.star3;
          case '2☆':
            bookScoreId = 3;
            return itemStyle.star2;
        }
      })(block[star].name);

      block[star].label = {
        color: style.color,
        downplay: {
          opacity: 0.5
        }
      };

      if (block[star].children) {
        style = {
          opacity: 1,
          color: style.color
        };
        block[star].children.forEach(function (book) {
          book.value = 1;
          book.itemStyle = style;

          book.label = {
            color: style.color
          };

          let value = 1;
          if (bookScoreId === 0 || bookScoreId === 3) {
            value = 5;
          }

          if (bookScore[bookScoreId]) {
            bookScore[bookScoreId].value += value;
          } else {
            bookScore[bookScoreId] = {
              color: colors[bookScoreId],
              value: value
            };
          }
        });
      }
    }

    level1[i].itemStyle = {
      color: data[j].itemStyle.color
    };
  }
}

option = {
  backgroundColor: bgColor,
  color: colors,
  series: [
    {
      type: 'sunburst',
      center: ['50%', '48%'],
      data: data,
      sort: function (a, b) {
        if (a.depth === 1) {
          return b.getValue() - a.getValue();
        } else {
          return a.dataIndex - b.dataIndex;
        }
      },
      label: {
        rotate: 'radial',
        color: bgColor
      },
      itemStyle: {
        borderColor: bgColor,
        borderWidth: 2
      },
      levels: [
        {},
        {
          r0: 0,
          r: 40,
          label: {
            rotate: 0
          }
        },
        {
          r0: 40,
          r: 105
        },
        {
          r0: 115,
          r: 140,
          itemStyle: {
            shadowBlur: 2,
            shadowColor: colors[2],
            color: 'transparent'
          },
          label: {
            rotate: 'tangential',
            fontSize: 10,
            color: colors[0]
          }
        },
        {
          r0: 140,
          r: 145,
          itemStyle: {
            shadowBlur: 80,
            shadowColor: colors[0]
          },
          label: {
            position: 'outside',
            textShadowBlur: 5,
            textShadowColor: '#333'
          },
          downplay: {
            label: {
              opacity: 0.5
            }
          }
        }
      ]
    }
  ]
};
"""#,
        option: [
            "backgroundColor": sunburstBookBgColor,
            "color": sunburstBookColors,
            "series": [
                [
                    "type": "sunburst",
                    "center": ["50%", "48%"],
                    "data": sunburstBookData,
                    // The example's comparator, ported (see sunburstBookSort). The key must stay
                    // PRESENT: an absent `sort` lets the series default `sort: 'desc'` merge in, which
                    // would re-order every ring by value — including the star rings.
                    "sort": sunburstBookSort,
                    "label": [
                        "rotate": "radial",
                        "color": sunburstBookBgColor
                    ] as [String: Any],
                    "itemStyle": [
                        "borderColor": sunburstBookBgColor,
                        "borderWidth": 2.0
                    ] as [String: Any],
                    "levels": sunburstBookLevels
                ] as [String: Any]
            ]
        ])
}
