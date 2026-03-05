import Foundation

struct ValidationIssue: Identifiable, Equatable {
    enum Severity: String, Equatable {
        case error
        case warning
    }

    let id = UUID()
    let field: String
    let message: String
    let severity: Severity
}

struct ReasoningScaffoldDraft: Equatable {
    var name: String
    var summary: String
    var role: String
    var perspective: String
    var tone: String
    var reasoningSteps: [String]
    var outputFormat: String
    var mustInclude: [String]
    var neverInclude: [String]
    var disclaimers: [String]
    var prohibitedActions: [String]

    static let empty = ReasoningScaffoldDraft(
        name: "",
        summary: "",
        role: "",
        perspective: "",
        tone: "",
        reasoningSteps: [],
        outputFormat: "",
        mustInclude: [],
        neverInclude: [],
        disclaimers: [],
        prohibitedActions: []
    )
}

enum ReasoningScaffoldTemplate: String, CaseIterable, Identifiable {
    case analyst = "Analyst"
    case tutor = "Tutor"
    case technicalDebugger = "Technical Debugger"
    case decisionCoach = "Decision Coach"
    case creativeStrategist = "Creative Strategist"

    var id: String { rawValue }

    var summary: String {
        switch self {
        case .analyst:
            return "Structured analysis for data-heavy questions."
        case .tutor:
            return "Stepwise teaching with checks for understanding."
        case .technicalDebugger:
            return "Root-cause debugging with actionable fixes."
        case .decisionCoach:
            return "Tradeoff-driven recommendations and decision framing."
        case .creativeStrategist:
            return "Divergent ideas, synthesis, then clear execution direction."
        }
    }

    var draft: ReasoningScaffoldDraft {
        switch self {
        case .analyst:
            return ReasoningScaffoldDraft(
                name: "Analyst",
                summary: "Analyze inputs with objective structure and prioritized findings.",
                role: "Senior analyst",
                perspective: "Evidence-first, concise, and explicit about uncertainty.",
                tone: "Clear and direct",
                reasoningSteps: [
                    "Identify the core question and constraints",
                    "Extract the most relevant facts from provided context",
                    "Assess tradeoffs and rank options by impact",
                    "Deliver a concise recommendation with rationale"
                ],
                outputFormat: "bullet_points",
                mustInclude: ["Top recommendation", "2-3 supporting reasons"],
                neverInclude: ["Unfounded certainty"],
                disclaimers: [],
                prohibitedActions: []
            )
        case .tutor:
            return ReasoningScaffoldDraft(
                name: "Tutor",
                summary: "Explain concepts progressively and verify understanding.",
                role: "Patient subject tutor",
                perspective: "Concept-first, examples second, reinforce intuition.",
                tone: "Supportive and clear",
                reasoningSteps: [
                    "Assess learner intent and current understanding",
                    "Explain key concept in plain language",
                    "Give one concrete example",
                    "Provide a quick check question or recap"
                ],
                outputFormat: "structured_narrative",
                mustInclude: ["Simple explanation", "Example"],
                neverInclude: ["Shaming language"],
                disclaimers: [],
                prohibitedActions: []
            )
        case .technicalDebugger:
            return ReasoningScaffoldDraft(
                name: "Technical Debugger",
                summary: "Diagnose technical issues and produce minimal-risk fixes.",
                role: "Senior software debugger",
                perspective: "Repro-first, isolate variables, fix smallest surface area.",
                tone: "Precise and practical",
                reasoningSteps: [
                    "Restate failure symptom and expected behavior",
                    "Generate likely root-cause hypotheses",
                    "Propose fastest verification steps",
                    "Recommend fix with validation checklist"
                ],
                outputFormat: "bullet_points",
                mustInclude: ["Likely root cause", "Verification steps", "Proposed fix"],
                neverInclude: ["Speculative claims without checks"],
                disclaimers: [],
                prohibitedActions: []
            )
        case .decisionCoach:
            return ReasoningScaffoldDraft(
                name: "Decision Coach",
                summary: "Help choose between options with transparent tradeoffs.",
                role: "Decision strategy coach",
                perspective: "Clarify criteria, compare options, commit with confidence level.",
                tone: "Grounded and pragmatic",
                reasoningSteps: [
                    "Clarify objective and decision criteria",
                    "Compare options against criteria",
                    "Highlight key risks and mitigations",
                    "Recommend a choice and next action"
                ],
                outputFormat: "structured_narrative",
                mustInclude: ["Decision criteria", "Recommendation"],
                neverInclude: ["False certainty"],
                disclaimers: [],
                prohibitedActions: []
            )
        case .creativeStrategist:
            return ReasoningScaffoldDraft(
                name: "Creative Strategist",
                summary: "Generate high-quality ideas, cluster, and recommend a direction.",
                role: "Creative strategy lead",
                perspective: "Diverge widely, converge intentionally.",
                tone: "Inventive but concrete",
                reasoningSteps: [
                    "Generate multiple distinct directions",
                    "Cluster and evaluate by impact and effort",
                    "Select strongest direction and justify",
                    "Propose immediate next execution steps"
                ],
                outputFormat: "bullet_points",
                mustInclude: ["Top concepts", "Chosen direction", "Next actions"],
                neverInclude: ["Generic filler"],
                disclaimers: [],
                prohibitedActions: []
            )
        }
    }
}

