import Foundation

struct WorkflowBlueprint {
    let type: String
    let stations: [WorkflowStation]
}

struct WorkflowStation: Identifiable {
    let key: String
    let name: String
    let purpose: String
    let stops: [String]
    var id: String { key }
}

enum WorkflowBlueprints {
    static func forType(_ type: String) -> WorkflowBlueprint {
        switch type {
        case "books & publishing": books
        case "website": website
        case "software": software
        case "professional research": research
        default: operations
        }
    }

    static let books = WorkflowBlueprint(type: "Books & Publishing", stations: [
        .init(key: "BOOK_SETUP", name: "Book Definition", purpose: "Define the book, its authority boundaries, and its place in the catalogue.", stops: ["Reader, premise, voice, and production-intent brief", "Named author decision to open the book workflow"]),
        .init(key: "PROMISE", name: "Reader Promise", purpose: "Make the reader transformation and market position testable.", stops: ["Reader transformation and central promise", "Positioning brief and comparable-title landscape"]),
        .init(key: "MARKET", name: "Market & Audience", purpose: "Test who the book is for and how it earns attention.", stops: ["Defined primary audience and reader-entry path", "Demand signals, channel assumptions, and risks"]),
        .init(key: "OUTLINE", name: "Architecture", purpose: "Build a chapter sequence that can deliver the promise.", stops: ["Table of contents with section and chapter purposes", "Chapter role, length, and continuity plan"]),
        .init(key: "BASE_STORY", name: "Narrative & Voice", purpose: "Create the unifying story spine and voice guardrails.", stops: ["Book-wide narrative or argument arc", "Voice guide and chapter base-story plan"]),
        .init(key: "RESEARCH", name: "Research & Claims", purpose: "Ground factual claims in attributable, reviewable evidence.", stops: ["Research dossiers and source ledger", "Verified claims or explicit author-review exceptions"]),
        .init(key: "STORIES_RIGHTS", name: "Stories & Rights", purpose: "Use external and personal stories with permission and context.", stops: ["Chapter-mapped case and personal-story collection", "Attribution, consent, rights, and source-status check"]),
        .init(key: "MANIFEST", name: "Chapter Packets", purpose: "Assign each chapter only the material it may responsibly use.", stops: ["Selected and excluded material packet per chapter", "Draft-ready chapter thread and source packet"]),
        .init(key: "CHAPTER_DRAFT", name: "Manuscript Draft", purpose: "Produce a complete manuscript that actually delivers the promise.", stops: ["Complete draft for every chapter", "Whole-manuscript continuity and pacing pass"]),
        .init(key: "DEVELOPMENTAL_EDIT", name: "Developmental Edit", purpose: "Solve structural, argument, repetition, and reader-experience problems.", stops: ["Editorial diagnosis and revision plan", "Resolved structural changes with author decisions retained"]),
        .init(key: "PEER_REVIEW", name: "Peer & Beta Review", purpose: "Test the manuscript with qualified outside readers before finalizing it.", stops: ["Reader, peer, or subject-matter review packet", "Feedback inventory with disposition for every material issue"]),
        .init(key: "AUTHOR_REVISION", name: "Author Revision", purpose: "Integrate the feedback Chris accepts while protecting the book’s intent.", stops: ["Revised manuscript and change summary", "Open questions, deferrals, and author decisions recorded"]),
        .init(key: "COPY_EDIT", name: "Copy Edit", purpose: "Improve clarity, consistency, grammar, and style line by line.", stops: ["Edited manuscript with tracked changes", "Style-sheet, terminology, and consistency review"]),
        .init(key: "FACT_AUDIT", name: "Fact, Citation & Rights Audit", purpose: "Prove support, attribution, permissions, and legal/ethical boundaries.", stops: ["Citation, bibliography, attribution, and permissions audit", "Unresolved claims, risks, and required approvals named"]),
        .init(key: "PROOFREAD", name: "Proofread", purpose: "Catch final errors after the manuscript has stabilized.", stops: ["Proofreading pass on final text", "Author disposition of remaining proof corrections"]),
        .init(key: "PRODUCTION", name: "Book Production", purpose: "Create the actual reader-ready editions and sales assets.", stops: ["Interior files, cover package, metadata, and edition profiles", "Accessible eBook, print files, and retailer-description package"]),
        .init(key: "PREFLIGHT", name: "Preflight & Proof", purpose: "Inspect the real output before any public release.", stops: ["Rendered print/eBook proof and preflight checklist", "Corrections resolved or consciously accepted by the author"]),
        .init(key: "RELEASE_GATE", name: "Release Decision", purpose: "Make the explicit human decision to publish, delay, or revise.", stops: ["Decision-ready release packet with known risks", "Named approval or decision to return to revision"]),
        .init(key: "PUBLISH", name: "Publish & Distribute", purpose: "Execute authorized distribution and preserve the release record.", stops: ["Authorized retailer upload or distribution record", "Live-listing verification and immutable release receipt"]),
        .init(key: "LAUNCH", name: "Launch Readiness", purpose: "Coordinate a bounded launch that serves the right readers.", stops: ["Audience, offer, channels, timeline, and success measure", "Approved launch assets, outreach list, and owner assignments"]),
        .init(key: "MARKETING", name: "Marketing & Reader Path", purpose: "Sustain discoverability and move readers into the next useful step.", stops: ["Ongoing content, partnership, and audience plan", "Back-matter, website, email, and catalogue pathway"]),
        .init(key: "POST_PUBLICATION", name: "Post-Publication Review", purpose: "Learn from readers and decide whether the edition or strategy needs change.", stops: ["Reader feedback, sales, and quality observation record", "Next-edition, marketing, or archive decision"])
    ])

