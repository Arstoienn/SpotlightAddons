import Foundation

// The registry is generated from the functions which actually execute, so completion and runtime
// cannot drift. A persistent local worker imports scientific libraries once, off the UI thread.
struct AstronomyMethod: Decodable {
    struct Parameter: Decodable {
        let name: String; let kind: String; let required: Bool; let `default`: String?; let choices: [String]?
        var completion: Completion.Parameter { Completion.Parameter(name: name, kind: kind, choices: choices ?? []) }
    }
    let name: String
    let category: String
    let description: String
    let parameters: [Parameter]
    let returns: String
    let visualization: String
    let model: String
    let formula: String
    let source: String
    let aliases: [String]
    let example: String
    let priority: String
    var completion: Completion.Function {
        if name == "escape_velocity" || name == "surface_gravity" {
            return Completion.Function(name: name, forms: [[Completion.Parameter(name:"body",kind:"body")],
                [Completion.Parameter(name:"M",kind:"mass"),Completion.Parameter(name:"r",kind:"radius")]],
                summary:category + " · " + description,aliases:aliases)
        }
        if name == "absolute_magnitude" {
            return Completion.Function(name:name,forms:[[Completion.Parameter(name:"body",kind:"seen")],
                [Completion.Parameter(name:"apparent_mag",kind:"apparent"),Completion.Parameter(name:"distance",kind:"distance")],
                parameters.map(\.completion)],summary:category + " · " + description,aliases:aliases)
        }
        if name == "luminosity" {
            return Completion.Function(name:name,forms:[[Completion.Parameter(name:"body",kind:"star")],
                [Completion.Parameter(name:"radius",kind:"radius"),Completion.Parameter(name:"temperature",kind:"temperature")]],
                summary:category + " · " + description,aliases:aliases)
        }
        if name == "orbital_period" {
            return Completion.Function(name:name,forms:[[Completion.Parameter(name:"body",kind:"satellite")],
                [Completion.Parameter(name:"a",kind:"orbit"),Completion.Parameter(name:"M",kind:"central")]],
                summary:category + " · " + description,aliases:aliases)
        }
        let required = parameters.filter(\.required).map(\.completion)
        let all = parameters.map(\.completion)
        return Completion.Function(name: name, forms: required == all ? [required] : [required, all],
                                   summary: category + " · " + description, aliases: aliases)
    }
}

struct AstronomySeries {
    var x: [Double]
    var y: [Double]
    var xLabel: String
    var yLabel: String
    var label: String
    var kind: String
    init?(_ raw: [String: Any]) {
        guard let x = raw["x"] as? [Double], let y = raw["y"] as? [Double], x.count == y.count, !x.isEmpty,
              x.allSatisfy(\.isFinite), y.allSatisfy(\.isFinite) else { return nil }
        self.x = x; self.y = y
        xLabel = raw["xLabel"] as? String ?? "x"; yLabel = raw["yLabel"] as? String ?? "y"
        label = raw["label"] as? String ?? "Model"; kind = raw["kind"] as? String ?? "curve"
    }
}

struct AstronomyPicture {
    var title: String
    var data: [String: Any]
    var series: AstronomySeries?
    var result: Any
}

struct AstronomyWorking {
    struct Row {
        let name: String
        let value: String
        let detail: String?

        init?(_ raw: [String: String]) {
            guard let name = raw["name"], let value = raw["value"] else { return nil }
            self.name = name
            self.value = value
            detail = raw["detail"]
        }
    }

    // A value the method looked up as it worked, in SI: the mass of the Earth, a radius given.
    struct Used {
        let kind: String     // mass, radius, length, temperature, luminosity, time, angle, speed, mu, a, number
        let label: String    // Mass of earth
        let value: Double
        let unit: String
    }

    let inputs: [Row]
    let formula: String
    let values: [Used]
    let si: Double?          // the answer in SI units, which the formula gives from the values in SI
    let siUnit: String
    let constants: [Row]
    let intermediates: [Row]
    let results: [Row]
    let model: String
    let source: String
    let notes: [String]

