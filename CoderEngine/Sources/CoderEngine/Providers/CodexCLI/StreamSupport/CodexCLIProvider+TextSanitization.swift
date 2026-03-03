import Foundation

extension CodexCLIProvider {
    static func scrubTechnicalTextChunk(_ input: String, carry: inout String) -> String {
        var out = carry + input
        carry = ""

        while let start = out.range(of: "[CODERIDE", options: .caseInsensitive) {
            if let end = out[start.lowerBound...].firstIndex(of: "]") {
                out.removeSubrange(start.lowerBound...end)
            } else {
                carry = String(out[start.lowerBound...])
                out.removeSubrange(start.lowerBound..<out.endIndex)
                break
            }
        }

        out = out.replacingOccurrences(
            of: #"(?i)\b(?:markers)?[a-z_]*(?:todo_write|todo_read|do_write|do_read|panel_write|plan_step(?:_update)?|read_batch(?:_started|_completed)?|web_search(?:_started|_completed|_failed)?|web_fetch(?:_started|_completed|_failed)?|instant_grep)\|[^\n\r]*"#,
            with: "",
            options: .regularExpression
        )
        out = out.replacingOccurrences(
            of: #"(?i)\b(?:id|title|status|priority|notes|files|step_id|queryid|query|group_id|count|task|pathscope|matchescount|previewlines)=[^|\n\r\]]+(?:\||\])?"#,
            with: "",
            options: .regularExpression
        )
        out = out.replacingOccurrences(
            of: #"(?im)^Planning\s+(?:bug\s+review|code\s+review)\s+workflow\s*$"#,
            with: "",
            options: .regularExpression
        )
        out = out.replacingOccurrences(
            of: #"(?im)^(\s*(?:Setting|Preparing|Starting|Initializing|Bootstrapping|Planning|Analyzing|Inspecting)\s+(?:initial\s+)?(?:task\s+panel(?:\s+and\s+todo\s+update)?|todo(?:\s+update)?|workflow(?:\s+steps?)?|project\s+analysis|analysis|plan|execution(?:\s+flow)?)(?:\s+and\s+todo\s+update)?\s+)"#,
            with: "",
            options: .regularExpression
        )
        out = out.replacingOccurrences(
            of: #"(?im)^(?:(?:Setting|Preparing|Starting|Initializing|Bootstrapping|Planning|Analyzing)\s+(?:initial\s+)?(?:task\s+panel|todo|workflow|workflow\s+steps?|project\s+analysis|analysis|plan|execution|execution\s+flow|operations?)\b[^\n]*|(?:Setting|Preparing|Starting|Initializing|Bootstrapping|Planning|Analyzing)\s+[^\n]*(?:task\s+panel|todo|workflow|analysis|plan|execution)\b[^\n]*)$"#,
            with: "",
            options: .regularExpression
        )
        out = out.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
        out = out.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        // Importante: non fare trim sui chunk streaming.
        // I delta possono essere solo spazio/newline; se li scartiamo sembra che lo stream si blocchi.
        return out
    }
}
