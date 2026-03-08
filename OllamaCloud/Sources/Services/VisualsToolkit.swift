import Foundation

/// Built-in visualization tools that generate self-contained dark-theme HTML pages with Plotly.js charts.
/// Models discover these through Ollama's tool calling schema and use their own judgment about when a visualization helps.
enum VisualsToolkit {

    // MARK: - Public API

    static let toolNames: Set<String> = Set(tools.map(\.function.name))

    static func handles(_ toolName: String) -> Bool {
        toolNames.contains(toolName)
    }

    static func execute(toolName: String, arguments: [String: JSONValue]) -> (content: String, isError: Bool) {
        switch toolName {
        case "render_table":            return renderTable(arguments)
        case "render_comparison_table": return renderComparisonTable(arguments)
        case "render_chart":            return renderChart(arguments)
        case "render_multi_chart":      return renderMultiChart(arguments)
        case "render_pie_chart":        return renderPieChart(arguments)
        case "render_heatmap":          return renderHeatmap(arguments)
        case "render_metrics_grid":     return renderMetricsGrid(arguments)
        case "render_timeline":         return renderTimeline(arguments)
        case "render_flowchart":        return renderFlowchart(arguments)
        case "render_tree":             return renderTree(arguments)
        case "render_dashboard":        return renderDashboard(arguments)
        case "render_gauge":            return renderGauge(arguments)
        case "render_gantt":            return renderGantt(arguments)
        case "render_sankey":           return renderSankey(arguments)
        case "render_radar":            return renderRadar(arguments)
        case "render_waterfall":        return renderWaterfall(arguments)
        case "render_funnel":           return renderFunnel(arguments)
        case "render_candlestick":      return renderCandlestick(arguments)
        default:
            return ("Unknown visual tool: \(toolName)", true)
        }
    }

    // MARK: - Tool Definitions

