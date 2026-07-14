// official-sunburst-drink — replica of https://echarts.apache.org/examples/zh/editor.html?c=sunburst-drink
// title: Drink Flavors / titleCN: 饮品风味分类
// The World Coffee Research sensory lexicon as a 3-ring sunburst: every node carries its own
// itemStyle.color, `sort: undefined` keeps the source order, `levels[]` pins each ring's r0/r and
// label placement (tangential on ring 1, right-aligned on ring 2, outside on ring 3), and
// emphasis.focus 'ancestor' lights up a leaf's whole lineage on hover.
// DEVIATIONS:
//   - canvas is 900x560 (the official shot is 1000 wide); the sunburst is radius-relative so it
//     just renders smaller, but the ring-3 `position: 'outside'` labels crowd more than on the site.
//   - the Swift `option` spells the tree with two local helpers (`sbDrinkNode` / `sbDrinkLeaf`)
//     instead of one giant literal — same values, Swift's type-checker cannot chew the literal.
//   - `sort: undefined` is `NSNull()` natively: the key must stay PRESENT (an absent key would let
//     the series default `sort: 'desc'` merge in and re-order the rings). Same semantics as JS.
//   - nothing else: no data fetch, no closures, no timers, so no `drive` and the JS is verbatim
//     (minus the example's `/* title: ... */` metadata block and the trailing `export {};`).

import Foundation   // NSNull — the port's stand-in for the series' `sort: undefined`.