    static let website = WorkflowBlueprint(type: "Website", stations: [
        .init(key: "STRATEGY", name: "Strategy", purpose: "Establish purpose, audience, and conversion/formation outcome.", stops: ["Audience and desired next action", "Success, trust, and authority boundaries"]),
        .init(key: "IA_CONTENT", name: "Information & Content", purpose: "Decide what the site must say and where.", stops: ["Page map and navigation", "Approved page copy and required content inventory"]),
        .init(key: "DESIGN", name: "Design System", purpose: "Make the experience coherent before build.", stops: ["Visual direction and reusable components", "Responsive page designs or approved build reference"]),
        .init(key: "BUILD", name: "Build", purpose: "Implement the public experience.", stops: ["Working responsive pages and forms", "Analytics, content, and integration configuration"]),
        .init(key: "QUALITY", name: "Quality & Trust", purpose: "Protect people and the brand before launch.", stops: ["Accessibility, performance, link, and mobile checks", "Privacy, permissions, and public-claim review"]),
        .init(key: "LAUNCH", name: "Launch & Learn", purpose: "Release deliberately and measure what happens.", stops: ["Approved deployment and rollback plan", "Post-launch measurement review and next improvement decision"])
    ])

    static let software = WorkflowBlueprint(type: "Software", stations: [
        .init(key: "OUTCOME", name: "Outcome & Acceptance", purpose: "Define the problem and proof of usefulness.", stops: ["User outcome and success criteria", "Acceptance scenarios and authority boundaries"]),
        .init(key: "ARCHITECTURE", name: "Architecture & Trust", purpose: "Choose a durable, safe technical shape.", stops: ["System design and data/permission boundaries", "Risk, privacy, and failure-mode review"]),
        .init(key: "BUILD", name: "Build", purpose: "Deliver the smallest complete product slice.", stops: ["Implemented end-to-end user flow", "Required integrations and migration/rollback notes"]),
        .init(key: "VERIFY", name: "Verification", purpose: "Prove behavior beyond a passing build.", stops: ["Automated tests and adversarial checks", "Real-device or real-workflow evidence"]),
        .init(key: "ACCEPT", name: "Functional Acceptance", purpose: "Confirm it solves the intended problem.", stops: ["Named acceptance record against scenarios", "Known limitations and support plan"]),
        .init(key: "RELEASE", name: "Release & Observe", purpose: "Ship responsibly and learn from reality.", stops: ["Signed/package release and deployment proof", "Post-release monitoring and next-decision review"])
    ])

    static let research = WorkflowBlueprint(type: "Professional Research", stations: [
        .init(key: "DECISION", name: "Decision Frame", purpose: "Start with the decision, not an interesting topic.", stops: ["Decision question, owner, and deadline", "What evidence would change the recommendation"]),
        .init(key: "PLAN", name: "Evidence Plan", purpose: "Set scope and quality before collection.", stops: ["Research plan and source hierarchy", "Known constraints, assumptions, and exclusions"]),
        .init(key: "COLLECT", name: "Collect & Verify", purpose: "Build a source-backed evidence base.", stops: ["Attributable sources and exact support", "Verification notes, conflicts, and gaps"]),
        .init(key: "ANALYZE", name: "Analysis", purpose: "Turn evidence into defensible implications.", stops: ["Comparison or synthesis with uncertainty labeled", "Key risks, dependencies, and alternatives"]),
        .init(key: "RECOMMEND", name: "Recommendation", purpose: "Make the decision legible.", stops: ["Clear recommendation and tradeoffs", "Smallest justified next action"]),
        .init(key: "RECORD", name: "Decision Record", purpose: "Close the loop after judgment.", stops: ["Decision, owner, and rationale", "Follow-up trigger and evidence to revisit"])
    ])

    static let operations = WorkflowBlueprint(type: "Portfolio & Operations", stations: [
        .init(key: "STRATEGY", name: "Strategy & Guardrails", purpose: "Keep the portfolio aligned with the life it serves.", stops: ["Priorities, non-goals, and success measures", "Decision rights and operating constraints"]),
        .init(key: "BASELINE", name: "Registry & Baseline", purpose: "Make the operating picture trustworthy.", stops: ["Current project register and evidence dates", "Known unknowns and capacity baseline"]),
        .init(key: "SEQUENCE", name: "Capacity & Sequencing", purpose: "Convert ambition into an executable order.", stops: ["Bounded capacity and work-in-progress limit", "Near-term milestones and dependencies"]),
        .init(key: "EXECUTE", name: "Execution Cadence", purpose: "Move the few right things consistently.", stops: ["Named owners and next actions", "Weekly operating rhythm and escalation path"]),
        .init(key: "REVIEW", name: "Operating Review", purpose: "Inspect reality and make decisions.", stops: ["Evidence-backed weekly/monthly review", "Blocked, deferred, and completed work disposition"]),
        .init(key: "RESET", name: "Portfolio Reset", purpose: "Recommit or stop work intentionally.", stops: ["Quarterly priority and capacity decision", "Archive, pause, or recommit record"])
    ])
}
