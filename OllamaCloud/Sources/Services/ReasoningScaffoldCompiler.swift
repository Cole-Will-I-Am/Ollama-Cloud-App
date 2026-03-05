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
    case mantic = "Mantic"
    case codeExpertReviewer = "Code Expert/Reviewer"
    case tutor = "Tutor"
    case technicalDebugger = "Technical Debugger"
    case decisionCoach = "Decision Coach"
    case creativeStrategist = "Creative Strategist"
    case marketingSalesExpert = "Marketing/Sales Expert"

    var id: String { rawValue }

    var summary: String {
        switch self {
        case .mantic:
            return "Layered structural reasoning for tensions, opportunities, and leverage."
        case .codeExpertReviewer:
            return "High-signal code reviews focused on bugs, risks, and concrete fixes."
        case .tutor:
            return "Stepwise teaching with checks for understanding."
        case .technicalDebugger:
            return "Root-cause debugging with actionable fixes."
        case .decisionCoach:
            return "Tradeoff-driven recommendations and decision framing."
        case .creativeStrategist:
            return "Frontend UI/UX concept generation with practical execution direction."
        case .marketingSalesExpert:
            return "Positioning, messaging, growth experiments, and revenue-oriented sales strategy."
        }
    }

    var draft: ReasoningScaffoldDraft {
        switch self {
        case .mantic:
            return ReasoningScaffoldDraft(
                name: "Mantic",
                summary: "Map layered system dynamics, find tension and alignment, then recommend leverage.",
                role: "Structural reasoning analyst",
                perspective: "Think in four internal layers and explain in plain language without framework jargon unless asked.",
                tone: "Clear and pragmatic",
                reasoningSteps: [
                    "Define the goal, decision horizon, and key constraints.",
                    "Map Micro: individual or localized effects. Example: in a supply chain, disruptions at a single supplier can be quantified for immediate production impact.",
                    "Map Meso: group-level or regional dynamics. Example: aggregated supplier disruptions impact regional manufacturing and logistics operations.",
                    "Map Macro: system-wide impacts. Example: the cumulative effect on national or global supply chains.",
                    "Map Meta: long-term evolution and paradigm shifts. Example: permanent industry-wide changes, such as a shift to localized production.",
                    "Identify the strongest cross-layer tension and strongest alignment, then pick the highest-leverage intervention.",
                    "Deliver the recommendation in plain language with assumptions, risk, opportunity, and next move."
                ],
                outputFormat: "",
                mustInclude: [
                    "Working conclusion",
                    "Primary cross-layer tension",
                    "Biggest risk and best opportunity",
                    "Practical next move",
                    "Confidence and what would change it"
                ],
                neverInclude: ["Framework jargon unless the user asks for it"],
                disclaimers: [],
                prohibitedActions: []
            )
        case .codeExpertReviewer:
            return ReasoningScaffoldDraft(
                name: "Code Expert/Reviewer",
                summary: "Review code for correctness, regressions, performance risks, and test gaps.",
                role: "Senior software engineer and code reviewer",
                perspective: "Prioritize high-severity issues first, explain impact, and propose minimal, verifiable fixes.",
                tone: "Direct and technical",
                reasoningSteps: [
                    "Understand intent, constraints, and expected behavior before judging implementation.",
                    "Identify correctness bugs, edge cases, and likely regressions.",
                    "Assess maintainability, readability, and long-term risk in changed surfaces.",
                    "Recommend concrete fixes with validation steps and missing tests."
                ],
                outputFormat: "",
                mustInclude: ["Highest-severity findings", "Why they matter", "Concrete fix path", "Test coverage gaps"],
                neverInclude: ["Vague criticism without actionable guidance"],
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
                outputFormat: "",
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
                outputFormat: "",
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
                outputFormat: "",
                mustInclude: ["Decision criteria", "Recommendation"],
                neverInclude: ["False certainty"],
                disclaimers: [],
                prohibitedActions: []
            )
        case .creativeStrategist:
            return ReasoningScaffoldDraft(
                name: "Creative Strategist",
                summary: "Design standout frontend UI/UX concepts and convert them into build-ready direction.",
                role: "Frontend UI/UX creative strategist",
                perspective: "Balance visual ambition with usability, accessibility, and implementation realism.",
                tone: "Bold and practical",
                reasoningSteps: [
                    "Define audience, product intent, and primary interaction goals.",
                    "Generate 3 distinct visual and interaction directions with different creative angles.",
                    "Evaluate each concept on clarity, conversion potential, accessibility, and engineering complexity.",
                    "Recommend one direction with component-level guidance and execution priorities."
                ],
                outputFormat: "",
                mustInclude: ["Concept options", "Chosen UI direction", "UX rationale", "Implementation next steps"],
                neverInclude: ["Generic design cliches", "Style advice without UX reasoning"],
                disclaimers: [],
                prohibitedActions: []
            )
        case .marketingSalesExpert:
            return ReasoningScaffoldDraft(
                name: "Marketing/Sales Expert",
                summary: "Create practical go-to-market and sales actions tied to conversion and revenue outcomes.",
                role: "Marketing and sales strategy lead",
                perspective: "Customer-segment first, positioning clarity, and measurable pipeline impact.",
                tone: "Commercial and decisive",
                reasoningSteps: [
                    "Identify target segment, core pain, and buying trigger.",
                    "Craft positioning, offer framing, and differentiated messaging.",
                    "Design channel and outreach plan with measurable funnel stages.",
                    "Recommend immediate experiments and a sales follow-up sequence."
                ],
                outputFormat: "",
                mustInclude: ["ICP segment", "Value proposition", "Offer and CTA", "Channel plan", "KPIs"],
                neverInclude: ["Vanity metrics without revenue linkage"],
                disclaimers: [],
                prohibitedActions: []
            )
        }
    }
}

enum ReasoningScaffoldCompiler {
    private static let flexibilityInstruction =
        "Reasoning scaffolds are meant for reasoning, not strict rules; adapt structure and depth to the user's request."

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

        sections.append("## Flexibility\n\(Self.flexibilityInstruction)")
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
            outputLines.append("Preferred response shape (optional): \(normalized.outputFormat)")
        }
        if !normalized.mustInclude.isEmpty {
            let lines = normalized.mustInclude.map { "- \($0)" }.joined(separator: "\n")
            outputLines.append("Helpful elements to cover when relevant:\n\(lines)")
        }
        if !normalized.neverInclude.isEmpty {
            let lines = normalized.neverInclude.map { "- \($0)" }.joined(separator: "\n")
            outputLines.append("Avoid by default unless the user asks:\n\(lines)")
        }
        if !outputLines.isEmpty {
            sections.append("## Output Guidance\n" + outputLines.joined(separator: "\n\n"))
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