    static let tools: [ChatTool] = [
        makeTool(
            name: "render_table",
            description: "Render an interactive styled data table.",
            required: ["rows"],
            properties: [
                "rows": .init(type: "array", description: "Array of objects. Keys become column headers.", items: .init(type: "object")),
                "title": .init(type: "string", description: "Table title."),
            ]
        ),
        makeTool(
            name: "render_comparison_table",
            description: "Render a comparison table with items scored across criteria.",
            required: ["items", "criteria", "scores"],
            properties: [
                "items": .init(type: "array", description: "List of item names to compare.", items: .init(type: "string")),
                "criteria": .init(type: "array", description: "List of criteria names.", items: .init(type: "string")),
                "scores": .init(type: "object", description: "Object of {item: {criterion: score}} mappings."),
                "title": .init(type: "string", description: "Table title."),
            ]
        ),
        makeTool(
            name: "render_chart",
            description: "Render an interactive bar, line, or scatter chart.",
            required: ["x", "y"],
            properties: [
                "x": .init(type: "array", description: "X-axis values.", items: .init(type: "string")),
                "y": .init(type: "array", description: "Y-axis values.", items: .init(type: "number")),
                "chart_type": .init(type: "string", description: "Chart type.", enum: ["bar", "line", "scatter"]),
                "title": .init(type: "string", description: "Chart title."),
                "x_label": .init(type: "string", description: "X-axis label."),
                "y_label": .init(type: "string", description: "Y-axis label."),
            ]
        ),
        makeTool(
            name: "render_multi_chart",
            description: "Render multiple data series on one chart.",
            required: ["series"],
            properties: [
                "series": .init(type: "array", description: "Array of {x, y, label} objects.", items: .init(type: "object")),
                "chart_type": .init(type: "string", description: "Chart type.", enum: ["bar", "line", "scatter"]),
                "title": .init(type: "string", description: "Chart title."),
            ]
        ),
        makeTool(
            name: "render_pie_chart",
            description: "Render an interactive pie or donut chart.",
            required: ["labels", "values"],
            properties: [
                "labels": .init(type: "array", description: "Slice labels.", items: .init(type: "string")),
                "values": .init(type: "array", description: "Slice values.", items: .init(type: "number")),
                "title": .init(type: "string", description: "Chart title."),
                "donut": .init(type: "boolean", description: "If true, render as donut chart."),
            ]
        ),
        makeTool(
            name: "render_heatmap",
            description: "Render a 2D heatmap.",
            required: ["data"],
            properties: [
                "data": .init(type: "array", description: "2D array of numbers (rows of columns).", items: .init(type: "array")),
                "row_labels": .init(type: "array", description: "Row labels.", items: .init(type: "string")),
                "col_labels": .init(type: "array", description: "Column labels.", items: .init(type: "string")),
                "title": .init(type: "string", description: "Chart title."),
            ]
        ),
        makeTool(
            name: "render_metrics_grid",
            description: "Render a grid of metric cards with optional deltas.",
            required: ["metrics"],
            properties: [
                "metrics": .init(type: "array", description: "Array of {label, value, delta?} objects.", items: .init(type: "object")),
                "title": .init(type: "string", description: "Grid title."),
                "columns": .init(type: "number", description: "Number of columns (default 3)."),
            ]
        ),
        makeTool(
            name: "render_timeline",
            description: "Render a vertical timeline of events.",
            required: ["events"],
            properties: [
                "events": .init(type: "array", description: "Array of {date, title, description?} objects.", items: .init(type: "object")),
                "title": .init(type: "string", description: "Timeline title."),
            ]
        ),
        makeTool(
            name: "render_flowchart",
            description: "Render a horizontal flowchart.",
            required: ["steps"],
            properties: [
                "steps": .init(type: "array", description: "Array of {id, label, next?} objects. next is an array of step ids.", items: .init(type: "object")),
                "title": .init(type: "string", description: "Flowchart title."),
            ]
        ),
        makeTool(
            name: "render_tree",
            description: "Render a collapsible tree diagram.",
            required: ["data"],
            properties: [
                "data": .init(type: "object", description: "Nested object representing the tree structure."),
                "title": .init(type: "string", description: "Tree title."),
                "root_name": .init(type: "string", description: "Label for root node."),
            ]
        ),
        makeTool(
            name: "render_dashboard",
            description: "Render a multi-component dashboard layout.",
            required: ["components"],
            properties: [
                "components": .init(type: "array", description: "Array of component specs, each with a 'type' matching another render tool name and its params.", items: .init(type: "object")),
                "title": .init(type: "string", description: "Dashboard title."),
            ]
        ),
        makeTool(
            name: "render_gauge",
            description: "Render a gauge/dial indicator.",
            required: ["value"],
            properties: [
                "value": .init(type: "number", description: "Current value."),
                "title": .init(type: "string", description: "Gauge title."),
                "min_val": .init(type: "number", description: "Minimum value (default 0)."),
                "max_val": .init(type: "number", description: "Maximum value (default 100)."),
                "unit": .init(type: "string", description: "Unit label (e.g. '%', 'ms')."),
            ]
        ),
        makeTool(
            name: "render_gantt",
            description: "Render a Gantt chart for project timelines.",
            required: ["tasks"],
            properties: [
                "tasks": .init(type: "array", description: "Array of {name, start, end} objects. Dates as YYYY-MM-DD strings.", items: .init(type: "object")),
                "title": .init(type: "string", description: "Chart title."),
            ]
        ),
        makeTool(
            name: "render_sankey",
            description: "Render a Sankey flow diagram.",
            required: ["nodes", "links"],
            properties: [
                "nodes": .init(type: "array", description: "Array of node name strings.", items: .init(type: "string")),
                "links": .init(type: "array", description: "Array of {source, target, value} objects. source/target are node indices.", items: .init(type: "object")),
                "title": .init(type: "string", description: "Chart title."),
            ]
        ),
        makeTool(
            name: "render_radar",
            description: "Render a radar/spider chart.",
            required: ["categories", "series"],
            properties: [
                "categories": .init(type: "array", description: "Axis category labels.", items: .init(type: "string")),
                "series": .init(type: "array", description: "Array of {name, values} objects.", items: .init(type: "object")),
                "title": .init(type: "string", description: "Chart title."),
            ]
        ),
        makeTool(
            name: "render_waterfall",
            description: "Render a waterfall chart showing cumulative effect.",
            required: ["labels", "values"],
            properties: [
                "labels": .init(type: "array", description: "Step labels.", items: .init(type: "string")),
                "values": .init(type: "array", description: "Step values (positive or negative).", items: .init(type: "number")),
                "title": .init(type: "string", description: "Chart title."),
            ]
        ),
        makeTool(
            name: "render_funnel",
            description: "Render a funnel chart showing progressive reduction.",
            required: ["stages", "values"],
            properties: [
                "stages": .init(type: "array", description: "Stage names.", items: .init(type: "string")),
                "values": .init(type: "array", description: "Stage values.", items: .init(type: "number")),
                "title": .init(type: "string", description: "Chart title."),
            ]
        ),
        makeTool(
            name: "render_candlestick",
            description: "Render a candlestick chart for financial data.",
            required: ["dates", "open", "high", "low", "close"],
            properties: [
                "dates": .init(type: "array", description: "Date strings.", items: .init(type: "string")),
                "open": .init(type: "array", description: "Opening prices.", items: .init(type: "number")),
                "high": .init(type: "array", description: "High prices.", items: .init(type: "number")),
                "low": .init(type: "array", description: "Low prices.", items: .init(type: "number")),
                "close": .init(type: "array", description: "Closing prices.", items: .init(type: "number")),
                "title": .init(type: "string", description: "Chart title."),
            ]
        ),
    ]

    // MARK: - Helpers

    private static func makeTool(
        name: String,
        description: String,
        required: [String],
        properties: [String: ChatToolProperty]
    ) -> ChatTool {
        ChatTool(function: ChatToolFunction(
            name: name,
            description: description,
            parameters: ChatToolParameters(required: required, properties: properties)
        ))
    }

    private static func escapeJS(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }

    private static func jsonStringArray(_ values: [JSONValue]) -> String {
        let strings = values.compactMap(\.stringValue).map { "\"\(escapeJS($0))\"" }
        return "[\(strings.joined(separator: ","))]"
    }

    private static func jsonNumberArray(_ values: [JSONValue]) -> String {
        let numbers = values.compactMap(\.numberValue).map { formatNumber($0) }
        return "[\(numbers.joined(separator: ","))]"
    }