enum ReasoningScaffoldCompiler {
    static func draft(from scaffold: ReasoningScaffold) -> ReasoningScaffoldDraft {
        ReasoningScaffoldDraft(
            name: scaffold.name,
            summary: scaffold.summary,
            role: scaffold.role,
            perspective: scaffold.perspective,
            tone: scaffold.tone,
            reasoningSteps: scaffold.reasoningSteps,
            outputFormat: scaffold.outputFormat,
            mustInclude: scaffold.mustInclude,
            neverInclude: scaffold.neverInclude,
            disclaimers: scaffold.disclaimers,
            prohibitedActions: scaffold.prohibitedActions
        )
    }

    static func compile(_ scaffold: ReasoningScaffold) -> String {
        compile(draft: draft(from: scaffold), title: scaffold.name)
    }

    static func compile(draft: ReasoningScaffoldDraft, title: String? = nil) -> String {
        let normalized = normalizeDraft(draft)
        var sections: [String] = []

        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append("## Reasoning Scaffold\n\(title)")
        } else if !normalized.name.isEmpty {
            sections.append("## Reasoning Scaffold\n\(normalized.name)")
        } else {
            sections.append("## Reasoning Scaffold")
        }

        if !normalized.summary.isEmpty {
            sections.append("## Purpose\n\(normalized.summary)")
        }

        sections.append("## Role\n\(normalized.role)")
        sections.append("## Perspective\n\(normalized.perspective)")

        if !normalized.tone.isEmpty {
            sections.append("## Tone\n\(normalized.tone)")
        }

        if !normalized.reasoningSteps.isEmpty {
            let lines = normalized.reasoningSteps.enumerated().map { idx, step in
                "\(idx + 1). \(step)"
            }.joined(separator: "\n")
            sections.append("## Reasoning Steps\n\(lines)")
        }

        var outputLines: [String] = []
        if !normalized.outputFormat.isEmpty {
            outputLines.append("Format: \(normalized.outputFormat)")
        }
        if !normalized.mustInclude.isEmpty {
            let lines = normalized.mustInclude.map { "- \($0)" }.joined(separator: "\n")
            outputLines.append("Must include:\n\(lines)")
        }
        if !normalized.neverInclude.isEmpty {
            let lines = normalized.neverInclude.map { "- \($0)" }.joined(separator: "\n")
            outputLines.append("Never include:\n\(lines)")
        }
        if !outputLines.isEmpty {
            sections.append("## Output Contract\n" + outputLines.joined(separator: "\n\n"))
        }

        var safetyLines: [String] = []
        if !normalized.disclaimers.isEmpty {
            let lines = normalized.disclaimers.map { "- \($0)" }.joined(separator: "\n")
            safetyLines.append("Disclaimers:\n\(lines)")
        }
        if !normalized.prohibitedActions.isEmpty {
            let lines = normalized.prohibitedActions.map { "- \($0)" }.joined(separator: "\n")
            safetyLines.append("Prohibited actions:\n\(lines)")
        }
        if !safetyLines.isEmpty {
            sections.append("## Safety Hints\n" + safetyLines.joined(separator: "\n\n"))
        }