    init?(_ raw: [String: Any], notes: [String]) {
        guard let working = raw["working"] as? [String: Any], let formula = working["formula"] as? String else { return nil }
        func rows(_ key: String) -> [Row] {
            (working[key] as? [[String: String]] ?? []).compactMap(Row.init)
        }
        inputs = rows("inputs")
        self.formula = formula
        values = (working["values"] as? [[String: Any]] ?? []).compactMap { v in
            guard let kind = v["kind"] as? String, let label = v["label"] as? String, let value = v["value"] as? Double else { return nil }
            return Used(kind: kind, label: label, value: value, unit: v["unit"] as? String ?? "")
        }
        si = working["si"] as? Double
        siUnit = working["si_unit"] as? String ?? ""
        constants = rows("constants")
        intermediates = rows("intermediates")
        results = rows("results")
        model = raw["model"] as? String ?? ""
        source = raw["source"] as? String ?? ""
        self.notes = notes
    }
}

final class AstronomyEngine: @unchecked Sendable {
    static let shared = AstronomyEngine()
    static let changed = Notification.Name("AstronomyEngineChanged")
    static let resource: URL = {
        let bundle = Bundle.main.resourceURL?.appendingPathComponent("Astronomy")
        if let bundle, FileManager.default.fileExists(atPath: bundle.appendingPathComponent("methods.json").path) { return bundle }
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/Astronomy")
    }()
    static let methods: [AstronomyMethod] = {
        guard let data = try? Data(contentsOf: resource.appendingPathComponent("methods.json")),
              let methods = try? JSONDecoder().decode([AstronomyMethod].self, from: data) else { return [] }
        return methods
    }()
    private let queue = DispatchQueue(label: "Astronomy.worker", qos: .userInitiated)
    private let lock = NSLock()
    private var cache: [String: Astronomy] = [:]
    private var pending = Set<String>()
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var buffer = Data()
    // The worker holds about 100 MB once its libraries are loaded, and nothing while it is not there.
    // Five minutes after the last calculation it is let go; the next @ starts it again in a second or so.
    static var idleLimit: TimeInterval = 300
    private var idle: DispatchWorkItem?
    var isRunning: Bool { queue.sync { process?.isRunning == true } }
    // Tests use the same public parser and protocol synchronously; GUI work always runs on queue.
    static var synchronous = false

