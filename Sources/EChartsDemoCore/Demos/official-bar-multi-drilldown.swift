// official-bar-multi-drilldown — replica of https://echarts.apache.org/examples/zh/editor.html?c=bar-multi-drilldown
// title: Bar Chart Multi-level Drilldown Animation / titleCN: 柱状图多层下钻动画
// A 3-bar root chart (Animals / Fruits / Cars). Clicking a bar swaps in that group's child option and
// `universalTransition` morphs the bar into its children (things → animals → dogs, 3 levels deep);
// a `graphic` "Back" text pops the option stack. Each level's series carries `dimensions` +
// `encode.itemGroupId` / `encode.itemChildGroupId`, which is what links a parent bar to its children.
//
// DEVIATIONS from the official source:
//  - The gallery renders ONE static frame, so only the INITIAL option (`allOptions['things']`, the
//    root level) is what either pane shows. The drilldown is click-driven and never fires: no bar is
//    ever clicked, so the universalTransition morph and the "Back" text are inert in both panes.
//  - webOptionJS: TypeScript annotations stripped (`interface DataItem`, `: string[]`, `as string`,
//    the `allOptions` index signature) — the reference pane is a classic script, not TS. Trailing
//    `export {};` dropped (a bare export is a SyntaxError in a classic script).
//  - webOptionJS: the top-level `myChart.on('click', 'series', ...)` registration is DROPPED. The
//    option script runs BEFORE WebPage.swift calls `echarts.init`, so `myChart` is not yet defined
//    and the reference would throw and blank the page. Everything else — all 12 levels of data, the
//    `allLevelData.forEach` option factory, `optionStack`, `goForward`, `goBack` — is verbatim;
//    goForward/goBack are simply never invoked.
//  - Native option: only the root level's option is expressed; the 11 child-level options and the
//    option-stack machinery are web-only (they exist purely to serve clicks). `graphic[0].onclick`
//    is omitted — a JS closure Swift cannot carry.
extension EChartsDemoRegistry {
    static let official_bar_multi_drilldown = EChartsDemo(
        name: "official-bar-multi-drilldown", category: "bar",
        summary: "柱状图多层下钻动画 — Bar Chart Multi-level Drilldown Animation",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
// This example requires ECharts v5.5.0 or later
// level 1 (root)
const data_things = [
  ['Animals', 3, 'things', 'animals'],
  ['Fruits', 3, 'things', 'fruits'],
  ['Cars', 2, 'things', 'cars']
];
// level 2
const data_animals = [
  ['Dogs', 3, 'animals', 'dogs'],
  ['Cats', 4, 'animals', 'cats'],
  ['Birds', 3, 'animals', 'birds']
];
const data_fruits = [
  ['Pomes', 3, 'fruits', 'pomes'],
  ['Berries', 4, 'fruits', 'berries'],
  ['Citrus', 9, 'fruits', 'citrus']
];
const data_cars = [
  ['SUV', 5, 'cars', 'suv'],
  ['Sports', 3, 'cars', 'sports']
];
// level 3
const data_dogs = [
  ['Corgi', 5, 'dogs'], // the "childest" data need not to be specified a `childGroupId`
  ['Bulldog', 6, 'dogs'],
  ['Shiba Inu', 7, 'dogs']
];
const data_cats = [
  ['American Shorthair', 2, 'cats'],
  ['British Shorthair', 9, 'cats'],
  ['Bengal', 2, 'cats'],
  ['Birman', 2, 'cats']
];
const data_birds = [
  ['Goose', 1, 'birds'],
  ['Owl', 2, 'birds'],
  ['Eagle', 8, 'birds']
];
const data_pomes = [
  ['Apple', 9, 'pomes'],
  ['Pear', 2, 'pomes'],
  ['Kiwi', 1, 'pomes']
];
const data_berries = [
  ['Blackberries', 7, 'berries'],
  ['Cranberries', 2, 'berries'],
  ['Strawberries', 9, 'berries'],
  ['Grapes', 4, 'berries']
];
const data_citrus = [
  ['Oranges', 3, 'citrus'],
  ['Grapefruits', 7, 'citrus'],
  ['Tangerines', 8, 'citrus'],
  ['Lemons', 7, 'citrus'],
  ['Limes', 3, 'citrus'],
  ['Kumquats', 2, 'citrus'],
  ['Citrons', 3, 'citrus'],
  ['Tengelows', 3, 'citrus'],
  ['Uglifruit', 1, 'citrus']
];
const data_suv = [
  ['Mazda CX-30', 7, 'suv'],
  ['BMW X2', 7, 'suv'],
  ['Ford Bronco Sport', 2, 'suv'],
  ['Toyota RAV4', 9, 'suv'],
  ['Porsche Macan', 4, 'suv']
];
const data_sports = [
  ['Porsche 718 Cayman', 2, 'sports'],
  ['Porsche 911 Turbo', 2, 'sports'],
  ['Ferrari F8', 4, 'sports']
];
const allLevelData = [
  data_things,
  data_animals,
  data_fruits,
  data_cars,
  data_dogs,
  data_cats,
  data_birds,
  data_pomes,
  data_berries,
  data_citrus,
  data_suv,
  data_sports
];

const allOptions = {};

allLevelData.forEach((data, index) => {
  // since dataItems of each data have same groupId in this
  // example, we can use groupId as optionId for optionStack.
  const optionId = data[0][2];

  const option = {
    id: optionId, // option.id is not a property of emyCharts option model, but can be accessed if we provide it
    xAxis: {
      type: 'category'
    },
    yAxis: {
      minInterval: 1
    },
    animationDurationUpdate: 500,
    series: {
      type: 'bar',
      dimensions: ['x', 'y', 'groupId', 'childGroupId'],
      encode: {
        x: 'x',
        y: 'y',
        itemGroupId: 'groupId',
        itemChildGroupId: 'childGroupId'
      },
      data,
      universalTransition: {
        enabled: true,
        divideShape: 'clone'
      }
    },
    graphic: [
      {
        type: 'text',
        left: 50,
        top: 20,
        style: {
          text: 'Back',
          fontSize: 18,
          fill: 'grey'
        },
        onclick: function () {
          goBack();
        }
      }
    ]
  };
  allOptions[optionId] = option;
});

// A stack to remember previous option id
const optionStack = [];

const goForward = (optionId) => {
  optionStack.push(myChart.getOption().id); // push current option id into stack.
  myChart.setOption(allOptions[optionId]);
};

const goBack = () => {
  if (optionStack.length === 0) {
    console.log('Already in root level!');
  } else {
    console.log('Go back to previous level.');
    myChart.setOption(allOptions[optionStack.pop()]);
  }
};

option = allOptions['things']; // The initial option is the root data option
"""#,
        option: [
            // `option.id` is not an echarts component; the example sets it so the click handler can
            // read the current level back out of `myChart.getOption()`.
            "id": "things",
            "xAxis": [
                "type": "category"
            ] as [String: Any],
            "yAxis": [
                "minInterval": 1.0
            ] as [String: Any],
            "animationDurationUpdate": 500.0,
            "series": [
                "type": "bar",
                "dimensions": ["x", "y", "groupId", "childGroupId"],
                "encode": [
                    "x": "x",
                    "y": "y",
                    "itemGroupId": "groupId",
                    "itemChildGroupId": "childGroupId"
                ] as [String: Any],
                "data": barMultiDrilldownThingsData,
                "universalTransition": [
                    "enabled": true,
                    "divideShape": "clone"
                ] as [String: Any]
            ] as [String: Any],
            "graphic": [
                [
                    "type": "text",
                    "left": 50.0,
                    "top": 20.0,
                    "style": [
                        "text": "Back",
                        "fontSize": 18.0,
                        "fill": "grey"
                    ] as [String: Any]
                    // onclick omitted — the JS closure called goBack(), which popped the
                    // option stack and re-setOption'd the parent level. Click-driven, so it is inert
                    // in the gallery's single static frame anyway.
                ] as [String: Any]
            ]
        ])
}

// Root level ("things"). Row layout matches series.dimensions: [x, y, groupId, childGroupId].
// The 11 child-level datasets (animals/fruits/cars/dogs/... ) live only in webOptionJS — they are
// reachable solely by clicking a bar, which a static render never does.
private let barMultiDrilldownThingsData: [[Any]] = [
    ["Animals", 3.0, "things", "animals"],
    ["Fruits", 3.0, "things", "fruits"],
    ["Cars", 2.0, "things", "cars"]
]