extension EChartsDemoRegistry {
    static let official_sunburst_drink = EChartsDemo(
        name: "official-sunburst-drink", category: "sunburst",
        summary: "饮品风味分类 — Drink Flavors",
        width: 900, height: 560,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
var data = [
  {
    name: 'Flora',
    itemStyle: {
      color: '#da0d68'
    },
    children: [
      {
        name: 'Black Tea',
        value: 1,
        itemStyle: {
          color: '#975e6d'
        }
      },
      {
        name: 'Floral',
        itemStyle: {
          color: '#e0719c'
        },
        children: [
          {
            name: 'Chamomile',
            value: 1,
            itemStyle: {
              color: '#f99e1c'
            }
          },
          {
            name: 'Rose',
            value: 1,
            itemStyle: {
              color: '#ef5a78'
            }
          },
          {
            name: 'Jasmine',
            value: 1,
            itemStyle: {
              color: '#f7f1bd'
            }
          }
        ]
      }
    ]
  },
  {
    name: 'Fruity',
    itemStyle: {
      color: '#da1d23'
    },
    children: [
      {
        name: 'Berry',
        itemStyle: {
          color: '#dd4c51'
        },
        children: [
          {
            name: 'Blackberry',
            value: 1,
            itemStyle: {
              color: '#3e0317'
            }
          },
          {
            name: 'Raspberry',
            value: 1,
            itemStyle: {
              color: '#e62969'
            }
          },
          {
            name: 'Blueberry',
            value: 1,
            itemStyle: {
              color: '#6569b0'
            }
          },
          {
            name: 'Strawberry',
            value: 1,
            itemStyle: {
              color: '#ef2d36'
            }
          }
        ]
      },
      {
        name: 'Dried Fruit',
        itemStyle: {
          color: '#c94a44'
        },
        children: [
          {
            name: 'Raisin',
            value: 1,
            itemStyle: {
              color: '#b53b54'
            }
          },
          {
            name: 'Prune',
            value: 1,
            itemStyle: {
              color: '#a5446f'
            }
          }
        ]
      },
      {
        name: 'Other Fruit',
        itemStyle: {
          color: '#dd4c51'
        },
        children: [
          {
            name: 'Coconut',
            value: 1,
            itemStyle: {
              color: '#f2684b'
            }
          },
          {
            name: 'Cherry',
            value: 1,
            itemStyle: {
              color: '#e73451'
            }
          },
          {
            name: 'Pomegranate',
            value: 1,
            itemStyle: {
              color: '#e65656'
            }
          },
          {
            name: 'Pineapple',
            value: 1,
            itemStyle: {
              color: '#f89a1c'
            }
          },
          {
            name: 'Grape',
            value: 1,
            itemStyle: {
              color: '#aeb92c'
            }
          },
          {
            name: 'Apple',
            value: 1,
            itemStyle: {
              color: '#4eb849'
            }
          },
          {
            name: 'Peach',
            value: 1,
            itemStyle: {
              color: '#f68a5c'
            }
          },
          {
            name: 'Pear',
            value: 1,
            itemStyle: {
              color: '#baa635'
            }
          }
        ]
      },
      {
        name: 'Citrus Fruit',
        itemStyle: {
          color: '#f7a128'
        },
        children: [
          {
            name: 'Grapefruit',
            value: 1,
            itemStyle: {
              color: '#f26355'
            }
          },
          {
            name: 'Orange',
            value: 1,
            itemStyle: {
              color: '#e2631e'
            }
          },
          {
            name: 'Lemon',
            value: 1,
            itemStyle: {
              color: '#fde404'
            }
          },
          {
            name: 'Lime',
            value: 1,
            itemStyle: {
              color: '#7eb138'
            }
          }
        ]
      }
    ]
  },
  {
    name: 'Sour/\nFermented',
    itemStyle: {
      color: '#ebb40f'
    },
    children: [
      {
        name: 'Sour',
        itemStyle: {
          color: '#e1c315'
        },
        children: [
          {
            name: 'Sour Aromatics',
            value: 1,
            itemStyle: {
              color: '#9ea718'
            }
          },
          {
            name: 'Acetic Acid',
            value: 1,
            itemStyle: {
              color: '#94a76f'
            }
          },
          {
            name: 'Butyric Acid',
            value: 1,
            itemStyle: {
              color: '#d0b24f'
            }
          },
          {
            name: 'Isovaleric Acid',
            value: 1,
            itemStyle: {
              color: '#8eb646'
            }
          },
          {
            name: 'Citric Acid',
            value: 1,
            itemStyle: {
              color: '#faef07'
            }
          },
          {
            name: 'Malic Acid',
            value: 1,
            itemStyle: {
              color: '#c1ba07'
            }
          }
        ]
      },
      {
        name: 'Alcohol/\nFremented',
        itemStyle: {
          color: '#b09733'
        },
        children: [
          {
            name: 'Winey',
            value: 1,
            itemStyle: {
              color: '#8f1c53'
            }
          },
          {
            name: 'Whiskey',
            value: 1,
            itemStyle: {
              color: '#b34039'
            }
          },
          {
            name: 'Fremented',
            value: 1,
            itemStyle: {
              color: '#ba9232'
            }
          },
          {
            name: 'Overripe',
            value: 1,
            itemStyle: {
              color: '#8b6439'
            }
          }
        ]
      }
    ]
  },
  {
    name: 'Green/\nVegetative',
    itemStyle: {
      color: '#187a2f'
    },
    children: [
      {
        name: 'Olive Oil',
        value: 1,
        itemStyle: {
          color: '#a2b029'
        }
      },
      {
        name: 'Raw',
        value: 1,
        itemStyle: {
          color: '#718933'
        }
      },
      {
        name: 'Green/\nVegetative',
        itemStyle: {
          color: '#3aa255'
        },
        children: [
          {
            name: 'Under-ripe',
            value: 1,
            itemStyle: {
              color: '#a2bb2b'
            }
          },
          {
            name: 'Peapod',
            value: 1,
            itemStyle: {
              color: '#62aa3c'
            }
          },
          {
            name: 'Fresh',
            value: 1,
            itemStyle: {
              color: '#03a653'
            }
          },
          {
            name: 'Dark Green',
            value: 1,
            itemStyle: {
              color: '#038549'
            }
          },
          {
            name: 'Vegetative',
            value: 1,
            itemStyle: {
              color: '#28b44b'
            }
          },
          {
            name: 'Hay-like',
            value: 1,
            itemStyle: {
              color: '#a3a830'
            }
          },
          {
            name: 'Herb-like',
            value: 1,
            itemStyle: {
              color: '#7ac141'
            }
          }
        ]
      },
      {
        name: 'Beany',
        value: 1,
        itemStyle: {
          color: '#5e9a80'
        }
      }
    ]
  },
  {
    name: 'Other',
    itemStyle: {
      color: '#0aa3b5'
    },
    children: [
      {
        name: 'Papery/Musty',
        itemStyle: {
          color: '#9db2b7'
        },
        children: [
          {
            name: 'Stale',
            value: 1,
            itemStyle: {
              color: '#8b8c90'
            }
          },
          {
            name: 'Cardboard',
            value: 1,
            itemStyle: {
              color: '#beb276'
            }
          },
          {
            name: 'Papery',
            value: 1,
            itemStyle: {
              color: '#fefef4'
            }
          },
          {
            name: 'Woody',
            value: 1,
            itemStyle: {
              color: '#744e03'
            }
          },
          {
            name: 'Moldy/Damp',
            value: 1,
            itemStyle: {
              color: '#a3a36f'
            }
          },
          {
            name: 'Musty/Dusty',
            value: 1,
            itemStyle: {
              color: '#c9b583'
            }
          },
          {
            name: 'Musty/Earthy',
            value: 1,
            itemStyle: {
              color: '#978847'
            }
          },
          {
            name: 'Animalic',
            value: 1,
            itemStyle: {
              color: '#9d977f'
            }
          },
          {
            name: 'Meaty Brothy',
            value: 1,
            itemStyle: {
              color: '#cc7b6a'
            }
          },
          {
            name: 'Phenolic',
            value: 1,
            itemStyle: {
              color: '#db646a'
            }
          }
        ]
      },
      {
        name: 'Chemical',
        itemStyle: {
          color: '#76c0cb'
        },
        children: [
          {
            name: 'Bitter',
            value: 1,
            itemStyle: {
              color: '#80a89d'
            }
          },
          {
            name: 'Salty',
            value: 1,
            itemStyle: {
              color: '#def2fd'
            }
          },
          {
            name: 'Medicinal',
            value: 1,
            itemStyle: {
              color: '#7a9bae'
            }
          },
          {
            name: 'Petroleum',
            value: 1,
            itemStyle: {
              color: '#039fb8'
            }
          },
          {
            name: 'Skunky',
            value: 1,
            itemStyle: {
              color: '#5e777b'
            }
          },
          {
            name: 'Rubber',
            value: 1,
            itemStyle: {
              color: '#120c0c'
            }
          }
        ]
      }
    ]
  },
  {
    name: 'Roasted',
    itemStyle: {
      color: '#c94930'
    },
    children: [
      {
        name: 'Pipe Tobacco',
        value: 1,
        itemStyle: {
          color: '#caa465'
        }
      },
      {
        name: 'Tobacco',
        value: 1,
        itemStyle: {
          color: '#dfbd7e'
        }
      },
      {
        name: 'Burnt',
        itemStyle: {
          color: '#be8663'
        },
        children: [
          {
            name: 'Acrid',
            value: 1,
            itemStyle: {
              color: '#b9a449'
            }
          },
          {
            name: 'Ashy',
            value: 1,
            itemStyle: {
              color: '#899893'
            }
          },
          {
            name: 'Smoky',
            value: 1,
            itemStyle: {
              color: '#a1743b'
            }
          },
          {
            name: 'Brown, Roast',
            value: 1,
            itemStyle: {
              color: '#894810'
            }
          }
        ]
      },
      {
        name: 'Cereal',
        itemStyle: {
          color: '#ddaf61'
        },
        children: [
          {
            name: 'Grain',
            value: 1,
            itemStyle: {
              color: '#b7906f'
            }
          },
          {
            name: 'Malt',
            value: 1,
            itemStyle: {
              color: '#eb9d5f'
            }
          }
        ]
      }
    ]
  },
  {
    name: 'Spices',
    itemStyle: {
      color: '#ad213e'
    },
    children: [
      {
        name: 'Pungent',
        value: 1,
        itemStyle: {
          color: '#794752'
        }
      },
      {
        name: 'Pepper',
        value: 1,
        itemStyle: {
          color: '#cc3d41'
        }
      },
      {
        name: 'Brown Spice',
        itemStyle: {
          color: '#b14d57'
        },
        children: [
          {
            name: 'Anise',
            value: 1,
            itemStyle: {
              color: '#c78936'
            }
          },
          {
            name: 'Nutmeg',
            value: 1,
            itemStyle: {
              color: '#8c292c'
            }
          },
          {
            name: 'Cinnamon',
            value: 1,
            itemStyle: {
              color: '#e5762e'
            }
          },
          {
            name: 'Clove',
            value: 1,
            itemStyle: {
              color: '#a16c5a'
            }
          }
        ]
      }
    ]
  },
  {
    name: 'Nutty/\nCocoa',
    itemStyle: {
      color: '#a87b64'
    },
    children: [
      {
        name: 'Nutty',
        itemStyle: {
          color: '#c78869'
        },
        children: [
          {
            name: 'Peanuts',
            value: 1,
            itemStyle: {
              color: '#d4ad12'
            }
          },
          {
            name: 'Hazelnut',
            value: 1,
            itemStyle: {
              color: '#9d5433'
            }
          },
          {
            name: 'Almond',
            value: 1,
            itemStyle: {
              color: '#c89f83'
            }
          }
        ]
      },
      {
        name: 'Cocoa',
        itemStyle: {
          color: '#bb764c'
        },
        children: [
          {
            name: 'Chocolate',
            value: 1,
            itemStyle: {
              color: '#692a19'
            }
          },
          {
            name: 'Dark Chocolate',
            value: 1,
            itemStyle: {
              color: '#470604'
            }
          }
        ]
      }
    ]
  },
  {
    name: 'Sweet',
    itemStyle: {
      color: '#e65832'
    },
    children: [
      {
        name: 'Brown Sugar',
        itemStyle: {
          color: '#d45a59'
        },
        children: [
          {
            name: 'Molasses',
            value: 1,
            itemStyle: {
              color: '#310d0f'
            }
          },
          {
            name: 'Maple Syrup',
            value: 1,
            itemStyle: {
              color: '#ae341f'
            }
          },
          {
            name: 'Caramelized',
            value: 1,
            itemStyle: {
              color: '#d78823'
            }
          },
          {
            name: 'Honey',
            value: 1,
            itemStyle: {
              color: '#da5c1f'
            }
          }
        ]
      },
      {
        name: 'Vanilla',
        value: 1,
        itemStyle: {
          color: '#f89a80'
        }
      },
      {
        name: 'Vanillin',
        value: 1,
        itemStyle: {
          color: '#f37674'
        }
      },
      {
        name: 'Overall Sweet',
        value: 1,
        itemStyle: {
          color: '#e75b68'
        }
      },
      {
        name: 'Sweet Aromatics',
        value: 1,
        itemStyle: {
          color: '#d0545f'
        }
      }
    ]
  }
];

option = {
  title: {
    text: 'WORLD COFFEE RESEARCH SENSORY LEXICON',
    subtext: 'Source: https://worldcoffeeresearch.org/work/sensory-lexicon/',
    textStyle: {
      fontSize: 14,
      align: 'center'
    },
    subtextStyle: {
      align: 'center'
    },
    sublink: 'https://worldcoffeeresearch.org/work/sensory-lexicon/'
  },
  series: {
    type: 'sunburst',

    data: data,
    radius: [0, '95%'],
    sort: undefined,

    emphasis: {
      focus: 'ancestor'
    },

    levels: [
      {},
      {
        r0: '15%',
        r: '35%',
        itemStyle: {
          borderWidth: 2
        },
        label: {
          rotate: 'tangential'
        }
      },
      {
        r0: '35%',
        r: '70%',
        label: {
          align: 'right'
        }
      },
      {
        r0: '70%',
        r: '72%',
        label: {
          position: 'outside',
          padding: 3,
          silent: false
        },
        itemStyle: {
          borderWidth: 3
        }
      }
    ]
  }
};
"""#,
        option: [
            "title": [
                "text": "WORLD COFFEE RESEARCH SENSORY LEXICON",
                "subtext": "Source: https://worldcoffeeresearch.org/work/sensory-lexicon/",
                "textStyle": [
                    "fontSize": 14.0,
                    "align": "center"
                ] as [String: Any],
                "subtextStyle": [
                    "align": "center"
                ] as [String: Any],
                "sublink": "https://worldcoffeeresearch.org/work/sensory-lexicon/"
            ] as [String: Any],
            // Upstream passes `series` as a single object (not an array); echarts normalizes it.
            "series": [
                "type": "sunburst",
                "data": sunburstDrinkData,
                "radius": [0.0, "95%"] as [Any],
                // JS `sort: undefined` — the key must EXIST (a missing key would let the series
                // default `sort: 'desc'` merge in); NSNull is the port's explicit-null.
                "sort": NSNull(),
                "emphasis": [
                    "focus": "ancestor"
                ] as [String: Any],
                "levels": sunburstDrinkLevels
            ] as [String: Any]
        ])
}

// Ring geometry + label placement, one entry per depth (index 0 = the invisible root level).
private let sunburstDrinkLevels: [[String: Any]] = [
    [:],
    [
        "r0": "15%",
        "r": "35%",
        "itemStyle": ["borderWidth": 2.0] as [String: Any],
        "label": ["rotate": "tangential"] as [String: Any]
    ],
    [
        "r0": "35%",
        "r": "70%",
        "label": ["align": "right"] as [String: Any]
    ],
    [
        "r0": "70%",
        "r": "72%",
        "label": [
            "position": "outside",
            "padding": 3.0,
            "silent": false
        ] as [String: Any],
        "itemStyle": ["borderWidth": 3.0] as [String: Any]
    ]
]

// The example's tree, node for node. Spelled through two helpers rather than one nested literal:
// Swift's type-checker times out on a heterogeneous literal this deep.
private func sunburstDrinkLeaf(_ name: String, _ color: String) -> [String: Any] {
    ["name": name, "value": 1.0, "itemStyle": ["color": color] as [String: Any]]
}

private func sunburstDrinkNode(_ name: String, _ color: String, _ children: [[String: Any]]) -> [String: Any] {
    ["name": name, "itemStyle": ["color": color] as [String: Any], "children": children]
}

private let sunburstDrinkData: [[String: Any]] = [
    sunburstDrinkNode("Flora", "#da0d68", [
        sunburstDrinkLeaf("Black Tea", "#975e6d"),
        sunburstDrinkNode("Floral", "#e0719c", [
            sunburstDrinkLeaf("Chamomile", "#f99e1c"),
            sunburstDrinkLeaf("Rose", "#ef5a78"),
            sunburstDrinkLeaf("Jasmine", "#f7f1bd")
        ])
    ]),
    sunburstDrinkNode("Fruity", "#da1d23", [
        sunburstDrinkNode("Berry", "#dd4c51", [
            sunburstDrinkLeaf("Blackberry", "#3e0317"),
            sunburstDrinkLeaf("Raspberry", "#e62969"),
            sunburstDrinkLeaf("Blueberry", "#6569b0"),
            sunburstDrinkLeaf("Strawberry", "#ef2d36")
        ]),
        sunburstDrinkNode("Dried Fruit", "#c94a44", [
            sunburstDrinkLeaf("Raisin", "#b53b54"),
            sunburstDrinkLeaf("Prune", "#a5446f")
        ]),
        sunburstDrinkNode("Other Fruit", "#dd4c51", [
            sunburstDrinkLeaf("Coconut", "#f2684b"),
            sunburstDrinkLeaf("Cherry", "#e73451"),
            sunburstDrinkLeaf("Pomegranate", "#e65656"),
            sunburstDrinkLeaf("Pineapple", "#f89a1c"),
            sunburstDrinkLeaf("Grape", "#aeb92c"),
            sunburstDrinkLeaf("Apple", "#4eb849"),
            sunburstDrinkLeaf("Peach", "#f68a5c"),
            sunburstDrinkLeaf("Pear", "#baa635")
        ]),
        sunburstDrinkNode("Citrus Fruit", "#f7a128", [
            sunburstDrinkLeaf("Grapefruit", "#f26355"),
            sunburstDrinkLeaf("Orange", "#e2631e"),
            sunburstDrinkLeaf("Lemon", "#fde404"),
            sunburstDrinkLeaf("Lime", "#7eb138")
        ])
    ]),
    sunburstDrinkNode("Sour/\nFermented", "#ebb40f", [
        sunburstDrinkNode("Sour", "#e1c315", [
            sunburstDrinkLeaf("Sour Aromatics", "#9ea718"),
            sunburstDrinkLeaf("Acetic Acid", "#94a76f"),
            sunburstDrinkLeaf("Butyric Acid", "#d0b24f"),
            sunburstDrinkLeaf("Isovaleric Acid", "#8eb646"),
            sunburstDrinkLeaf("Citric Acid", "#faef07"),
            sunburstDrinkLeaf("Malic Acid", "#c1ba07")
        ]),
        sunburstDrinkNode("Alcohol/\nFremented", "#b09733", [
            sunburstDrinkLeaf("Winey", "#8f1c53"),
            sunburstDrinkLeaf("Whiskey", "#b34039"),
            sunburstDrinkLeaf("Fremented", "#ba9232"),
            sunburstDrinkLeaf("Overripe", "#8b6439")
        ])
    ]),
    sunburstDrinkNode("Green/\nVegetative", "#187a2f", [
        sunburstDrinkLeaf("Olive Oil", "#a2b029"),
        sunburstDrinkLeaf("Raw", "#718933"),
        sunburstDrinkNode("Green/\nVegetative", "#3aa255", [
            sunburstDrinkLeaf("Under-ripe", "#a2bb2b"),
            sunburstDrinkLeaf("Peapod", "#62aa3c"),
            sunburstDrinkLeaf("Fresh", "#03a653"),
            sunburstDrinkLeaf("Dark Green", "#038549"),
            sunburstDrinkLeaf("Vegetative", "#28b44b"),
            sunburstDrinkLeaf("Hay-like", "#a3a830"),
            sunburstDrinkLeaf("Herb-like", "#7ac141")
        ]),
        sunburstDrinkLeaf("Beany", "#5e9a80")
    ]),
    sunburstDrinkNode("Other", "#0aa3b5", [
        sunburstDrinkNode("Papery/Musty", "#9db2b7", [
            sunburstDrinkLeaf("Stale", "#8b8c90"),
            sunburstDrinkLeaf("Cardboard", "#beb276"),
            sunburstDrinkLeaf("Papery", "#fefef4"),
            sunburstDrinkLeaf("Woody", "#744e03"),
            sunburstDrinkLeaf("Moldy/Damp", "#a3a36f"),
            sunburstDrinkLeaf("Musty/Dusty", "#c9b583"),
            sunburstDrinkLeaf("Musty/Earthy", "#978847"),
            sunburstDrinkLeaf("Animalic", "#9d977f"),
            sunburstDrinkLeaf("Meaty Brothy", "#cc7b6a"),
            sunburstDrinkLeaf("Phenolic", "#db646a")
        ]),
        sunburstDrinkNode("Chemical", "#76c0cb", [
            sunburstDrinkLeaf("Bitter", "#80a89d"),
            sunburstDrinkLeaf("Salty", "#def2fd"),
            sunburstDrinkLeaf("Medicinal", "#7a9bae"),
            sunburstDrinkLeaf("Petroleum", "#039fb8"),
            sunburstDrinkLeaf("Skunky", "#5e777b"),
            sunburstDrinkLeaf("Rubber", "#120c0c")
        ])
    ]),
    sunburstDrinkNode("Roasted", "#c94930", [
        sunburstDrinkLeaf("Pipe Tobacco", "#caa465"),
        sunburstDrinkLeaf("Tobacco", "#dfbd7e"),
        sunburstDrinkNode("Burnt", "#be8663", [
            sunburstDrinkLeaf("Acrid", "#b9a449"),
            sunburstDrinkLeaf("Ashy", "#899893"),
            sunburstDrinkLeaf("Smoky", "#a1743b"),
            sunburstDrinkLeaf("Brown, Roast", "#894810")
        ]),
        sunburstDrinkNode("Cereal", "#ddaf61", [
            sunburstDrinkLeaf("Grain", "#b7906f"),
            sunburstDrinkLeaf("Malt", "#eb9d5f")
        ])
    ]),
    sunburstDrinkNode("Spices", "#ad213e", [
        sunburstDrinkLeaf("Pungent", "#794752"),
        sunburstDrinkLeaf("Pepper", "#cc3d41"),
        sunburstDrinkNode("Brown Spice", "#b14d57", [
            sunburstDrinkLeaf("Anise", "#c78936"),
            sunburstDrinkLeaf("Nutmeg", "#8c292c"),
            sunburstDrinkLeaf("Cinnamon", "#e5762e"),
            sunburstDrinkLeaf("Clove", "#a16c5a")
        ])
    ]),
    sunburstDrinkNode("Nutty/\nCocoa", "#a87b64", [
        sunburstDrinkNode("Nutty", "#c78869", [
            sunburstDrinkLeaf("Peanuts", "#d4ad12"),
            sunburstDrinkLeaf("Hazelnut", "#9d5433"),
            sunburstDrinkLeaf("Almond", "#c89f83")
        ]),
        sunburstDrinkNode("Cocoa", "#bb764c", [
            sunburstDrinkLeaf("Chocolate", "#692a19"),
            sunburstDrinkLeaf("Dark Chocolate", "#470604")
        ])
    ]),
    sunburstDrinkNode("Sweet", "#e65832", [
        sunburstDrinkNode("Brown Sugar", "#d45a59", [
            sunburstDrinkLeaf("Molasses", "#310d0f"),
            sunburstDrinkLeaf("Maple Syrup", "#ae341f"),
            sunburstDrinkLeaf("Caramelized", "#d78823"),
            sunburstDrinkLeaf("Honey", "#da5c1f")
        ]),
        sunburstDrinkLeaf("Vanilla", "#f89a80"),
        sunburstDrinkLeaf("Vanillin", "#f37674"),
        sunburstDrinkLeaf("Overall Sweet", "#e75b68"),
        sunburstDrinkLeaf("Sweet Aromatics", "#d0545f")
    ])
]