    private static func formatNumber(_ n: Double) -> String {
        if n == n.rounded(.towardZero) && abs(n) < 1e15 {
            return String(Int(n))
        }
        return String(n)
    }

    private static func getString(_ args: [String: JSONValue], _ key: String, default defaultValue: String = "") -> String {
        args[key]?.stringValue ?? defaultValue
    }

    private static func getNumber(_ args: [String: JSONValue], _ key: String, default defaultValue: Double? = nil) -> Double? {
        args[key]?.numberValue ?? defaultValue
    }

    private static func getArray(_ args: [String: JSONValue], _ key: String) -> [JSONValue]? {
        args[key]?.arrayValue
    }

    private static func getBool(_ args: [String: JSONValue], _ key: String, default defaultValue: Bool = false) -> Bool {
        args[key]?.boolValue ?? defaultValue
    }

    // MARK: - HTML Template

    private static let plotlyCDN = "https://cdn.plot.ly/plotly-2.35.2.min.js"

    private static func wrapHTML(title: String, body: String, extraHead: String = "") -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            background: #080810;
            color: #e0e0e8;
            font-family: -apple-system, BlinkMacSystemFont, 'SF Pro', system-ui, sans-serif;
            padding: 16px;
        }
        h2 {
            font-size: 15px;
            font-weight: 600;
            color: #f0f0f5;
            margin-bottom: 12px;
            letter-spacing: 0.02em;
        }
        .chart-container {
            background: rgba(255,255,255,0.03);
            border: 1px solid rgba(255,255,255,0.06);
            border-radius: 12px;
            padding: 16px;
            overflow: hidden;
        }
        .plotly-chart { width: 100%; }
        table {
            width: 100%;
            border-collapse: collapse;
            font-size: 12px;
        }
        th {
            background: rgba(255,255,255,0.06);
            color: #a0a0b0;
            font-weight: 600;
            text-align: left;
            padding: 8px 12px;
            font-size: 11px;
            text-transform: uppercase;
            letter-spacing: 0.05em;
        }
        td {
            padding: 8px 12px;
            border-bottom: 1px solid rgba(255,255,255,0.04);
            color: #d0d0d8;
        }
        tr:hover td { background: rgba(255,255,255,0.02); }
        .metric-grid {
            display: grid;
            gap: 12px;
        }
        .metric-card {
            background: rgba(255,255,255,0.03);
            border: 1px solid rgba(255,255,255,0.06);
            border-radius: 10px;
            padding: 14px;
        }
        .metric-label {
            font-size: 11px;
            color: #808090;
            text-transform: uppercase;
            letter-spacing: 0.05em;
            margin-bottom: 4px;
        }
        .metric-value {
            font-size: 22px;
            font-weight: 700;
            color: #f0f0f5;
        }
        .metric-delta {
            font-size: 12px;
            margin-top: 2px;
        }
        .delta-positive { color: #4ade80; }
        .delta-negative { color: #f87171; }
        .timeline-item {
            display: flex;
            gap: 14px;
            padding: 12px 0;
            border-left: 2px solid rgba(255,255,255,0.08);
            padding-left: 16px;
            margin-left: 6px;
            position: relative;
        }
        .timeline-item::before {
            content: '';
            width: 10px;
            height: 10px;
            background: #6366f1;
            border-radius: 50%;
            position: absolute;
            left: -6px;
            top: 16px;
        }
        .timeline-date {
            font-size: 11px;
            color: #6366f1;
            font-weight: 600;
            min-width: 80px;
        }
        .timeline-title { font-weight: 600; font-size: 13px; }
        .timeline-desc { font-size: 12px; color: #a0a0b0; margin-top: 2px; }
        .flow-container {
            display: flex;
            align-items: center;
            gap: 0;
            overflow-x: auto;
            padding: 12px 0;
        }
        .flow-step {
            background: rgba(99,102,241,0.15);
            border: 1px solid rgba(99,102,241,0.3);
            border-radius: 8px;
            padding: 10px 16px;
            font-size: 12px;
            font-weight: 500;
            white-space: nowrap;
            color: #c4b5fd;
        }
        .flow-arrow {
            color: rgba(255,255,255,0.2);
            font-size: 18px;
            padding: 0 6px;
            flex-shrink: 0;
        }
        \(extraHead)
        </style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }

    private static func wrapPlotlyHTML(title: String, plotJS: String, height: Int = 260) -> String {
        let body = """
        \(title.isEmpty ? "" : "<h2>\(escapeJS(title))</h2>")
        <div class="chart-container">
            <div id="chart" class="plotly-chart"></div>
        </div>
        <script src="\(plotlyCDN)"></script>
        <script>
        var layout = {
            paper_bgcolor: 'rgba(0,0,0,0)',
            plot_bgcolor: 'rgba(0,0,0,0)',
            font: { color: '#a0a0b0', family: '-apple-system, system-ui, sans-serif', size: 11 },
            margin: { t: 8, r: 16, b: 36, l: 44 },
            height: \(height),
            xaxis: { gridcolor: 'rgba(255,255,255,0.04)', zerolinecolor: 'rgba(255,255,255,0.06)' },
            yaxis: { gridcolor: 'rgba(255,255,255,0.04)', zerolinecolor: 'rgba(255,255,255,0.06)' },
            showlegend: true,
            legend: { font: { size: 10 }, bgcolor: 'rgba(0,0,0,0)' }
        };
        var config = { responsive: true, displayModeBar: false };
        \(plotJS)
        </script>
        """
        return wrapHTML(title: title, body: body)
    }

    // MARK: - Color Palette

    private static let colors = [
        "#6366f1", "#8b5cf6", "#a78bfa", "#c4b5fd",
        "#818cf8", "#6d28d9", "#7c3aed", "#4f46e5",
        "#4338ca", "#5b21b6", "#9333ea", "#a855f7"
    ]

    private static func color(_ index: Int) -> String {
        colors[index % colors.count]
    }

    // MARK: - Renderers

    private static func renderTable(_ args: [String: JSONValue]) -> (String, Bool) {
        guard let rows = getArray(args, "rows"), !rows.isEmpty else {
            return ("render_table requires a non-empty 'rows' array.", true)
        }
        let title = getString(args, "title")

        // Collect all unique keys in order
        var keyOrder: [String] = []
        var keySet: Set<String> = []
        for row in rows {
            guard let obj = row.objectValue else { continue }
            for key in obj.keys.sorted() {
                if keySet.insert(key).inserted {
                    keyOrder.append(key)
                }
            }
        }

        var html = ""
        if !title.isEmpty { html += "<h2>\(escapeJS(title))</h2>" }
        html += "<div class=\"chart-container\"><table><thead><tr>"
        for key in keyOrder {
            html += "<th>\(escapeJS(key))</th>"
        }
        html += "</tr></thead><tbody>"
        for row in rows {
            guard let obj = row.objectValue else { continue }
            html += "<tr>"
            for key in keyOrder {
                let cell: String
                switch obj[key] {
                case .string(let s): cell = escapeJS(s)
                case .number(let n): cell = formatNumber(n)
                case .bool(let b): cell = b ? "true" : "false"
                case .null: cell = ""
                case .none: cell = ""
                default: cell = "..."
                }
                html += "<td>\(cell)</td>"
            }
            html += "</tr>"
        }
        html += "</tbody></table></div>"
        return (wrapHTML(title: title, body: html), false)
    }

    private static func renderComparisonTable(_ args: [String: JSONValue]) -> (String, Bool) {
        guard let items = getArray(args, "items"),
              let criteria = getArray(args, "criteria"),
              let scoresObj = args["scores"]?.objectValue else {
            return ("render_comparison_table requires 'items', 'criteria', and 'scores'.", true)
        }
        let title = getString(args, "title", default: "Comparison")

        let itemNames = items.compactMap(\.stringValue)
        let criteriaNames = criteria.compactMap(\.stringValue)

        var html = "<h2>\(escapeJS(title))</h2>"
        html += "<div class=\"chart-container\"><table><thead><tr><th>Criteria</th>"
        for item in itemNames {
            html += "<th>\(escapeJS(item))</th>"
        }
        html += "</tr></thead><tbody>"

        for criterion in criteriaNames {
            html += "<tr><td style=\"font-weight:600;color:#a0a0b0\">\(escapeJS(criterion))</td>"
            for item in itemNames {
                let score: String
                if let itemScores = scoresObj[item]?.objectValue,
                   let val = itemScores[criterion] {
                    switch val {
                    case .number(let n): score = formatNumber(n)
                    case .string(let s): score = escapeJS(s)
                    default: score = "-"
                    }
                } else {
                    score = "-"
                }
                html += "<td>\(score)</td>"
            }
            html += "</tr>"
        }
        html += "</tbody></table></div>"
        return (wrapHTML(title: title, body: html), false)
    }

    private static func renderChart(_ args: [String: JSONValue]) -> (String, Bool) {
        guard let xArr = getArray(args, "x"),
              let yArr = getArray(args, "y") else {
            return ("render_chart requires 'x' and 'y' arrays.", true)
        }
        let title = getString(args, "title")
        let chartType = getString(args, "chart_type", default: "bar")
        let xLabel = getString(args, "x_label")
        let yLabel = getString(args, "y_label")

        let xJS = jsonStringArray(xArr)
        let yJS = jsonNumberArray(yArr)

        let plotJS = """
        var trace = { x: \(xJS), y: \(yJS), type: '\(chartType)', marker: { color: '\(colors[0])' } };
        \(!xLabel.isEmpty ? "layout.xaxis.title = '\(escapeJS(xLabel))';" : "")
        \(!yLabel.isEmpty ? "layout.yaxis.title = '\(escapeJS(yLabel))';" : "")
        Plotly.newPlot('chart', [trace], layout, config);
        """
        return (wrapPlotlyHTML(title: title, plotJS: plotJS), false)
    }

    private static func renderMultiChart(_ args: [String: JSONValue]) -> (String, Bool) {
        guard let seriesArr = getArray(args, "series"), !seriesArr.isEmpty else {
            return ("render_multi_chart requires a non-empty 'series' array.", true)
        }
        let title = getString(args, "title")
        let chartType = getString(args, "chart_type", default: "line")

        var traces: [String] = []
        for (i, item) in seriesArr.enumerated() {
            guard let obj = item.objectValue,
                  let x = obj["x"]?.arrayValue,
                  let y = obj["y"]?.arrayValue else { continue }
            let label = obj["label"]?.stringValue ?? "Series \(i + 1)"
            traces.append("""
            { x: \(jsonStringArray(x)), y: \(jsonNumberArray(y)), type: '\(chartType)', name: '\(escapeJS(label))', marker: { color: '\(color(i))' }, line: { color: '\(color(i))' } }
            """)
        }

        let plotJS = "Plotly.newPlot('chart', [\(traces.joined(separator: ","))], layout, config);"
        return (wrapPlotlyHTML(title: title, plotJS: plotJS), false)
    }

    private static func renderPieChart(_ args: [String: JSONValue]) -> (String, Bool) {
        guard let labels = getArray(args, "labels"),
              let values = getArray(args, "values") else {
            return ("render_pie_chart requires 'labels' and 'values' arrays.", true)
        }
        let title = getString(args, "title")
        let donut = getBool(args, "donut")

        let plotJS = """
        var trace = {
            labels: \(jsonStringArray(labels)),
            values: \(jsonNumberArray(values)),
            type: 'pie',
            hole: \(donut ? "0.45" : "0"),
            marker: { colors: [\(colors.prefix(labels.count).map { "'\($0)'" }.joined(separator: ","))] },
            textfont: { color: '#e0e0e8', size: 11 }
        };
        layout.showlegend = true;
        layout.height = 280;
        Plotly.newPlot('chart', [trace], layout, config);
        """
        return (wrapPlotlyHTML(title: title, plotJS: plotJS, height: 280), false)
    }

    private static func renderHeatmap(_ args: [String: JSONValue]) -> (String, Bool) {
        guard let dataArr = getArray(args, "data") else {
            return ("render_heatmap requires a 'data' 2D array.", true)
        }
        let title = getString(args, "title")
        let rowLabels = getArray(args, "row_labels")
        let colLabels = getArray(args, "col_labels")

        let zRows = dataArr.map { row -> String in
            guard let r = row.arrayValue else { return "[]" }
            return jsonNumberArray(r)
        }
        let zJS = "[\(zRows.joined(separator: ","))]"

        var traceExtra = ""
        if let rl = rowLabels { traceExtra += ", y: \(jsonStringArray(rl))" }
        if let cl = colLabels { traceExtra += ", x: \(jsonStringArray(cl))" }

        let plotJS = """
        var trace = {
            z: \(zJS)\(traceExtra),
            type: 'heatmap',
            colorscale: [[0,'#080810'],[0.5,'#6366f1'],[1,'#c4b5fd']],
            showscale: true,
            colorbar: { tickfont: { color: '#a0a0b0' } }
        };
        layout.height = 280;
        Plotly.newPlot('chart', [trace], layout, config);
        """
        return (wrapPlotlyHTML(title: title, plotJS: plotJS, height: 280), false)
    }

    private static func renderMetricsGrid(_ args: [String: JSONValue]) -> (String, Bool) {
        guard let metrics = getArray(args, "metrics"), !metrics.isEmpty else {
            return ("render_metrics_grid requires a non-empty 'metrics' array.", true)
        }
        let title = getString(args, "title")
        let columns = args["columns"]?.intValue ?? 3

        var html = ""
        if !title.isEmpty { html += "<h2>\(escapeJS(title))</h2>" }
        html += "<div class=\"metric-grid\" style=\"grid-template-columns: repeat(\(columns), 1fr);\">"

        for m in metrics {
            guard let obj = m.objectValue else { continue }
            let label = obj["label"]?.stringValue ?? ""
            let value: String
            switch obj["value"] {
            case .string(let s): value = s
            case .number(let n): value = formatNumber(n)
            default: value = "-"
            }

            var deltaHTML = ""
            if let delta = obj["delta"] {
                let deltaStr: String
                let deltaNum: Double?
                switch delta {
                case .number(let n):
                    deltaNum = n
                    deltaStr = (n >= 0 ? "+" : "") + formatNumber(n)
                case .string(let s):
                    deltaNum = Double(s.replacingOccurrences(of: "+", with: ""))
                    deltaStr = s
                default:
                    deltaNum = nil
                    deltaStr = ""
                }
                if !deltaStr.isEmpty {
                    let cls = (deltaNum ?? 0) >= 0 ? "delta-positive" : "delta-negative"
                    deltaHTML = "<div class=\"metric-delta \(cls)\">\(escapeJS(deltaStr))</div>"
                }
            }

            html += """
            <div class="metric-card">
                <div class="metric-label">\(escapeJS(label))</div>
                <div class="metric-value">\(escapeJS(value))</div>
                \(deltaHTML)
            </div>
            """
        }
        html += "</div>"
        return (wrapHTML(title: title, body: html), false)
    }

    private static func renderTimeline(_ args: [String: JSONValue]) -> (String, Bool) {
        guard let events = getArray(args, "events"), !events.isEmpty else {
            return ("render_timeline requires a non-empty 'events' array.", true)
        }
        let title = getString(args, "title")

        var html = ""
        if !title.isEmpty { html += "<h2>\(escapeJS(title))</h2>" }
        html += "<div style=\"padding: 8px 0;\">"

        for event in events {
            guard let obj = event.objectValue else { continue }
            let date = obj["date"]?.stringValue ?? ""
            let eventTitle = obj["title"]?.stringValue ?? ""
            let desc = obj["description"]?.stringValue ?? ""

            html += """
            <div class="timeline-item">
                <div>
                    <div class="timeline-date">\(escapeJS(date))</div>
                    <div class="timeline-title">\(escapeJS(eventTitle))</div>
                    \(!desc.isEmpty ? "<div class=\"timeline-desc\">\(escapeJS(desc))</div>" : "")
                </div>
            </div>
            """
        }
        html += "</div>"
        return (wrapHTML(title: title, body: html), false)
    }

    private static func renderFlowchart(_ args: [String: JSONValue]) -> (String, Bool) {
        guard let steps = getArray(args, "steps"), !steps.isEmpty else {
            return ("render_flowchart requires a non-empty 'steps' array.", true)
        }
        let title = getString(args, "title")

        // Build ordered steps with connections
        var stepList: [(id: String, label: String, next: [String])] = []
        for step in steps {
            guard let obj = step.objectValue else { continue }
            let id = obj["id"]?.stringValue ?? ""
            let label = obj["label"]?.stringValue ?? id
            let next = obj["next"]?.arrayValue?.compactMap(\.stringValue) ?? []
            stepList.append((id: id, label: label, next: next))
        }

        var html = ""
        if !title.isEmpty { html += "<h2>\(escapeJS(title))</h2>" }
        html += "<div class=\"chart-container\"><div class=\"flow-container\">"

        for (i, step) in stepList.enumerated() {
            if i > 0 {
                html += "<div class=\"flow-arrow\">\u{2192}</div>"
            }
            html += "<div class=\"flow-step\">\(escapeJS(step.label))</div>"
        }

        html += "</div></div>"
        return (wrapHTML(title: title, body: html), false)
    }

    private static func renderTree(_ args: [String: JSONValue]) -> (String, Bool) {
        guard let data = args["data"]?.objectValue else {
            return ("render_tree requires a 'data' object.", true)
        }
        let title = getString(args, "title")
        let rootName = getString(args, "root_name", default: "Root")

        func buildTreeHTML(_ obj: [String: JSONValue], depth: Int) -> String {
            var html = "<ul style=\"list-style:none;padding-left:\(depth > 0 ? 18 : 0)px;margin:4px 0;\">"
            for (key, value) in obj.sorted(by: { $0.key < $1.key }) {
                let nodeColor = color(depth)
                html += "<li style=\"padding:3px 0;\">"
                html += "<span style=\"color:\(nodeColor);font-weight:500;font-size:12px;\">\(escapeJS(key))</span>"
                if let childObj = value.objectValue, !childObj.isEmpty {
                    html += buildTreeHTML(childObj, depth: depth + 1)
                } else {
                    let valStr: String
                    switch value {
                    case .string(let s): valStr = s
                    case .number(let n): valStr = formatNumber(n)
                    case .bool(let b): valStr = b ? "true" : "false"
                    default: valStr = ""
                    }
                    if !valStr.isEmpty {
                        html += " <span style=\"color:#808090;font-size:11px;\">: \(escapeJS(valStr))</span>"
                    }
                }
                html += "</li>"
            }
            html += "</ul>"
            return html
        }

        var html = ""
        if !title.isEmpty { html += "<h2>\(escapeJS(title))</h2>" }
        html += "<div class=\"chart-container\">"
        html += "<div style=\"font-weight:600;font-size:13px;color:#c4b5fd;margin-bottom:8px;\">\(escapeJS(rootName))</div>"
        html += buildTreeHTML(data, depth: 0)
        html += "</div>"
        return (wrapHTML(title: title, body: html), false)
    }

    private static func renderDashboard(_ args: [String: JSONValue]) -> (String, Bool) {
        guard let components = getArray(args, "components"), !components.isEmpty else {
            return ("render_dashboard requires a non-empty 'components' array.", true)
        }
        let title = getString(args, "title")

        var htmlParts: [String] = []
        if !title.isEmpty { htmlParts.append("<h2>\(escapeJS(title))</h2>") }
        htmlParts.append("<div style=\"display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:16px;\">")

        for component in components {
            guard let obj = component.objectValue,
                  let compType = obj["type"]?.stringValue else { continue }

            // Build sub-arguments from the component object (everything except "type")
            var subArgs: [String: JSONValue] = [:]
            for (k, v) in obj where k != "type" {
                subArgs[k] = v
            }

            let toolName = compType.hasPrefix("render_") ? compType : "render_\(compType)"
            if handles(toolName) {
                let (subHTML, isError) = execute(toolName: toolName, arguments: subArgs)
                if !isError {
                    // Extract body content between <body> and </body>
                    if let bodyStart = subHTML.range(of: "<body>"),
                       let bodyEnd = subHTML.range(of: "</body>") {
                        let bodyContent = String(subHTML[bodyStart.upperBound..<bodyEnd.lowerBound])
                        htmlParts.append("<div>\(bodyContent)</div>")
                    } else {
                        htmlParts.append("<div>\(subHTML)</div>")
                    }
                }
            }
        }

        htmlParts.append("</div>")
        return (wrapHTML(title: title, body: htmlParts.joined(separator: "\n")), false)
    }

    private static func renderGauge(_ args: [String: JSONValue]) -> (String, Bool) {
        guard let value = getNumber(args, "value") else {
            return ("render_gauge requires a 'value' number.", true)
        }
        let title = getString(args, "title")
        let minVal = getNumber(args, "min_val", default: 0) ?? 0
        let maxVal = getNumber(args, "max_val", default: 100) ?? 100
        let unit = getString(args, "unit")

        let suffix = unit.isEmpty ? "" : ", number: { suffix: ' \(escapeJS(unit))' }"

        let plotJS = """
        var trace = {
            type: 'indicator',
            mode: 'gauge+number',
            value: \(formatNumber(value)),
            gauge: {
                axis: { range: [\(formatNumber(minVal)), \(formatNumber(maxVal))], tickcolor: '#a0a0b0' },
                bar: { color: '\(colors[0])' },
                bgcolor: 'rgba(255,255,255,0.03)',
                bordercolor: 'rgba(255,255,255,0.06)',
                steps: [
                    { range: [\(formatNumber(minVal)), \(formatNumber(minVal + (maxVal - minVal) * 0.33))], color: 'rgba(99,102,241,0.1)' },
                    { range: [\(formatNumber(minVal + (maxVal - minVal) * 0.33)), \(formatNumber(minVal + (maxVal - minVal) * 0.66))], color: 'rgba(99,102,241,0.15)' },
                    { range: [\(formatNumber(minVal + (maxVal - minVal) * 0.66)), \(formatNumber(maxVal))], color: 'rgba(99,102,241,0.2)' }
                ]
            }\(suffix)
        };
        layout.height = 200;
        layout.margin = { t: 8, r: 16, b: 8, l: 16 };
        Plotly.newPlot('chart', [trace], layout, config);
        """
        return (wrapPlotlyHTML(title: title, plotJS: plotJS, height: 200), false)
    }

    private static func renderGantt(_ args: [String: JSONValue]) -> (String, Bool) {
        guard let tasks = getArray(args, "tasks"), !tasks.isEmpty else {
            return ("render_gantt requires a non-empty 'tasks' array.", true)
        }
        let title = getString(args, "title")

        var traces: [String] = []
        for (i, task) in tasks.reversed().enumerated() {
            guard let obj = task.objectValue else { continue }
            let name = obj["name"]?.stringValue ?? "Task \(i + 1)"
            let start = obj["start"]?.stringValue ?? ""
            let end = obj["end"]?.stringValue ?? ""

            traces.append("""
            {
                x: ['\(escapeJS(start))', '\(escapeJS(end))'],
                y: ['\(escapeJS(name))', '\(escapeJS(name))'],
                mode: 'lines',
                line: { color: '\(color(i))', width: 16 },
                name: '\(escapeJS(name))',
                showlegend: false,
                hoverinfo: 'text',
                text: ['\(escapeJS(name)): \(escapeJS(start))', '\(escapeJS(name)): \(escapeJS(end))']
            }
            """)
        }

        let plotJS = """
        layout.xaxis.type = 'date';
        layout.height = \(max(180, tasks.count * 36 + 60));
        layout.showlegend = false;
        layout.yaxis.automargin = true;
        Plotly.newPlot('chart', [\(traces.joined(separator: ","))], layout, config);
        """
        return (wrapPlotlyHTML(title: title, plotJS: plotJS, height: max(180, tasks.count * 36 + 60)), false)
    }

    private static func renderSankey(_ args: [String: JSONValue]) -> (String, Bool) {
        guard let nodes = getArray(args, "nodes"),
              let links = getArray(args, "links") else {
            return ("render_sankey requires 'nodes' and 'links' arrays.", true)
        }
        let title = getString(args, "title")

        let nodeLabels = jsonStringArray(nodes)
        let nodeColors = nodes.indices.map { "'\(color($0))'" }.joined(separator: ",")

        var sources: [String] = []
        var targets: [String] = []
        var values: [String] = []
        for link in links {
            guard let obj = link.objectValue else { continue }
            if let s = obj["source"]?.numberValue { sources.append(formatNumber(s)) }
            if let t = obj["target"]?.numberValue { targets.append(formatNumber(t)) }
            if let v = obj["value"]?.numberValue { values.append(formatNumber(v)) }
        }

        let plotJS = """
        var trace = {
            type: 'sankey',
            node: {
                label: \(nodeLabels),
                color: [\(nodeColors)],
                pad: 12,
                thickness: 16
            },
            link: {
                source: [\(sources.joined(separator: ","))],
                target: [\(targets.joined(separator: ","))],
                value: [\(values.joined(separator: ","))],
                color: 'rgba(99,102,241,0.2)'
            }
        };
        layout.height = 300;
        Plotly.newPlot('chart', [trace], layout, config);
        """
        return (wrapPlotlyHTML(title: title, plotJS: plotJS, height: 300), false)
    }

    private static func renderRadar(_ args: [String: JSONValue]) -> (String, Bool) {
        guard let categories = getArray(args, "categories"),
              let seriesArr = getArray(args, "series"), !seriesArr.isEmpty else {
            return ("render_radar requires 'categories' and 'series' arrays.", true)
        }
        let title = getString(args, "title")

        let catLabels = categories.compactMap(\.stringValue)
        var traces: [String] = []
        for (i, s) in seriesArr.enumerated() {
            guard let obj = s.objectValue,
                  let vals = obj["values"]?.arrayValue else { continue }
            let name = obj["name"]?.stringValue ?? "Series \(i + 1)"
            let rValues = vals.compactMap(\.numberValue)
            // Close the polygon
            var closedR = rValues
            var closedTheta = catLabels
            if let first = rValues.first { closedR.append(first) }
            if let first = catLabels.first { closedTheta.append(first) }

            traces.append("""
            {
                type: 'scatterpolar',
                r: [\(closedR.map { formatNumber($0) }.joined(separator: ","))],
                theta: [\(closedTheta.map { "'\(escapeJS($0))'" }.joined(separator: ","))],
                fill: 'toself',
                fillcolor: '\(color(i))22',
                line: { color: '\(color(i))' },
                name: '\(escapeJS(name))'
            }
            """)
        }

        let plotJS = """
        layout.polar = {
            bgcolor: 'rgba(0,0,0,0)',
            radialaxis: { gridcolor: 'rgba(255,255,255,0.06)', linecolor: 'rgba(255,255,255,0.06)' },
            angularaxis: { gridcolor: 'rgba(255,255,255,0.06)', linecolor: 'rgba(255,255,255,0.06)' }
        };
        layout.height = 300;
        Plotly.newPlot('chart', [\(traces.joined(separator: ","))], layout, config);
        """
        return (wrapPlotlyHTML(title: title, plotJS: plotJS, height: 300), false)
    }

    private static func renderWaterfall(_ args: [String: JSONValue]) -> (String, Bool) {
        guard let labels = getArray(args, "labels"),
              let values = getArray(args, "values") else {
            return ("render_waterfall requires 'labels' and 'values' arrays.", true)
        }
        let title = getString(args, "title")

        let labelStrs = labels.compactMap(\.stringValue)
        let valueNums = values.compactMap(\.numberValue)

        var measures: [String] = []
        for (i, _) in valueNums.enumerated() {
            if i == valueNums.count - 1 {
                measures.append("'total'")
            } else {
                measures.append("'relative'")
            }
        }

        let plotJS = """
        var trace = {
            type: 'waterfall',
            x: [\(labelStrs.map { "'\(escapeJS($0))'" }.joined(separator: ","))],
            y: [\(valueNums.map { formatNumber($0) }.joined(separator: ","))],
            measure: [\(measures.joined(separator: ","))],
            increasing: { marker: { color: '#4ade80' } },
            decreasing: { marker: { color: '#f87171' } },
            totals: { marker: { color: '\(colors[0])' } },
            connector: { line: { color: 'rgba(255,255,255,0.1)', width: 1 } },
            textfont: { color: '#e0e0e8' }
        };
        Plotly.newPlot('chart', [trace], layout, config);
        """
        return (wrapPlotlyHTML(title: title, plotJS: plotJS), false)
    }

    private static func renderFunnel(_ args: [String: JSONValue]) -> (String, Bool) {
        guard let stages = getArray(args, "stages"),
              let values = getArray(args, "values") else {
            return ("render_funnel requires 'stages' and 'values' arrays.", true)
        }
        let title = getString(args, "title")

        let plotJS = """
        var trace = {
            type: 'funnel',
            y: \(jsonStringArray(stages)),
            x: \(jsonNumberArray(values)),
            marker: {
                color: [\(stages.indices.map { "'\(color($0))'" }.joined(separator: ","))]
            },
            textfont: { color: '#e0e0e8' },
            textposition: 'inside'
        };
        layout.funnelmode = 'stack';
        layout.height = \(max(200, stages.count * 40 + 60));
        Plotly.newPlot('chart', [trace], layout, config);
        """
        return (wrapPlotlyHTML(title: title, plotJS: plotJS, height: max(200, stages.count * 40 + 60)), false)
    }

    private static func renderCandlestick(_ args: [String: JSONValue]) -> (String, Bool) {
        guard let dates = getArray(args, "dates"),
              let open = getArray(args, "open"),
              let high = getArray(args, "high"),
              let low = getArray(args, "low"),
              let close = getArray(args, "close") else {
            return ("render_candlestick requires 'dates', 'open', 'high', 'low', and 'close' arrays.", true)
        }
        let title = getString(args, "title")

        let plotJS = """
        var trace = {
            type: 'candlestick',
            x: \(jsonStringArray(dates)),
            open: \(jsonNumberArray(open)),
            high: \(jsonNumberArray(high)),
            low: \(jsonNumberArray(low)),
            close: \(jsonNumberArray(close)),
            increasing: { line: { color: '#4ade80' }, fillcolor: '#4ade8066' },
            decreasing: { line: { color: '#f87171' }, fillcolor: '#f8717166' }
        };
        layout.xaxis.type = 'date';
        layout.xaxis.rangeslider = { visible: false };
        layout.height = 300;
        Plotly.newPlot('chart', [trace], layout, config);
        """
        return (wrapPlotlyHTML(title: title, plotJS: plotJS, height: 300), false)
    }
}