    func answer(_ text: String) -> Astronomy {
        lock.lock()
        if let result = cache[text] { lock.unlock(); return result }
        if pending.contains(text) { lock.unlock(); return waiting }
        pending.insert(text); lock.unlock()
        if Self.synchronous {
            let result = queue.sync { compute(text) }
            save(result, for: text); return result
        }
        queue.async { [self] in
            let result = compute(text)
            save(result, for: text)
            DispatchQueue.main.async { NotificationCenter.default.post(name: Self.changed, object: text) }
        }
        return waiting
    }
    private var waiting: Astronomy { Astronomy(solution: Solution(exact: "Calculating astronomy…", approx: "Local scientific engine")) }
    private func save(_ result: Astronomy, for text: String) {
        lock.lock(); defer { lock.unlock() }
        if cache.count > 128 { cache.removeAll(keepingCapacity: true) }
        pending.remove(text); cache[text] = result
    }
    private func start() throws {
        if process?.isRunning == true { return }
        let root = Self.resource.deletingLastPathComponent().deletingLastPathComponent()
        let paths: [String] = ([ProcessInfo.processInfo.environment["ASTRONOMY_PYTHON"],
                     Self.resource.appendingPathComponent("runtime/bin/python3").path,
                     root.appendingPathComponent("build/astronomy-runtime/bin/python3").path] as [String?]).compactMap { $0 }
        guard let python = paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw Problem(message: "Astronomy runtime missing", detail: "Run ./setup-astronomy.sh in the checkout, then rebuild the app.")
        }
        let p = Process(); p.executableURL = URL(fileURLWithPath: python)
        p.arguments = ["-I", "-B", "-u", Self.resource.appendingPathComponent("engine.py").path]
        let stdin = Pipe(), stdout = Pipe()
        p.standardInput = stdin; p.standardOutput = stdout
        p.standardError = FileHandle.nullDevice
        try p.run()
        process = p; input = stdin.fileHandleForWriting; output = stdout.fileHandleForReading; buffer = Data()
    }
    // On the queue, as every calculation is, so a calculation and the closing never meet.
    private func closeWhenIdle() {
        idle?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.stop() }
        idle = item
        queue.asyncAfter(deadline: .now() + Self.idleLimit, execute: item)
    }
    private func compute(_ text: String) -> Astronomy {
        idle?.cancel()
        defer { closeWhenIdle() }
        do {
            try start()
            guard let input, let output else { throw Problem(message: "Astronomy worker unavailable", detail: "Restart the app.") }
            let child = process
            let timeout = DispatchWorkItem { if child?.isRunning == true { child?.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + 60, execute: timeout)
            defer { timeout.cancel() }
            var request = try JSONSerialization.data(withJSONObject: ["text": text]); request.append(0x0a)
            try input.write(contentsOf: request)
            while !buffer.contains(0x0a) {
                let chunk = output.availableData
                guard !chunk.isEmpty else { throw Problem(message: "Astronomy worker stopped", detail: "Calculation exceeded 60 seconds or the runtime failed. Try a smaller data set.") }
                buffer.append(chunk)
                guard buffer.count < 64 * 1024 * 1024 else { throw Problem(message: "Astronomy result too large", detail: "Reduce the number of samples.") }
            }
            let end = buffer.firstIndex(of: 0x0a)!
            let line = buffer[..<end]; buffer.removeSubrange(...end)
            guard let raw = try JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                throw Problem(message: "Invalid astronomy response", detail: "Rebuild the scientific runtime.")
            }
            if raw["ok"] as? Bool != true {
                return failure(raw["error"] as? String ?? "Calculation failed", "Check the method signature, units and physical domain.", query: text)
            }
            return decode(raw, query: text)
        } catch let error as Problem {
            stop(); return failure(error.message, error.detail, query: text)
        } catch {
            stop(); return failure("Astronomy runtime error", error.localizedDescription, query: text)
        }
    }
    private func stop() { process?.terminate(); process = nil; input = nil; output = nil; buffer = Data() }
    private func failure(_ title: String, _ note: String, query: String) -> Astronomy {
        let details = Details(name: "Astronomy", equation: .text(query), steps: [], solutions: [], note: note, f: { _ in .nan }, roots: [])
        return Astronomy(solution: Solution(exact: title, approx: note), details: details)
    }
    private func decode(_ raw: [String: Any], query: String) -> Astronomy {
        let name = raw["method"] as? String ?? "Astronomy"
        let summary = raw["summary"] as? String ?? ""
        let model = raw["model"] as? String ?? ""
        let source = raw["source"] as? String ?? ""
        let notes = raw["notes"] as? [String] ?? []
        let value = raw["value"] as? Double
        var steps = (raw["steps"] as? [[String: String]] ?? []).map { Step(label: $0["label"] ?? "Working", math: .text($0["text"] ?? "")) }
        steps.append(Step(label: "Model and source", math: nil, note: model + "\n" + source))
        let result = raw["result"] ?? NSNull()
        let context = notes.isEmpty ? ["Input values treated as exact; catalogue/model uncertainty is not included."] : notes
        var d = Details(name: name, equation: .text(query), steps: steps, solutions: [.text(summary)],
                        note: context.joined(separator: "\n"), f: { _ in .nan }, roots: [])
        d.astronomyWorking = AstronomyWorking(raw, notes: context)
        let series = (raw["plot"] as? [String: Any]).flatMap(AstronomySeries.init)
        let data = raw["diagram"] as? [String: Any] ?? [:]
        if data["kind"] as? String == "hr", let t = data["temperature"] as? Double, let l = data["luminosity"] as? Double {
            d.diagram = .hr(HRPicture(stars: [HRPicture.Star(name: data["name"] as? String ?? "Star", temperature: t, luminosity: l, marked: true)]))
        } else {
            let titles = ["orbit": "Orbital diagram", "transfer": "Orbital transfer", "sky": "Horizon sky map", "black_hole": "Black hole structure",
                          "spectrum": "Spectral shift", "comparison": "Body comparison", "potential": "Effective gravitational potential",
                          "habitable": "Habitable zone", "image": "Image data", "transit_controls": "Interactive transit model"]
            let method = Self.methods.first { $0.name == name }
            let key = data["kind"] as? String ?? method?.visualization ?? "panel"
            d.diagram = .scientific(AstronomyPicture(title: titles[key] ?? name.replacingOccurrences(of: "_", with: " ").capitalized,
                                                    data: data, series: series, result: result))
        }
        let copy: String
        if let value { copy = String(format: "%.12g", value) }
        else if JSONSerialization.isValidJSONObject(result), let json = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted,.sortedKeys]), let s = String(data: json, encoding: .utf8) { copy = s }
        else { copy = summary }
        d.whole = copy
        return Astronomy(solution: Solution(exact: summary, approx: AstronomyWorkingText.name(name) + " · " + AstronomyWorkingText.sentence(model)),
                         details: d, copy: copy, value: value)
    }
}
