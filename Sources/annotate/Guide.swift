import Foundation

/// Guided mode: a queue of steps shown one at a time. Each step's first shape
/// carries a "✓ Next" (or "✓ Done" on the last step) button; pressing it shows
/// the next step without any round trip to the agent. ✕ cancels the guide.
///
/// Events: every step click is recorded under "<guide id>.<n>", and the guide
/// as a whole records "completed" or "cancelled" under the guide id itself.
final class Guides {
    static let shared = Guides()

    private struct Guide {
        let id: String
        let steps: [[[String: Any]]]   // shapes per step
        let defaults: [String: Any]
        let titles: [String?]
        var index: Int
    }
    private var guides: [String: Guide] = [:]

    /// Validate every step up front, then show step 1.
    func start(_ req: [String: Any]) throws -> [String: Any] {
        guard let rawSteps = req["steps"] as? [Any], !rawSteps.isEmpty else {
            throw AnnotatorError("guide needs a non-empty \"steps\" array.")
        }
        let gid = (req["id"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "guide"
        var defaults = req
        for k in ["cmd", "steps", "id", "clear_first"] { defaults[k] = nil }
        if defaults["urgency"] == nil && defaults["color"] == nil { defaults["urgency"] = "urgent" }

        var steps: [[[String: Any]]] = []
        var titles: [String?] = []
        for (i, raw) in rawSteps.enumerated() {
            guard let step = raw as? [String: Any] else { throw AnnotatorError("Step \(i + 1) must be an object.") }
            var shapes: [[String: Any]]
            if let list = step["shapes"] as? [[String: Any]] { shapes = list }
            else if step["type"] != nil { shapes = [step] }
            else { throw AnnotatorError("Step \(i + 1) needs \"shapes\" (array) or a \"type\".") }
            guard !shapes.isEmpty else { throw AnnotatorError("Step \(i + 1) has no shapes.") }
            // Dry-run parse so a bad step fails now, not halfway through.
            for sh in shapes { _ = try ShapeParser.parse(sh, defaults: defaults) }
            steps.append(shapes)
            titles.append(step["title"] as? String)
        }

        cancel(gid, record: false)
        if ShapeParser.bool(req, "clear_first") == true { Overlay.shared.remove { _ in true } }
        guides[gid] = Guide(id: gid, steps: steps, defaults: defaults, titles: titles, index: 0)
        try show(gid)
        return ["ok": true, "guide": gid, "steps": steps.count,
                "note": "Step 1 is on screen. Steps advance when the user presses ✓ Next. wait_for_click with id \"\(gid)\" returns when the guide is completed or cancelled."]
    }

    private func stepID(_ gid: String, _ n: Int) -> String { "\(gid).\(n + 1)" }

    private func show(_ gid: String) throws {
        guard let g = guides[gid] else { return }
        let n = g.index, total = g.steps.count
        var shapes = g.steps[n]
        for i in shapes.indices {
            shapes[i]["id"] = stepID(gid, n)
            shapes[i]["task"] = false
            shapes[i]["dismissible"] = false
        }
        // The first shape carries the buttons and the step caption.
        let last = n == total - 1
        shapes[0]["done_text"] = last ? "Done" : "Next (\(n + 2)/\(total))"
        shapes[0]["dismissible"] = true
        shapes[0]["task"] = true
        let title = g.titles[n] ?? (shapes[0]["label"] as? String)
        let prefix = "Step \(n + 1)/\(total)"
        if shapes[0]["type"] as? String == "label" {
            shapes[0]["text"] = "\(prefix): \(shapes[0]["text"] as? String ?? title ?? "")"
        } else {
            shapes[0]["label"] = title.map { "\(prefix): \($0)" } ?? prefix
        }
        var parsed: [Annotation] = []
        for sh in shapes { parsed += try ShapeParser.parse(sh, defaults: g.defaults) }
        Overlay.shared.add(parsed)
    }

    /// Called by the overlay after a user click on any mark.
    func stepClicked(id: String, action: String) {
        guard let dot = id.lastIndex(of: "."), let gid = Optional(String(id[..<dot])),
              var g = guides[gid], id == stepID(gid, g.index) else { return }
        if action != "done" { cancel(gid, record: true); return }
        g.index += 1
        guides[gid] = g
        if g.index >= g.steps.count {
            guides[gid] = nil
            Overlay.shared.recordEvent(id: gid, action: "completed", display: "", label: "All \(g.steps.count) steps done")
            return
        }
        // Let the green "done" flash play, then show the next step.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            do { try self?.show(gid) } catch { self?.cancel(gid, record: true) }
        }
    }

    func cancel(_ gid: String, record: Bool) {
        guard let g = guides.removeValue(forKey: gid) else { return }
        Overlay.shared.remove { $0.id.hasPrefix("\(gid).") }
        if record {
            Overlay.shared.recordEvent(id: gid, action: "cancelled", display: "",
                                       label: "Stopped at step \(g.index + 1) of \(g.steps.count)")
        }
    }

    func cancelAll(record: Bool = false) { for k in Array(guides.keys) { cancel(k, record: record) } }

    var status: [[String: Any]] {
        guides.values.map { ["id": $0.id, "step": $0.index + 1, "of": $0.steps.count] }
    }
}