        return sections.joined(separator: "\n\n")
    }

    static func validate(_ draft: ReasoningScaffoldDraft) -> [ValidationIssue] {
        let normalized = normalizeDraft(draft)
        var issues: [ValidationIssue] = []

        if normalized.name.isEmpty {
            issues.append(issue("name", "Name is required."))
        }
        if normalized.role.isEmpty {
            issues.append(issue("role", "Role is required."))
        }
        if normalized.perspective.isEmpty {
            issues.append(issue("perspective", "Perspective is required."))
        }
        if normalized.reasoningSteps.isEmpty {
            issues.append(issue("reasoning_steps", "At least one reasoning step is required."))
        }

        if normalized.name.count > 80 {
            issues.append(issue("name", "Name must be 80 characters or fewer."))
        }
        if normalized.summary.count > 240 {
            issues.append(issue("summary", "Summary must be 240 characters or fewer."))
        }
        if normalized.role.count > 120 {
            issues.append(issue("role", "Role must be 120 characters or fewer."))
        }
        if normalized.perspective.count > 300 {
            issues.append(issue("perspective", "Perspective must be 300 characters or fewer."))
        }
        if normalized.tone.count > 120 {
            issues.append(issue("tone", "Tone must be 120 characters or fewer."))
        }
        if normalized.reasoningSteps.count > 12 {
            issues.append(issue("reasoning_steps", "Use 12 reasoning steps or fewer."))
        }

        for (index, step) in normalized.reasoningSteps.enumerated() where step.count > 220 {
            issues.append(issue("reasoning_step_\(index)", "Each reasoning step must be 220 characters or fewer."))
        }
        for (index, item) in normalized.mustInclude.enumerated() where item.count > 180 {
            issues.append(issue("must_include_\(index)", "Each required element must be 180 characters or fewer."))
        }
        for (index, item) in normalized.neverInclude.enumerated() where item.count > 180 {
            issues.append(issue("never_include_\(index)", "Each prohibited element must be 180 characters or fewer."))
        }
        for (index, item) in normalized.disclaimers.enumerated() where item.count > 220 {
            issues.append(issue("disclaimer_\(index)", "Each disclaimer must be 220 characters or fewer."))
        }
        for (index, item) in normalized.prohibitedActions.enumerated() where item.count > 220 {
            issues.append(issue("prohibited_action_\(index)", "Each prohibited action must be 220 characters or fewer."))
        }

        return issues
    }

    static func apply(_ draft: ReasoningScaffoldDraft, to scaffold: ReasoningScaffold) {
        let normalized = normalizeDraft(draft)
        scaffold.name = normalized.name
        scaffold.summary = normalized.summary
        scaffold.role = normalized.role
        scaffold.perspective = normalized.perspective
        scaffold.tone = normalized.tone
        scaffold.reasoningSteps = normalized.reasoningSteps
        scaffold.outputFormat = normalized.outputFormat
        scaffold.mustInclude = normalized.mustInclude
        scaffold.neverInclude = normalized.neverInclude
        scaffold.disclaimers = normalized.disclaimers
        scaffold.prohibitedActions = normalized.prohibitedActions
        scaffold.updatedAt = Date()
    }

    static func makeScaffold(accountScopeKey: String, draft: ReasoningScaffoldDraft) -> ReasoningScaffold {
        let normalized = normalizeDraft(draft)
        return ReasoningScaffold(
            accountScopeKey: accountScopeKey,
            name: normalized.name,
            summary: normalized.summary,
            role: normalized.role,
            perspective: normalized.perspective,
            tone: normalized.tone,
            reasoningSteps: normalized.reasoningSteps,
            outputFormat: normalized.outputFormat,
            mustInclude: normalized.mustInclude,
            neverInclude: normalized.neverInclude,
            disclaimers: normalized.disclaimers,
            prohibitedActions: normalized.prohibitedActions
        )
    }

    private static func normalizeDraft(_ draft: ReasoningScaffoldDraft) -> ReasoningScaffoldDraft {
        ReasoningScaffoldDraft(
            name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
            summary: draft.summary.trimmingCharacters(in: .whitespacesAndNewlines),
            role: draft.role.trimmingCharacters(in: .whitespacesAndNewlines),
            perspective: draft.perspective.trimmingCharacters(in: .whitespacesAndNewlines),
            tone: draft.tone.trimmingCharacters(in: .whitespacesAndNewlines),
            reasoningSteps: normalizeList(draft.reasoningSteps),
            outputFormat: draft.outputFormat.trimmingCharacters(in: .whitespacesAndNewlines),
            mustInclude: normalizeList(draft.mustInclude),
            neverInclude: normalizeList(draft.neverInclude),
            disclaimers: normalizeList(draft.disclaimers),
            prohibitedActions: normalizeList(draft.prohibitedActions)
        )
    }

    private static func normalizeList(_ input: [String]) -> [String] {
        input.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func issue(_ field: String, _ message: String) -> ValidationIssue {
        ValidationIssue(field: field, message: message, severity: .error)
    }
}
