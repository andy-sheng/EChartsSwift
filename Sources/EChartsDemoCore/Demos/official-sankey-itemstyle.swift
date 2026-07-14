// official-sankey-itemstyle — replica of https://echarts.apache.org/examples/zh/editor.html?c=sankey-itemstyle
// title: Specify ItemStyle for Each Node in Sankey / titleCN: 桑基图节点自定义样式
// A currency → city cash-flow sankey where EVERY node carries its own itemStyle (color/borderColor),
// links inherit their source node's color (lineStyle.color: 'source', curveness 0.5).
// DEVIATIONS: none functionally — the official source is one static `option` literal with no data
// fetch, no closures and no timers, so the single static frame IS the whole example.
//   - webOptionJS is the official example VERBATIM; only its leading title-comment block and the
//     trailing `export {};` (a TS module marker, not part of the option) are dropped.
//   - The Swift `option` mirrors it key-for-key. The official option has no JS-function-valued keys,
//     so nothing is omitted from the native side and there are no PORT-NOTEs to carry.
//   - The 99 nodes and 109 links are hoisted out of the Swift option literal into file-scope tables
//     (the type-checker chokes on nested heterogeneous literals this big). The hoist is lossless:
//     the node table is (name, color) pairs because every official node sets borderColor == color.
// NOTE (not a typo to "fix"): 4 nodes — the leftmost card-type column — carry `rgba(r,g,b,255)`,
// i.e. an out-of-range alpha. zrender's `clampCssFloat` clamps it to 1 and the port mirrors that
// (ZRenderKit/tool/color.swift), so both panes read these as opaque. Keep the strings as upstream.
extension EChartsDemoRegistry {
    static let official_sankey_itemstyle = EChartsDemo(
        name: "official-sankey-itemstyle", category: "sankey",
        summary: "桑基图节点自定义样式 — Specify ItemStyle for Each Node in Sankey",
        width: 720, height: 460,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
option = {
  backgroundColor: '#fff',
  title: {
    subtext: 'Data From lisachristina1234 on GitHub',
    left: 'center'
  },
  series: [
    {
      type: 'sankey',
      left: 50.0,
      top: 20.0,
      right: 150.0,
      bottom: 25.0,
      data: [
        {
          name: 'Werne',
          itemStyle: {
            color: '#f18bbf',
            borderColor: '#f18bbf'
          }
        },
        {
          name: 'Duesseldorf',
          itemStyle: {
            color: '#0078D7',
            borderColor: '#0078D7'
          }
        },
        {
          name: 'Cambridge',
          itemStyle: {
            color: '#3891A7',
            borderColor: '#3891A7'
          }
        },
        {
          name: 'Colma',
          itemStyle: {
            color: '#0037DA',
            borderColor: '#0037DA'
          }
        },
        {
          name: 'W. York',
          itemStyle: {
            color: '#C0BEAF',
            borderColor: '#C0BEAF'
          }
        },
        {
          name: 'Frankfurt am Main',
          itemStyle: {
            color: '#EA005E',
            borderColor: '#EA005E'
          }
        },
        {
          name: 'Metz',
          itemStyle: {
            color: '#D13438',
            borderColor: '#D13438'
          }
        },
        {
          name: 'Orleans',
          itemStyle: {
            color: '#567C73',
            borderColor: '#567C73'
          }
        },
        {
          name: 'Saint-Denis',
          itemStyle: {
            color: '#9ed566',
            borderColor: '#9ed566'
          }
        },
        {
          name: 'Hof',
          itemStyle: {
            color: '#2BCC7F',
            borderColor: '#2BCC7F'
          }
        },
        {
          name: 'Cliffside',
          itemStyle: {
            color: '#809B48',
            borderColor: '#809B48'
          }
        },
        {
          name: 'Leeds',
          itemStyle: {
            color: '#9B2D1F',
            borderColor: '#9B2D1F'
          }
        },
        {
          name: 'Victoria',
          itemStyle: {
            color: '#604878',
            borderColor: '#604878'
          }
        },
        {
          name: 'Erlangen',
          itemStyle: {
            color: '#A5644E',
            borderColor: '#A5644E'
          }
        },
        {
          name: 'Saint Germain en Laye',
          itemStyle: {
            color: '#2D3F3A',
            borderColor: '#2D3F3A'
          }
        },
        {
          name: 'Roissy en Brie',
          itemStyle: {
            color: '#761721',
            borderColor: '#761721'
          }
        },
        {
          name: 'Wokingham',
          itemStyle: {
            color: '#B1BADD',
            borderColor: '#B1BADD'
          }
        },
        {
          name: 'Runcorn',
          itemStyle: {
            color: '#B0CCB0',
            borderColor: '#B0CCB0'
          }
        },
        {
          name: 'Newton',
          itemStyle: {
            color: '#8164A3',
            borderColor: '#8164A3'
          }
        },
        {
          name: 'Morangis',
          itemStyle: {
            color: '#8E562E',
            borderColor: '#8E562E'
          }
        },
        {
          name: 'Metchosin',
          itemStyle: {
            color: '#C1504D',
            borderColor: '#C1504D'
          }
        },
        {
          name: 'Kirkby',
          itemStyle: {
            color: '#CCAF0A',
            borderColor: '#CCAF0A'
          }
        },
        {
          name: 'London',
          itemStyle: {
            color: '#956251',
            borderColor: '#956251'
          }
        },
        {
          name: 'Offenbach',
          itemStyle: {
            color: '#C17529',
            borderColor: '#C17529'
          }
        },
        {
          name: 'Warrington',
          itemStyle: {
            color: '#CEC597',
            borderColor: '#CEC597'
          }
        },
        {
          name: 'Vancouver',
          itemStyle: {
            color: '#9F2936',
            borderColor: '#9F2936'
          }
        },
        {
          name: 'SuperiorCard',
          itemStyle: {
            color: 'rgba(128,155,72,255)',
            borderColor: 'rgba(128,155,72,255)'
          }
        },
        {
          name: 'Lille',
          itemStyle: {
            color: '#ac7430',
            borderColor: '#ac7430'
          }
        },
        {
          name: 'Hamburg',
          itemStyle: {
            color: '#00BCF2',
            borderColor: '#00BCF2'
          }
        },
        {
          name: 'Langley',
          itemStyle: {
            color: '#CD7B38',
            borderColor: '#CD7B38'
          }
        },
        {
          name: 'Les Ulis',
          itemStyle: {
            color: '#424242',
            borderColor: '#424242'
          }
        },
        {
          name: 'Saarbrücken',
          itemStyle: {
            color: '#f63185',
            borderColor: '#f63185'
          }
        },
        {
          name: 'N. Vancouver',
          itemStyle: {
            color: '#9CBC59',
            borderColor: '#9CBC59'
          }
        },
        {
          name: 'Chalk Riber',
          itemStyle: {
            color: '#4F4BD9',
            borderColor: '#4F4BD9'
          }
        },
        {
          name: 'Esher-Molesey',
          itemStyle: {
            color: '#3EC562',
            borderColor: '#3EC562'
          }
        },
        {
          name: 'Chatou',
          itemStyle: {
            color: '#F06F2E',
            borderColor: '#F06F2E'
          }
        },
        {
          name: 'Hannover',
          itemStyle: {
            color: '#C3986D',
            borderColor: '#C3986D'
          }
        },
        {
          name: 'Roncq',
          itemStyle: {
            color: '#4D291C',
            borderColor: '#4D291C'
          }
        },
        {
          name: 'Ingolstadt',
          itemStyle: {
            color: '#009c7a',
            borderColor: '#009c7a'
          }
        },
        {
          name: 'Drancy',
          itemStyle: {
            color: '#986F0B',
            borderColor: '#986F0B'
          }
        },
        {
          name: 'Langford',
          itemStyle: {
            color: '#3C8EA4',
            borderColor: '#3C8EA4'
          }
        },
        {
          name: 'Lebanon',
          itemStyle: {
            color: '#4F82BE',
            borderColor: '#4F82BE'
          }
        },
        {
          name: 'Maidenhead',
          itemStyle: {
            color: '#D38017',
            borderColor: '#D38017'
          }
        },
        {
          name: 'Stoke-on-Trent',
          itemStyle: {
            color: '#A8CDD7',
            borderColor: '#A8CDD7'
          }
        },
        {
          name: 'Peterborough',
          itemStyle: {
            color: '#7A072D',
            borderColor: '#7A072D'
          }
        },
        {
          name: 'Suresnes',
          itemStyle: {
            color: '#859599',
            borderColor: '#859599'
          }
        },
        {
          name: 'Versailles',
          itemStyle: {
            color: '#84AA33',
            borderColor: '#84AA33'
          }
        },
        {
          name: 'Neunkirchen',
          itemStyle: {
            color: '#ff8b67',
            borderColor: '#ff8b67'
          }
        },
        {
          name: 'Vista',
          itemStyle: {
            color: 'rgba(106,82,134,255)',
            borderColor: 'rgba(106,82,134,255)'
          }
        },
        {
          name: 'Westminster',
          itemStyle: {
            color: '#1B587C',
            borderColor: '#1B587C'
          }
        },
        {
          name: 'Kiel',
          itemStyle: {
            color: '#A19574',
            borderColor: '#A19574'
          }
        },
        {
          name: 'Newcastle upon Tyne',
          itemStyle: {
            color: '#918485',
            borderColor: '#918485'
          }
        },
        {
          name: 'Oxon',
          itemStyle: {
            color: '#FFA98C',
            borderColor: '#FFA98C'
          }
        },
        {
          name: 'West Sussex',
          itemStyle: {
            color: '#B0E3C0',
            borderColor: '#B0E3C0'
          }
        },
        {
          name: 'Oak Bay',
          itemStyle: {
            color: '#4BADC7',
            borderColor: '#4BADC7'
          }
        },
        {
          name: 'Milton Keynes',
          itemStyle: {
            color: '#BA144C',
            borderColor: '#BA144C'
          }
        },
        {
          name: 'Eilenburg',
          itemStyle: {
            color: '#F0A22E',
            borderColor: '#F0A22E'
          }
        },
        {
          name: 'ColonialVoice',
          itemStyle: {
            color: 'rgba(64,105,157,255)',
            borderColor: 'rgba(64,105,157,255)'
          }
        },
        {
          name: 'Liverpool',
          itemStyle: {
            color: '#A28E6A',
            borderColor: '#A28E6A'
          }
        },
        {
          name: 'Calgary',
          itemStyle: {
            color: '#9F413E',
            borderColor: '#9F413E'
          }
        },
        {
          name: 'CAD',
          itemStyle: {
            color: '#40699D',
            borderColor: '#40699D'
          }
        },
        {
          name: 'Paris La Defense',
          itemStyle: {
            color: '#989391',
            borderColor: '#989391'
          }
        },
        {
          name: "Villeneuve-d'Ascq",
          itemStyle: {
            color: '#886CE4',
            borderColor: '#886CE4'
          }
        },
        {
          name: 'Gloucestershire',
          itemStyle: {
            color: '#964305',
            borderColor: '#964305'
          }
        },
        {
          name: 'Gateshead',
          itemStyle: {
            color: '#485FB5',
            borderColor: '#485FB5'
          }
        },
        {
          name: 'Salzgitter',
          itemStyle: {
            color: '#87a0c7',
            borderColor: '#87a0c7'
          }
        },
        {
          name: 'Woolston',
          itemStyle: {
            color: '#FFE2C5',
            borderColor: '#FFE2C5'
          }
        },
        {
          name: 'Frankfurt',
          itemStyle: {
            color: '#40699D',
            borderColor: '#40699D'
          }
        },
        {
          name: 'Münster',
          itemStyle: {
            color: '#7e7eb2',
            borderColor: '#7e7eb2'
          }
        },
        {
          name: 'York',
          itemStyle: {
            color: '#587C7D',
            borderColor: '#587C7D'
          }
        },
        {
          name: 'High Wycombe',
          itemStyle: {
            color: '#F07F09',
            borderColor: '#F07F09'
          }
        },
        {
          name: 'Stuttgart',
          itemStyle: {
            color: '#E3008C',
            borderColor: '#E3008C'
          }
        },
        {
          name: 'Sooke',
          itemStyle: {
            color: '#4E8542',
            borderColor: '#4E8542'
          }
        },
        {
          name: 'Essen',
          itemStyle: {
            color: '#B58B80',
            borderColor: '#B58B80'
          }
        },
        {
          name: 'München',
          itemStyle: {
            color: '#4dc0a6',
            borderColor: '#4dc0a6'
          }
        },
        {
          name: 'Haney',
          itemStyle: {
            color: '#6A5286',
            borderColor: '#6A5286'
          }
        },
        {
          name: 'Port Hammond',
          itemStyle: {
            color: '#F89746',
            borderColor: '#F89746'
          }
        },
        {
          name: 'Saint Ouen',
          itemStyle: {
            color: '#744DA9',
            borderColor: '#744DA9'
          }
        },
        {
          name: 'Watford',
          itemStyle: {
            color: '#E8B7B7',
            borderColor: '#E8B7B7'
          }
        },
        {
          name: 'GBP',
          itemStyle: {
            color: '#C32D2E',
            borderColor: '#C32D2E'
          }
        },
        {
          name: 'Paderborn',
          itemStyle: {
            color: '#F0C42E',
            borderColor: '#F0C42E'
          }
        },
        {
          name: 'Dunkerque',
          itemStyle: {
            color: '#881798',
            borderColor: '#881798'
          }
        },
        {
          name: 'Colomiers',
          itemStyle: {
            color: '#efa835',
            borderColor: '#efa835'
          }
        },
        {
          name: 'Oxford',
          itemStyle: {
            color: '#D8B25C',
            borderColor: '#D8B25C'
          }
        },
        {
          name: 'Bury',
          itemStyle: {
            color: '#FEB80A',
            borderColor: '#FEB80A'
          }
        },
        {
          name: 'Royal Oak',
          itemStyle: {
            color: '#009DD9',
            borderColor: '#009DD9'
          }
        },
        {
          name: 'Shawnee',
          itemStyle: {
            color: '#F07F09',
            borderColor: '#F07F09'
          }
        },
        {
          name: 'Lancaster',
          itemStyle: {
            color: '#D34817',
            borderColor: '#D34817'
          }
        },
        {
          name: 'DEM',
          itemStyle: {
            color: '#4E342E',
            borderColor: '#4E342E'
          }
        },
        {
          name: 'Grevenbroich',
          itemStyle: {
            color: '#FFA836',
            borderColor: '#FFA836'
          }
        },
        {
          name: 'Distinguish',
          itemStyle: {
            color: 'rgba(159,65,62,255)',
            borderColor: 'rgba(159,65,62,255)'
          }
        },
        {
          name: 'Cheltenham',
          itemStyle: {
            color: '#FF6551',
            borderColor: '#FF6551'
          }
        },
        {
          name: 'Reading',
          itemStyle: {
            color: '#72A376',
            borderColor: '#72A376'
          }
        },
        {
          name: 'Pantin',
          itemStyle: {
            color: '#69797E',
            borderColor: '#69797E'
          }
        },
        {
          name: 'Kassel',
          itemStyle: {
            color: '#e65e20',
            borderColor: '#e65e20'
          }
        },
        {
          name: 'Orly',
          itemStyle: {
            color: '#6E6A68',
            borderColor: '#6E6A68'
          }
        },
        {
          name: 'FRF',
          itemStyle: {
            color: '#5ba33b',
            borderColor: '#5ba33b'
          }
        },
        {
          name: 'Cergy',
          itemStyle: {
            color: '#B4009E',
            borderColor: '#B4009E'
          }
        },
        {
          name: 'Paris',
          itemStyle: {
            color: '#666666',
            borderColor: '#666666'
          }
        }
      ],
      links: [
        {
          source: 'FRF',
          target: 'Colomiers',
          value: 357.8399963378906
        },
        {
          source: 'SuperiorCard',
          target: 'FRF',
          value: 894.5999908447266
        },
        {
          source: 'DEM',
          target: 'München',
          value: 178.9199981689453
        },
        {
          source: 'GBP',
          target: 'Reading',
          value: 188.52999836206436
        },
        {
          source: 'CAD',
          target: 'Shawnee',
          value: 2346.919983509928
        },
        {
          source: 'GBP',
          target: 'Kirkby',
          value: 753.4000000059605
        },
        {
          source: 'FRF',
          target: 'Roncq',
          value: 178.9199981689453
        },
        {
          source: 'GBP',
          target: 'Peterborough',
          value: 999.159998036921
        },
        {
          source: 'DEM',
          target: 'Frankfurt am Main',
          value: 536.7599945068359
        },
        {
          source: 'GBP',
          target: 'Oxford',
          value: 1831.3799968883395
        },
        {
          source: 'Vista',
          target: 'FRF',
          value: 1789.1999816894531
        },
        {
          source: 'CAD',
          target: 'Langley',
          value: 1274.8199949413538
        },
        {
          source: 'DEM',
          target: 'Offenbach',
          value: 357.8399963378906
        },
        {
          source: 'FRF',
          target: "Villeneuve-d'Ascq",
          value: 178.9199981689453
        },
        {
          source: 'FRF',
          target: 'Dunkerque',
          value: 357.8399963378906
        },
        {
          source: 'DEM',
          target: 'Eilenburg',
          value: 178.9199981689453
        },
        {
          source: 'FRF',
          target: 'Paris',
          value: 1073.5199890136719
        },
        {
          source: 'GBP',
          target: 'Maidenhead',
          value: 549.8400026857853
        },
        {
          source: 'CAD',
          target: 'Sooke',
          value: 1764.499989286065
        },
        {
          source: 'CAD',
          target: 'Vancouver',
          value: 1528.580000281334
        },
        {
          source: 'DEM',
          target: 'Hamburg',
          value: 357.8399963378906
        },
        {
          source: 'GBP',
          target: 'London',
          value: 8619.309983983636
        },
        {
          source: 'CAD',
          target: 'Oak Bay',
          value: 1565.109990529716
        },
        {
          source: 'Distinguish',
          target: 'FRF',
          value: 2683.7999725341797
        },
        {
          source: 'DEM',
          target: 'Neunkirchen',
          value: 178.9199981689453
        },
        {
          source: 'FRF',
          target: 'Cergy',
          value: 178.9199981689453
        },
        {
          source: 'DEM',
          target: 'Hof',
          value: 357.8399963378906
        },
        {
          source: 'FRF',
          target: 'Paris La Defense',
          value: 178.9199981689453
        },
        {
          source: 'CAD',
          target: 'Westminster',
          value: 1149.7999994903803
        },
        {
          source: 'DEM',
          target: 'Ingolstadt',
          value: 536.7599945068359
        },
        {
          source: 'GBP',
          target: 'Saint Ouen',
          value: 0.5899999737739563
        },
        {
          source: 'FRF',
          target: 'Lille',
          value: 357.8399963378906
        },
        {
          source: 'GBP',
          target: 'Leeds',
          value: 1356.6899970173836
        },
        {
          source: 'FRF',
          target: 'Morangis',
          value: 357.8399963378906
        },
        {
          source: 'GBP',
          target: 'Orly',
          value: 0.5899999737739563
        },
        {
          source: 'SuperiorCard',
          target: 'DEM',
          value: 1431.3599853515625
        },
        {
          source: 'Vista',
          target: 'CAD',
          value: 5369.929964579642
        },
        {
          source: 'GBP',
          target: 'Paris',
          value: 0.6399999856948853
        },
        {
          source: 'GBP',
          target: 'Liverpool',
          value: 857.1999968588352
        },
        {
          source: 'GBP',
          target: 'Stoke-on-Trent',
          value: 1131.7099939212203
        },
        {
          source: 'Distinguish',
          target: 'DEM',
          value: 2504.8799743652344
        },
        {
          source: 'CAD',
          target: 'Langford',
          value: 2343.4599857851863
        },
        {
          source: 'DEM',
          target: 'Kassel',
          value: 536.7599945068359
        },
        {
          source: 'GBP',
          target: 'High Wycombe',
          value: 216.83999809622765
        },
        {
          source: 'CAD',
          target: 'Port Hammond',
          value: 1711.1399984136224
        },
        {
          source: 'DEM',
          target: 'Duesseldorf',
          value: 178.9199981689453
        },
        {
          source: 'GBP',
          target: 'Gloucestershire',
          value: 422.28999888151884
        },
        {
          source: 'Distinguish',
          target: 'GBP',
          value: 10384.949975416064
        },
        {
          source: 'FRF',
          target: 'Roissy en Brie',
          value: 178.9199981689453
        },
        {
          source: 'GBP',
          target: 'West Sussex',
          value: 592.1700052022934
        },
        {
          source: 'CAD',
          target: 'Cliffside',
          value: 2906.2699892893434
        },
        {
          source: 'GBP',
          target: 'Newcastle upon Tyne',
          value: 1448.2899911925197
        },
        {
          source: 'GBP',
          target: 'Runcorn',
          value: 1120.4800013303757
        },
        {
          source: 'GBP',
          target: 'W. York',
          value: 612.1199932694435
        },
        {
          source: 'DEM',
          target: 'Kiel',
          value: 178.9199981689453
        },
        {
          source: 'GBP',
          target: 'Woolston',
          value: 833.3199937939644
        },
        {
          source: 'Distinguish',
          target: 'CAD',
          value: 6950.059956334531
        },
        {
          source: 'DEM',
          target: 'Frankfurt',
          value: 715.6799926757812
        },
        {
          source: 'CAD',
          target: 'Colma',
          value: 0.2199999988079071
        },
        {
          source: 'DEM',
          target: 'Essen',
          value: 178.9199981689453
        },
        {
          source: 'FRF',
          target: 'Chatou',
          value: 178.9199981689453
        },
        {
          source: 'GBP',
          target: 'Cheltenham',
          value: 573.0499979257584
        },
        {
          source: 'SuperiorCard',
          target: 'GBP',
          value: 8228.39999615401
        },
        {
          source: 'CAD',
          target: 'Haney',
          value: 2310.4499812424183
        },
        {
          source: 'FRF',
          target: 'Saint Ouen',
          value: 178.9199981689453
        },
        {
          source: 'CAD',
          target: 'Chalk Riber',
          value: 0.9200000166893005
        },
        {
          source: 'DEM',
          target: 'Salzgitter',
          value: 178.9199981689453
        },
        {
          source: 'ColonialVoice',
          target: 'FRF',
          value: 1610.2799835205078
        },
        {
          source: 'DEM',
          target: 'Stuttgart',
          value: 357.8399963378906
        },
        {
          source: 'FRF',
          target: 'Saint-Denis',
          value: 178.9199981689453
        },
        {
          source: 'CAD',
          target: 'Royal Oak',
          value: 2128.459992274642
        },
        {
          source: 'FRF',
          target: 'Les Ulis',
          value: 715.6799926757812
        },
        {
          source: 'FRF',
          target: 'Drancy',
          value: 178.9199981689453
        },
        {
          source: 'GBP',
          target: 'Esher-Molesey',
          value: 911.4700058028102
        },
        {
          source: 'SuperiorCard',
          target: 'CAD',
          value: 7388.099954992533
        },
        {
          source: 'GBP',
          target: 'Bury',
          value: 903.9400005489588
        },
        {
          source: 'GBP',
          target: 'Watford',
          value: 1326.5300009772182
        },
        {
          source: 'CAD',
          target: 'Victoria',
          value: 827.3899968340993
        },
        {
          source: 'DEM',
          target: 'Saarbrücken',
          value: 178.9199981689453
        },
        {
          source: 'GBP',
          target: 'Lancaster',
          value: 685.6899967193604
        },
        {
          source: 'FRF',
          target: 'Pantin',
          value: 178.9199981689453
        },
        {
          source: 'CAD',
          target: 'Newton',
          value: 1781.909985654056
        },
        {
          source: 'GBP',
          target: 'Oxon',
          value: 493.6499986946583
        },
        {
          source: 'CAD',
          target: 'Calgary',
          value: 361.3899962902069
        },
        {
          source: 'DEM',
          target: 'Münster',
          value: 715.6799926757812
        },
        {
          source: 'DEM',
          target: 'Grevenbroich',
          value: 536.7599945068359
        },
        {
          source: 'DEM',
          target: 'Paderborn',
          value: 357.8399963378906
        },
        {
          source: 'GBP',
          target: 'York',
          value: 3172.9999914616346
        },
        {
          source: 'CAD',
          target: 'Metchosin',
          value: 1750.7899813987315
        },
        {
          source: 'FRF',
          target: 'Suresnes',
          value: 357.8399963378906
        },
        {
          source: 'FRF',
          target: 'Versailles',
          value: 894.5999908447266
        },
        {
          source: 'DEM',
          target: 'Erlangen',
          value: 536.7599945068359
        },
        {
          source: 'CAD',
          target: 'Lebanon',
          value: 0.8700000047683716
        },
        {
          source: 'GBP',
          target: 'Wokingham',
          value: 812.6600027084351
        },
        {
          source: 'GBP',
          target: 'Cambridge',
          value: 500.36999743431807
        },
        {
          source: 'ColonialVoice',
          target: 'GBP',
          value: 8040.7799860313535
        },
        {
          source: 'FRF',
          target: 'Saint Germain en Laye',
          value: 178.9199981689453
        },
        {
          source: 'FRF',
          target: 'Metz',
          value: 178.9199981689453
        },
        {
          source: 'FRF',
          target: 'Orleans',
          value: 357.8399963378906
        },
        {
          source: 'GBP',
          target: 'Milton Keynes',
          value: 1648.2200061008334
        },
        {
          source: 'GBP',
          target: 'Warrington',
          value: 2162.8300000429153
        },
        {
          source: 'CAD',
          target: 'N. Vancouver',
          value: 1862.4599857926369
        },
        {
          source: 'DEM',
          target: 'Hannover',
          value: 178.9199981689453
        },
        {
          source: 'Vista',
          target: 'GBP',
          value: 9497.539981640875
        },
        {
          source: 'DEM',
          target: 'Werne',
          value: 178.9199981689453
        },
        {
          source: 'ColonialVoice',
          target: 'DEM',
          value: 1789.1999816894531
        },
        {
          source: 'ColonialVoice',
          target: 'CAD',
          value: 7907.36997512728
        },
        {
          source: 'GBP',
          target: 'Gateshead',
          value: 1425.7099913656712
        },
        {
          source: 'Vista',
          target: 'DEM',
          value: 1968.1199798583984
        }
      ],
      lineStyle: {
        color: 'source',
        curveness: 0.5
      },
      itemStyle: {
        color: '#1f77b4',
        borderColor: '#1f77b4'
      },
      label: {
        color: 'rgba(0,0,0,0.7)',
        fontFamily: 'Arial',
        fontSize: 10
      }
    }
  ],
  tooltip: {
    trigger: 'item'
  }
};
"""#,
        option: [
            "backgroundColor": "#fff",
            "title": [
                "subtext": "Data From lisachristina1234 on GitHub",
                "left": "center"
            ] as [String: Any],
            "series": [
                [
                    "type": "sankey",
                    "left": 50.0,
                    "top": 20.0,
                    "right": 150.0,
                    "bottom": 25.0,
                    "data": sankeyItemStyleNodes,
                    "links": sankeyItemStyleLinks,
                    "lineStyle": [
                        "color": "source",
                        "curveness": 0.5
                    ] as [String: Any],
                    "itemStyle": [
                        "color": "#1f77b4",
                        "borderColor": "#1f77b4"
                    ] as [String: Any],
                    "label": [
                        "color": "rgba(0,0,0,0.7)",
                        "fontFamily": "Arial",
                        "fontSize": 10.0
                    ] as [String: Any]
                ] as [String: Any]
            ],
            "tooltip": [
                "trigger": "item"
            ] as [String: Any]
        ])
}

// Every official node is `{ name, itemStyle: { color: C, borderColor: C } }` — one color per node.
private let sankeyItemStyleNodeColors: [(String, String)] = [
    ("Werne", "#f18bbf"),
    ("Duesseldorf", "#0078D7"),
    ("Cambridge", "#3891A7"),
    ("Colma", "#0037DA"),
    ("W. York", "#C0BEAF"),
    ("Frankfurt am Main", "#EA005E"),
    ("Metz", "#D13438"),
    ("Orleans", "#567C73"),
    ("Saint-Denis", "#9ed566"),
    ("Hof", "#2BCC7F"),
    ("Cliffside", "#809B48"),
    ("Leeds", "#9B2D1F"),
    ("Victoria", "#604878"),
    ("Erlangen", "#A5644E"),
    ("Saint Germain en Laye", "#2D3F3A"),
    ("Roissy en Brie", "#761721"),
    ("Wokingham", "#B1BADD"),
    ("Runcorn", "#B0CCB0"),
    ("Newton", "#8164A3"),
    ("Morangis", "#8E562E"),
    ("Metchosin", "#C1504D"),
    ("Kirkby", "#CCAF0A"),
    ("London", "#956251"),
    ("Offenbach", "#C17529"),
    ("Warrington", "#CEC597"),
    ("Vancouver", "#9F2936"),
    ("SuperiorCard", "rgba(128,155,72,255)"),
    ("Lille", "#ac7430"),
    ("Hamburg", "#00BCF2"),
    ("Langley", "#CD7B38"),
    ("Les Ulis", "#424242"),
    ("Saarbrücken", "#f63185"),
    ("N. Vancouver", "#9CBC59"),
    ("Chalk Riber", "#4F4BD9"),
    ("Esher-Molesey", "#3EC562"),
    ("Chatou", "#F06F2E"),
    ("Hannover", "#C3986D"),
    ("Roncq", "#4D291C"),
    ("Ingolstadt", "#009c7a"),
    ("Drancy", "#986F0B"),
    ("Langford", "#3C8EA4"),
    ("Lebanon", "#4F82BE"),
    ("Maidenhead", "#D38017"),
    ("Stoke-on-Trent", "#A8CDD7"),
    ("Peterborough", "#7A072D"),
    ("Suresnes", "#859599"),
    ("Versailles", "#84AA33"),
    ("Neunkirchen", "#ff8b67"),
    ("Vista", "rgba(106,82,134,255)"),
    ("Westminster", "#1B587C"),
    ("Kiel", "#A19574"),
    ("Newcastle upon Tyne", "#918485"),
    ("Oxon", "#FFA98C"),
    ("West Sussex", "#B0E3C0"),
    ("Oak Bay", "#4BADC7"),
    ("Milton Keynes", "#BA144C"),
    ("Eilenburg", "#F0A22E"),
    ("ColonialVoice", "rgba(64,105,157,255)"),
    ("Liverpool", "#A28E6A"),
    ("Calgary", "#9F413E"),
    ("CAD", "#40699D"),
    ("Paris La Defense", "#989391"),
    ("Villeneuve-d'Ascq", "#886CE4"),
    ("Gloucestershire", "#964305"),
    ("Gateshead", "#485FB5"),
    ("Salzgitter", "#87a0c7"),
    ("Woolston", "#FFE2C5"),
    ("Frankfurt", "#40699D"),
    ("Münster", "#7e7eb2"),
    ("York", "#587C7D"),
    ("High Wycombe", "#F07F09"),
    ("Stuttgart", "#E3008C"),
    ("Sooke", "#4E8542"),
    ("Essen", "#B58B80"),
    ("München", "#4dc0a6"),
    ("Haney", "#6A5286"),
    ("Port Hammond", "#F89746"),
    ("Saint Ouen", "#744DA9"),
    ("Watford", "#E8B7B7"),
    ("GBP", "#C32D2E"),
    ("Paderborn", "#F0C42E"),
    ("Dunkerque", "#881798"),
    ("Colomiers", "#efa835"),
    ("Oxford", "#D8B25C"),
    ("Bury", "#FEB80A"),
    ("Royal Oak", "#009DD9"),
    ("Shawnee", "#F07F09"),
    ("Lancaster", "#D34817"),
    ("DEM", "#4E342E"),
    ("Grevenbroich", "#FFA836"),
    ("Distinguish", "rgba(159,65,62,255)"),
    ("Cheltenham", "#FF6551"),
    ("Reading", "#72A376"),
    ("Pantin", "#69797E"),
    ("Kassel", "#e65e20"),
    ("Orly", "#6E6A68"),
    ("FRF", "#5ba33b"),
    ("Cergy", "#B4009E"),
    ("Paris", "#666666"),
]

private let sankeyItemStyleNodes: [[String: Any]] = sankeyItemStyleNodeColors.map { name, color in
    [
        "name": name,
        "itemStyle": ["color": color, "borderColor": color] as [String: Any]
    ] as [String: Any]
}

// (source, target, value)
private let sankeyItemStyleLinkRows: [(String, String, Double)] = [
    ("FRF", "Colomiers", 357.8399963378906),
    ("SuperiorCard", "FRF", 894.5999908447266),
    ("DEM", "München", 178.9199981689453),
    ("GBP", "Reading", 188.52999836206436),
    ("CAD", "Shawnee", 2346.919983509928),
    ("GBP", "Kirkby", 753.4000000059605),
    ("FRF", "Roncq", 178.9199981689453),
    ("GBP", "Peterborough", 999.159998036921),
    ("DEM", "Frankfurt am Main", 536.7599945068359),
    ("GBP", "Oxford", 1831.3799968883395),
    ("Vista", "FRF", 1789.1999816894531),
    ("CAD", "Langley", 1274.8199949413538),
    ("DEM", "Offenbach", 357.8399963378906),
    ("FRF", "Villeneuve-d'Ascq", 178.9199981689453),
    ("FRF", "Dunkerque", 357.8399963378906),
    ("DEM", "Eilenburg", 178.9199981689453),
    ("FRF", "Paris", 1073.5199890136719),
    ("GBP", "Maidenhead", 549.8400026857853),
    ("CAD", "Sooke", 1764.499989286065),
    ("CAD", "Vancouver", 1528.580000281334),
    ("DEM", "Hamburg", 357.8399963378906),
    ("GBP", "London", 8619.309983983636),
    ("CAD", "Oak Bay", 1565.109990529716),
    ("Distinguish", "FRF", 2683.7999725341797),
    ("DEM", "Neunkirchen", 178.9199981689453),
    ("FRF", "Cergy", 178.9199981689453),
    ("DEM", "Hof", 357.8399963378906),
    ("FRF", "Paris La Defense", 178.9199981689453),
    ("CAD", "Westminster", 1149.7999994903803),
    ("DEM", "Ingolstadt", 536.7599945068359),
    ("GBP", "Saint Ouen", 0.5899999737739563),
    ("FRF", "Lille", 357.8399963378906),
    ("GBP", "Leeds", 1356.6899970173836),
    ("FRF", "Morangis", 357.8399963378906),
    ("GBP", "Orly", 0.5899999737739563),
    ("SuperiorCard", "DEM", 1431.3599853515625),
    ("Vista", "CAD", 5369.929964579642),
    ("GBP", "Paris", 0.6399999856948853),
    ("GBP", "Liverpool", 857.1999968588352),
    ("GBP", "Stoke-on-Trent", 1131.7099939212203),
    ("Distinguish", "DEM", 2504.8799743652344),
    ("CAD", "Langford", 2343.4599857851863),
    ("DEM", "Kassel", 536.7599945068359),
    ("GBP", "High Wycombe", 216.83999809622765),
    ("CAD", "Port Hammond", 1711.1399984136224),
    ("DEM", "Duesseldorf", 178.9199981689453),
    ("GBP", "Gloucestershire", 422.28999888151884),
    ("Distinguish", "GBP", 10384.949975416064),
    ("FRF", "Roissy en Brie", 178.9199981689453),
    ("GBP", "West Sussex", 592.1700052022934),
    ("CAD", "Cliffside", 2906.2699892893434),
    ("GBP", "Newcastle upon Tyne", 1448.2899911925197),
    ("GBP", "Runcorn", 1120.4800013303757),
    ("GBP", "W. York", 612.1199932694435),
    ("DEM", "Kiel", 178.9199981689453),
    ("GBP", "Woolston", 833.3199937939644),
    ("Distinguish", "CAD", 6950.059956334531),
    ("DEM", "Frankfurt", 715.6799926757812),
    ("CAD", "Colma", 0.2199999988079071),
    ("DEM", "Essen", 178.9199981689453),
    ("FRF", "Chatou", 178.9199981689453),
    ("GBP", "Cheltenham", 573.0499979257584),
    ("SuperiorCard", "GBP", 8228.39999615401),
    ("CAD", "Haney", 2310.4499812424183),
    ("FRF", "Saint Ouen", 178.9199981689453),
    ("CAD", "Chalk Riber", 0.9200000166893005),
    ("DEM", "Salzgitter", 178.9199981689453),
    ("ColonialVoice", "FRF", 1610.2799835205078),
    ("DEM", "Stuttgart", 357.8399963378906),
    ("FRF", "Saint-Denis", 178.9199981689453),
    ("CAD", "Royal Oak", 2128.459992274642),
    ("FRF", "Les Ulis", 715.6799926757812),
    ("FRF", "Drancy", 178.9199981689453),
    ("GBP", "Esher-Molesey", 911.4700058028102),
    ("SuperiorCard", "CAD", 7388.099954992533),
    ("GBP", "Bury", 903.9400005489588),
    ("GBP", "Watford", 1326.5300009772182),
    ("CAD", "Victoria", 827.3899968340993),
    ("DEM", "Saarbrücken", 178.9199981689453),
    ("GBP", "Lancaster", 685.6899967193604),
    ("FRF", "Pantin", 178.9199981689453),
    ("CAD", "Newton", 1781.909985654056),
    ("GBP", "Oxon", 493.6499986946583),
    ("CAD", "Calgary", 361.3899962902069),
    ("DEM", "Münster", 715.6799926757812),
    ("DEM", "Grevenbroich", 536.7599945068359),
    ("DEM", "Paderborn", 357.8399963378906),
    ("GBP", "York", 3172.9999914616346),
    ("CAD", "Metchosin", 1750.7899813987315),
    ("FRF", "Suresnes", 357.8399963378906),
    ("FRF", "Versailles", 894.5999908447266),
    ("DEM", "Erlangen", 536.7599945068359),
    ("CAD", "Lebanon", 0.8700000047683716),
    ("GBP", "Wokingham", 812.6600027084351),
    ("GBP", "Cambridge", 500.36999743431807),
    ("ColonialVoice", "GBP", 8040.7799860313535),
    ("FRF", "Saint Germain en Laye", 178.9199981689453),
    ("FRF", "Metz", 178.9199981689453),
    ("FRF", "Orleans", 357.8399963378906),
    ("GBP", "Milton Keynes", 1648.2200061008334),
    ("GBP", "Warrington", 2162.8300000429153),
    ("CAD", "N. Vancouver", 1862.4599857926369),
    ("DEM", "Hannover", 178.9199981689453),
    ("Vista", "GBP", 9497.539981640875),
    ("DEM", "Werne", 178.9199981689453),
    ("ColonialVoice", "DEM", 1789.1999816894531),
    ("ColonialVoice", "CAD", 7907.36997512728),
    ("GBP", "Gateshead", 1425.7099913656712),
    ("Vista", "DEM", 1968.1199798583984),
]

private let sankeyItemStyleLinks: [[String: Any]] = sankeyItemStyleLinkRows.map { row in
    ["source": row.0, "target": row.1, "value": row.2] as [String: Any]
}
