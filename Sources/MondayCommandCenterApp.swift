import AppKit
import Foundation
import SwiftUI

@main
struct MondayCommandCenterApp: App {
    var body: some Scene {
        WindowGroup("Command Center") {
            MondayCommandCenterShell()
                .frame(minWidth: 1180, minHeight: 820)
        }
        .windowResizability(.contentMinSize)
    }
}

private enum CommandCenterRoom: String, CaseIterable, Identifiable {
    case today, projects, personalProjects, digitalTwin, continuity, activity, operations, journal, researchJournal, planner
    var id: String { rawValue }
    var title: String {
        switch self {
        case .today: "Today"
        case .projects: "Projects"
        case .personalProjects: "Personal Projects"
        case .digitalTwin: "Digital Twin"
        case .continuity: "Meeting Continuity"
        case .activity: "Activity Ledger"
        case .operations: "MONDAY Operations"
        case .journal: "Captain's Log"
        case .researchJournal: "Research Chronicle"
        case .planner: "Planner"
        }
    }
    var icon: String {
        switch self {
        case .today: "rectangle.grid.2x2.fill"
        case .projects: "point.3.connected.trianglepath.dotted"
        case .personalProjects: "person.crop.circle.badge.checkmark"
        case .digitalTwin: "person.text.rectangle.fill"
        case .continuity: "checklist.checked"
        case .activity: "list.bullet.rectangle.portrait.fill"
        case .operations: "waveform.path.ecg.rectangle.fill"
        case .journal: "book.closed.fill"
        case .researchJournal: "text.book.closed.fill"
        case .planner: "calendar"
        }
    }
}

private struct MondayCommandCenterShell: View {
    @State private var room: CommandCenterRoom = .today
    @StateObject private var pairing = CommandCenterPairing.shared
    @State private var showingPairing = false

    var body: some View {
        roomContent
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Menu {
                    Picker("Rooms", selection: $room) {
                        ForEach(CommandCenterRoom.allCases) { room in Label(room.title, systemImage: room.icon).tag(room) }
                    }
                } label: {
                    Label("Rooms", systemImage: "square.grid.2x2")
                }
            }
            ToolbarItem(placement: .automatic) {
                Button { showingPairing = true } label: {
                    Label(pairing.isPaired ? "Settings" : "Set up MONDAY", systemImage: pairing.isPaired ? "gearshape" : "link.badge.plus")
                }
            }
        }
        .sheet(isPresented: $showingPairing) { CommandCenterPairingView() }
        .task {
            if !pairing.isPaired { _ = pairing.discoverAndPairIfPossible() }
            showingPairing = !pairing.isPaired
        }
    }

    @ViewBuilder private var roomContent: some View {
        switch room {
        case .today: CommandCenterDashboard(room: $room)
        case .projects: CommandCenterView()
        case .personalProjects: PersonalProjectsRoom()
        case .digitalTwin: TwinInspectionRoom()
        case .continuity: MeetingContinuityRoom()
        case .activity: GovernedRecordLibraryRoom(title: "Activity Ledger", subtitle: "Observable MONDAY and Codex activity receipts. This is not a complete account of your day.", rootURL: pairing.activityLedgerURL, emptyMessage: "Choose the Activity Ledger folder in Settings.")
        case .operations: GovernedRecordLibraryRoom(title: "MONDAY Operations", subtitle: "Pipeline receipts, source health, open loops, and inspectable operational records.", rootURL: pairing.operationsURL, emptyMessage: "Choose the MONDAY Operations folder in Settings.")
        case .journal: VaultTomeRoom(title: "Captain's Log", subtitle: "Your personal journal, read from Chris Knowledge.", rootURL: pairing.captainsLogURL, emptyTitle: "No Captain's Log entries are available")
        case .researchJournal: VaultTomeRoom(title: "Research Chronicle", subtitle: "Verified MONDAY system-building records, read from Monday Knowledge.", rootURL: pairing.researchJournalURL, emptyTitle: "No MONDAY Research Chronicle entries are available")
        case .planner: PlannerRoom()
        }
    }
}

private struct CommandCenterDashboard: View {
    @Binding var room: CommandCenterRoom
    @StateObject private var projects = ProjectStore()
    @StateObject private var calendar = CalendarStore()
    @StateObject private var weather = WeatherStore()
    @StateObject private var planner = DailyPlannerFeed()
    @ObservedObject private var pairing = CommandCenterPairing.shared

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    private var todayKey: String { Self.dateFormatter.string(from: .now) }

    var body: some View {
        ZStack {
            DashboardPalette.canvas.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    masthead
                    commandDeck
                    provenanceNote
                }
                .padding(.horizontal, 34)
                .padding(.bottom, 32)
                .frame(maxWidth: 1560)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            while !Task.isCancelled {
                await refreshDeck()
                do { try await Task.sleep(for: .seconds(60)) }
                catch { return }
            }
        }
        .task(id: pairing.weatherAddress) {
            let address = pairing.weatherAddress.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !address.isEmpty else { return }
            while !Task.isCancelled {
                await weather.refresh(for: address)
                do { try await Task.sleep(for: .seconds(900)) }
                catch { return }
            }
        }
    }

    private var masthead: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 7) {
                Label("MONDAY COMMAND CENTER", systemImage: "sparkles")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.6)
                    .foregroundStyle(DashboardPalette.accent)
                Text("The day, in focus.")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text("A calm operating picture for what needs attention, context, or a real decision.")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.64))
            }
            Spacer(minLength: 20)
            HStack(spacing: 10) {
                Button { room = .projects } label: {
                    Label("Projects", systemImage: "point.3.connected.trianglepath.dotted")
                }
                .buttonStyle(CommandButtonStyle(prominent: false))
                Button { Task { await refreshDeck() } } label: {
                    Label(projects.loading ? "Refreshing" : "Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(CommandButtonStyle(prominent: false))
                .disabled(projects.loading)
            }
        }
        .padding(.vertical, 24)
    }

    private func refreshDeck() async {
        await projects.reload()
        await calendar.reloadToday()
        await planner.refresh(for: todayKey)
        let address = pairing.weatherAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        if !address.isEmpty { await weather.refresh(for: address) }
    }

    private var commandDeck: some View {
        ZStack {
            CommandDeckWeatherBackdrop(snapshot: weather.snapshot)
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("TODAY'S COMMAND DECK")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .tracking(1.5)
                            .foregroundStyle(.white.opacity(0.55))
                        Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                            .font(.system(size: 25, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                        Text(deckPosture)
                            .font(.system(size: 16, weight: .medium, design: .serif))
                            .foregroundStyle(.white.opacity(0.84))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 18)
                    AmbientWeatherStatus(snapshot: weather.snapshot, configured: !pairing.weatherAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                HStack(alignment: .top, spacing: 14) {
                    CommandDeckPanel(eyebrow: "TODAY'S COMMANDS", title: "The few moves that matter", icon: "flag.checkered") {
                        CommandDeckLines(items: primaryCommands, empty: "No approved daily priorities were supplied. Open Planner to refresh MONDAY's daily brief.")
                        Button { room = .planner } label: { Label("Open Planner", systemImage: "arrow.right") }
                            .buttonStyle(CommandButtonStyle(prominent: true))
                    }
                    CommandDeckPanel(eyebrow: "NEEDS YOUR JUDGMENT", title: "MONDAY will not decide these for you", icon: "person.crop.circle.badge.questionmark") {
                        CommandDeckLines(items: judgmentItems, empty: "No recorded project judgment is waiting. That does not prove every project is current.")
                        Button { room = .projects } label: { Label("Review projects", systemImage: "arrow.right") }
                            .buttonStyle(CommandButtonStyle(prominent: false))
                    }
                }

                HStack(alignment: .top, spacing: 14) {
                    CommandDeckPanel(eyebrow: "RISKS & OPEN LOOPS", title: "What should not quietly slip", icon: "exclamationmark.triangle") {
                        CommandDeckLines(items: riskItems, empty: "No risk list was supplied with this planning brief. Meeting Continuity remains separately governed.")
                        Button { room = .continuity } label: { Label("Open continuity", systemImage: "arrow.right") }
                            .buttonStyle(CommandButtonStyle(prominent: false))
                    }
                    CommandDeckPanel(eyebrow: "MONDAY'S READ", title: "A brief, evidence-bounded posture", icon: "sparkles") {
                        Text(mondayRead)
                            .font(.system(size: 13, design: .serif))
                            .foregroundStyle(.white.opacity(0.78))
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(sourceHealthLine)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.46))
                    }
                }

                CommandDeckContextBar(calendar: calendar, planner: planner.plan)
            }
            .padding(24)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.15), lineWidth: 1))
    }

    private var primaryCommands: [String] {
        if let priorities = planner.plan?.priorities.a, !priorities.isEmpty { return Array(priorities.prefix(3)) }
        return calendar.events.prefix(3).map { "Honor \($0.timeLabel): \($0.title)" }
    }

    private var judgmentItems: [String] {
        let attention = projects.projects.filter { ["intervention", "at-risk", "watch"].contains($0.health) }
        if !attention.isEmpty { return attention.prefix(3).map { "\($0.title): \($0.nextAction ?? $0.gateSummary)" } }
        let unknown = projects.projects.filter { $0.health == "unknown" }
        return unknown.prefix(2).map { "\($0.title): recorded status has not been assessed" }
    }

    private var riskItems: [String] { Array(planner.plan?.brief?.risks.prefix(3) ?? []) }
    private var mondayRead: String {
        if let mission = planner.plan?.brief?.mission, !mission.isEmpty { return mission }
        if let focus = planner.plan?.primaryFocus, !focus.isEmpty { return focus }
        return "The current picture is intentionally limited to connected records. Refresh the Planner to prepare MONDAY's evidence-bounded daily posture."
    }
    private var deckPosture: String {
        if let focus = planner.plan?.primaryFocus, !focus.isEmpty { return focus }
        return "Protect commitments, then use evidence to choose the next move."
    }
    private var sourceHealthLine: String {
        let sources = planner.plan?.sources ?? []
        guard !sources.isEmpty else { return "Planner source health is not available yet." }
        let available = sources.filter { $0.status == "available" }.count
        let unresolved = sources.count - available
        return unresolved == 0
            ? "All \(sources.count) planning sources report available · details remain in Planner"
            : "\(available) of \(sources.count) planning sources available · \(unresolved) limited or unknown · details remain in Planner"
    }

    private var provenanceNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.shield.fill").foregroundStyle(DashboardPalette.accent)
            Text("Project context comes from the governed MONDAY registry. Weather, calendar, and conversation are separately connected on purpose: this screen never turns missing information into a confident story.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.58))
        }
        .padding(15)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(.white.opacity(0.08), lineWidth: 1))
    }
}

#if LEGACY_COMMAND_RADAR
private struct CommandRadar: View {
    private struct Reading {
        let label: String
        let icon: String
        let color: Color
        let title: String
        let detail: String
        let destination: CommandCenterRoom
    }

    let projects: [Project]
    let weather: WeatherSnapshot?
    let calendarEvents: [DayEvent]
    let calendarConnected: Bool
    let openRoom: (CommandCenterRoom) -> Void
    @State private var active = 0
    @State private var angle = -90.0

    private var readings: [Reading] {
        let attention = projects.filter { ["intervention", "at-risk", "watch"].contains($0.health) }
        let projectDetail: String = {
            guard !projects.isEmpty else { return "The governed registry has not reported a project signal yet." }
            if attention.isEmpty { return "All \(projects.count) recorded projects are presently clear of an attention signal." }
            return "\(attention.count) project\(attention.count == 1 ? "" : "s") need attention: " + attention.prefix(2).map(\.title).joined(separator: " · ")
        }()
        let weatherDetail = weather.map { "\($0.place): \($0.temperature.formatted(.number.precision(.fractionLength(0))))° and \($0.condition.lowercased())." } ?? "Set a location when you want a live weather signal. Nothing is assumed."
        let calendarDetail = calendarConnected ? (calendarEvents.isEmpty ? "No remaining appointments are recorded today." : "\(calendarEvents.count) remaining appointment\(calendarEvents.count == 1 ? "" : "s"): " + calendarEvents.prefix(2).map(\.title).joined(separator: " · ")) : "Calendar remains private until you choose to connect it."
        return [
            Reading(label: "PROJECTS", icon: "point.3.connected.trianglepath.dotted", color: DashboardPalette.red, title: "Project signal", detail: projectDetail, destination: .projects),
            Reading(label: "WEATHER", icon: "cloud.sun.fill", color: DashboardPalette.accent, title: "Outside", detail: weatherDetail, destination: .today),
            Reading(label: "CALENDAR", icon: "calendar", color: DashboardPalette.green, title: "Today’s time", detail: calendarDetail, destination: .planner),
            Reading(label: "CAPTAIN’S LOG", icon: "book.closed.fill", color: DashboardPalette.amber, title: "Your MONDAY Journal", detail: "Your Personal Log is a read-only shelf of the things worth returning to.", destination: .journal),
        ]
    }

    var body: some View {
        let selected = readings[active]
        HStack(spacing: 24) {
            GeometryReader { proxy in
                let side = min(proxy.size.width, proxy.size.height)
                ZStack {
                    Canvas { context, size in
                        let center = CGPoint(x: size.width / 2, y: size.height / 2)
                        let outer = min(size.width, size.height) * 0.45
                        let inner = outer * 0.42
                        for ring in [outer, outer * 0.72, inner] {
                            context.stroke(Path(ellipseIn: CGRect(x: center.x - ring, y: center.y - ring, width: ring * 2, height: ring * 2)), with: .color(.white.opacity(0.16)), lineWidth: 1)
                        }
                        for index in readings.indices {
                            let radians = Double(index) * (2 * .pi / Double(readings.count)) - .pi / 2
                            let end = CGPoint(x: center.x + cos(radians) * outer, y: center.y + sin(radians) * outer)
                            var spoke = Path(); spoke.move(to: CGPoint(x: center.x + cos(radians) * inner, y: center.y + sin(radians) * inner)); spoke.addLine(to: end)
                            context.stroke(spoke, with: .color(.white.opacity(0.15)), style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
                        }
                        let start = Angle.degrees(angle - 30)
                        let end = Angle.degrees(angle + 30)
                        var wedge = Path(); wedge.move(to: center); wedge.addArc(center: center, radius: outer, startAngle: start, endAngle: end, clockwise: false); wedge.closeSubpath()
                        context.fill(wedge, with: .color(selected.color.opacity(0.18)))
                        context.stroke(wedge, with: .color(selected.color.opacity(0.92)), lineWidth: 1.2)
                        context.fill(Path(ellipseIn: CGRect(x: center.x - inner * 0.68, y: center.y - inner * 0.68, width: inner * 1.36, height: inner * 1.36)), with: .color(DashboardPalette.card))
                        context.stroke(Path(ellipseIn: CGRect(x: center.x - inner * 0.68, y: center.y - inner * 0.68, width: inner * 1.36, height: inner * 1.36)), with: .color(selected.color.opacity(0.62)), lineWidth: 1)
                    }
                    VStack(spacing: 6) {
                        Image(systemName: selected.icon).font(.system(size: 24, weight: .medium)).foregroundStyle(selected.color)
                        Text("LIVE FOCUS").font(.system(size: 8, weight: .bold, design: .rounded)).tracking(1.2).foregroundStyle(.white.opacity(0.45))
                    }
                }
                .frame(width: side, height: side)
                .contentShape(Circle())
                .onContinuousHover { phase in
                    guard case .active(let location) = phase else { return }
                    let center = CGPoint(x: side / 2, y: side / 2)
                    let raw = atan2(location.y - center.y, location.x - center.x) * 180 / .pi + 90
                    let normalized = (raw + 360).truncatingRemainder(dividingBy: 360)
                    angle = normalized - 90
                    active = Int(((normalized + 36) / 72).rounded(.down)) % readings.count
                }
                .animation(.easeOut(duration: 0.12), value: angle)
                .animation(.easeOut(duration: 0.12), value: active)
            }
            .frame(width: 250, height: 250)
            VStack(alignment: .leading, spacing: 10) {
                Text(selected.label).font(.system(size: 10, weight: .bold, design: .rounded)).tracking(1.5).foregroundStyle(selected.color)
                Text(selected.title).font(.system(size: 25, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                Text(selected.detail).font(.system(size: 14)).foregroundStyle(.white.opacity(0.66)).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 2)
                Button { openRoom(selected.destination) } label: { Label(selected.destination == .today ? "Stay on today" : "Open (selected.destination.title)", systemImage: "arrow.right") }
                    .buttonStyle(CommandButtonStyle(prominent: false))
            }
            .frame(maxWidth: .infinity, minHeight: 178, alignment: .leading)
            .padding(.vertical, 20)
        }
        .padding(20)
        .background(DashboardPalette.card, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.11), lineWidth: 1))
        .overlay(alignment: .topLeading) {
            Text("COMMAND RADAR · MOVE THROUGH THE DIAL")
                .font(.system(size: 9, weight: .bold, design: .rounded)).tracking(1.4)
                .foregroundStyle(.white.opacity(0.42)).padding(14)
        }
    }
}

private struct CommandRadarRoom: View {
    private struct Reading {
        let label: String
        let icon: String
        let color: Color
        let title: String
        let detail: String
        let destination: CommandCenterRoom
    }

    @StateObject private var projects = ProjectStore()
    @StateObject private var calendar = CalendarStore()
    @StateObject private var weather = WeatherStore()
    @AppStorage("weatherLocation") private var weatherLocation = ""
    @State private var active = 0
    @State private var angle = -90.0
    let openRoom: (CommandCenterRoom) -> Void

    private var readings: [Reading] {
        let attention = projects.projects.filter { ["intervention", "at-risk", "watch"].contains($0.health) }
        let projectDetail: String = {
            guard !projects.projects.isEmpty else { return "The governed registry has not reported a project signal yet." }
            if attention.isEmpty { return "All \(projects.projects.count) recorded projects are presently clear of an attention signal." }
            return "\(attention.count) project\(attention.count == 1 ? "" : "s") want a closer look: " + attention.prefix(3).map(\.title).joined(separator: " · ")
        }()
        let weatherDetail = weather.snapshot.map { "\($0.place) · \($0.temperature.formatted(.number.precision(.fractionLength(0))))° · \($0.condition)" } ?? "Weather stays deliberately quiet until you set a location."
        let calendarDetail = calendar.state == .connected ? (calendar.events.isEmpty ? "No remaining appointments are recorded today." : "\(calendar.events.count) remaining appointment\(calendar.events.count == 1 ? "" : "s"): " + calendar.events.prefix(3).map(\.title).joined(separator: " · ")) : "Calendar remains private until you choose to connect it."
        return [
            Reading(label: "PROJECTS", icon: "point.3.connected.trianglepath.dotted", color: DashboardPalette.red, title: "Project signal", detail: projectDetail, destination: .projects),
            Reading(label: "WEATHER", icon: "cloud.sun.fill", color: DashboardPalette.accent, title: "Outside", detail: weatherDetail, destination: .today),
            Reading(label: "CALENDAR", icon: "calendar", color: DashboardPalette.green, title: "Today’s time", detail: calendarDetail, destination: .planner),
            Reading(label: "CAPTAIN’S LOG", icon: "book.closed.fill", color: DashboardPalette.amber, title: "Your MONDAY Journal", detail: "Your Personal Log is held as a private shelf of the things worth returning to.", destination: .journal),
        ]
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.009, green: 0.014, blue: 0.023), Color(red: 0.018, green: 0.031, blue: 0.052)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
            GeometryReader { proxy in
                let width = proxy.size.width
                let height = proxy.size.height
                let side = min(width * 0.60, height * 0.88)
                let center = CGPoint(x: width * 0.55, y: height * 0.57)
                let selected = readings[active]
                ZStack {
                    Canvas { context, size in
                        let outer = side * 0.47
                        let inner = outer * 0.30
                        func arc(_ radius: CGFloat, _ start: Double, _ end: Double, _ color: Color, _ lineWidth: CGFloat = 1) {
                            var path = Path()
                            path.addArc(center: center, radius: radius, startAngle: .degrees(start), endAngle: .degrees(end), clockwise: false)
                            context.stroke(path, with: .color(color), lineWidth: lineWidth)
                        }
                        for ring in [outer * 1.12, outer, outer * 0.87, outer * 0.70, outer * 0.53, inner] {
                            context.stroke(Path(ellipseIn: CGRect(x: center.x - ring, y: center.y - ring, width: ring * 2, height: ring * 2)), with: .color(.white.opacity(ring == outer ? 0.32 : 0.12)), lineWidth: ring == outer ? 1.5 : 1)
                        }
                        arc(outer * 1.16, -206, -72, .white.opacity(0.55), 2)
                        arc(outer * 1.16, -68, 16, DashboardPalette.accent.opacity(0.75), 2)
                        arc(outer * 1.16, 24, 110, .white.opacity(0.32), 1)
                        arc(outer * 1.04, 118, 220, .white.opacity(0.58), 3)
                        arc(outer * 0.95, -165, -55, DashboardPalette.accent.opacity(0.54), 2)
                        for tick in 0..<96 {
                            let radians = Double(tick) * 2 * .pi / 96 - .pi / 2
                            let startRadius = outer - (tick.isMultiple(of: 5) ? 13 : 7)
                            var tickPath = Path()
                            tickPath.move(to: CGPoint(x: center.x + cos(radians) * startRadius, y: center.y + sin(radians) * startRadius))
                            tickPath.addLine(to: CGPoint(x: center.x + cos(radians) * outer, y: center.y + sin(radians) * outer))
                            context.stroke(tickPath, with: .color(.white.opacity(tick.isMultiple(of: 5) ? 0.46 : 0.19)), lineWidth: tick.isMultiple(of: 5) ? 1.3 : 0.7)
                        }
                        let gaugeColors: [Color] = [DashboardPalette.accent, DashboardPalette.accent, DashboardPalette.amber]
                        let gaugeStarts: [Double] = [-152, -50, 22]
                        for group in 0..<3 {
                            for bar in 0..<22 {
                                let degrees = gaugeStarts[group] + Double(bar) * 3.25
                                let radians = degrees * .pi / 180
                                let activity = ((bar * (group + 3) + active * 5) % 9) < 6
                                let from = outer * 0.63
                                let to = from + (activity ? outer * 0.16 : outer * 0.07)
                                var barPath = Path()
                                barPath.move(to: CGPoint(x: center.x + cos(radians) * from, y: center.y + sin(radians) * from))
                                barPath.addLine(to: CGPoint(x: center.x + cos(radians) * to, y: center.y + sin(radians) * to))
                                context.stroke(barPath, with: .color(gaugeColors[group].opacity(activity ? 0.88 : 0.22)), lineWidth: 2)
                            }
                        }
                        for index in readings.indices {
                            let radians = Double(index) * (2 * .pi / Double(readings.count)) - .pi / 2
                            let start = CGPoint(x: center.x + cos(radians) * inner, y: center.y + sin(radians) * inner)
                            let end = CGPoint(x: center.x + cos(radians) * outer * 0.58, y: center.y + sin(radians) * outer * 0.58)
                            var spoke = Path(); spoke.move(to: start); spoke.addLine(to: end)
                            context.stroke(spoke, with: .color(index == active ? selected.color.opacity(0.75) : .white.opacity(0.15)), style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
                        }
                        var wedge = Path()
                        wedge.move(to: center)
                        wedge.addArc(center: center, radius: outer * 1.11, startAngle: .degrees(angle - 23), endAngle: .degrees(angle + 23), clockwise: false)
                        wedge.closeSubpath()
                        context.fill(wedge, with: .color(selected.color.opacity(0.14)))
                        context.stroke(wedge, with: .color(selected.color.opacity(0.94)), lineWidth: 1.25)
                        context.fill(Path(ellipseIn: CGRect(x: center.x - inner, y: center.y - inner, width: inner * 2, height: inner * 2)), with: .color(Color(red: 0.025, green: 0.045, blue: 0.070)))
                        context.stroke(Path(ellipseIn: CGRect(x: center.x - inner, y: center.y - inner, width: inner * 2, height: inner * 2)), with: .color(selected.color.opacity(0.82)), lineWidth: 1.4)
                        for node in 0..<5 {
                            let radians = Double(node) * 2 * .pi / 5 - .pi / 2
                            let radius = inner * 0.70
                            let nodeRect = CGRect(x: center.x + cos(radians) * radius - 3, y: center.y + sin(radians) * radius - 3, width: 6, height: 6)
                            context.fill(Path(ellipseIn: nodeRect), with: .color(node == active ? selected.color : .white.opacity(0.42)))
                        }
                    }
                    .allowsHitTesting(false)
                    VStack(spacing: 8) {
                        Image(systemName: selected.icon).font(.system(size: 31, weight: .medium)).foregroundStyle(selected.color)
                        Text("MONDAY").font(.system(size: 11, weight: .bold, design: .rounded)).tracking(3).foregroundStyle(.white.opacity(0.76))
                        Text("FOCUS ONLINE").font(.system(size: 8, weight: .bold, design: .rounded)).tracking(1.4).foregroundStyle(selected.color.opacity(0.72))
                    }
                    .position(center)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: selected.icon).foregroundStyle(selected.color)
                            Text(selected.label).font(.system(size: 9, weight: .bold, design: .rounded)).tracking(1.4).foregroundStyle(selected.color)
                        }
                        Text(selected.title).font(.system(size: 21, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                        Text(selected.detail).font(.system(size: 12)).foregroundStyle(.white.opacity(0.64)).lineSpacing(3).lineLimit(5)
                        HStack(spacing: 5) {
                            ForEach(0..<8, id: \.self) { bar in
                                Rectangle().fill(bar < active + 3 ? selected.color : .white.opacity(0.16)).frame(width: 12, height: CGFloat(7 + (bar % 3) * 5))
                            }
                        }
                        Button { openRoom(selected.destination) } label: { Text(selected.destination == .today ? "RETURN TO TODAY  →" : "OPEN \(selected.destination.title.uppercased())  →").font(.system(size: 10, weight: .bold, design: .rounded)).tracking(0.7) }
                            .buttonStyle(.plain).foregroundStyle(.white.opacity(0.82))
                    }
                    .padding(17)
                    .frame(width: min(260, width * 0.23), alignment: .leading)
                    .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(selected.color.opacity(0.74), lineWidth: 1))
                    .rotationEffect(.degrees(-8))
                    .position(x: width * 0.19, y: height * 0.49)
                    HStack(spacing: 7) {
                        Circle().fill(DashboardPalette.green).frame(width: 6, height: 6)
                        Text("MONDAY COMMAND NETWORK · SIGNAL READY").font(.system(size: 9, weight: .bold, design: .rounded)).tracking(1.1).foregroundStyle(.white.opacity(0.5))
                    }
                    .position(x: width * 0.34, y: height * 0.82)
                    VStack(alignment: .trailing, spacing: 5) {
                        Text("01  PROJECTS").foregroundStyle(.white.opacity(active == 0 ? 0.88 : 0.33))
                        Text("02  WEATHER").foregroundStyle(.white.opacity(active == 1 ? 0.88 : 0.33))
                        Text("03  CALENDAR").foregroundStyle(.white.opacity(active == 2 ? 0.88 : 0.33))
                        Text("04  CAPTAIN'S LOG").foregroundStyle(.white.opacity(active == 3 ? 0.88 : 0.33))
                    }
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .position(x: width * 0.84, y: height * 0.76)
                }
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    guard case .active(let location) = phase else { return }
                    let raw = atan2(location.y - center.y, location.x - center.x) * 180 / .pi + 90
                    let normalized = (raw + 360).truncatingRemainder(dividingBy: 360)
                    angle = normalized - 90
                    active = Int(((normalized + 36) / 72).rounded(.down)) % readings.count
                }
                .animation(.easeOut(duration: 0.12), value: angle)
            }
            .overlay(alignment: .top) {
                VStack(spacing: 7) {
                    Text("MONDAY COMMAND CENTER").font(.system(size: 10, weight: .bold, design: .rounded)).tracking(2.4).foregroundStyle(DashboardPalette.accent)
                    Text("Command Radar").font(.system(size: 30, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                    Text("Move through the dial. The wedge drives the angled readout.").font(.system(size: 13)).foregroundStyle(.white.opacity(0.52))
                }
                .padding(.top, 28)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await projects.reload()
            if !weatherLocation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                await weather.refresh(for: weatherLocation)
            }
        }
    }

}

#endif

private struct CommandDeckWeatherBackdrop: View {
    let snapshot: WeatherSnapshot?

    private var tint: Color {
        guard let snapshot else { return DashboardPalette.accent }
        switch snapshot.weatherCode {
        case 61...67, 80...82, 95...99: return Color(red: 0.34, green: 0.56, blue: 0.82)
        case 71...77, 85, 86: return Color(red: 0.63, green: 0.78, blue: 0.90)
        case 0: return snapshot.isDaylight ? Color(red: 0.95, green: 0.67, blue: 0.28) : Color(red: 0.30, green: 0.45, blue: 0.75)
        default: return DashboardPalette.accent
        }
    }

    var body: some View {
        ZStack {
            if let image = WeatherArtResource.image(for: snapshot?.artKey ?? "partly_cloudy_day") {
                GeometryReader { proxy in
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .opacity(snapshot == nil ? 0.10 : 0.36)
                }
            }
            LinearGradient(colors: [DashboardPalette.canvas.opacity(0.84), tint.opacity(0.25), DashboardPalette.canvas.opacity(0.93)], startPoint: .topLeading, endPoint: .bottomTrailing)
            LinearGradient(colors: [.black.opacity(0.05), DashboardPalette.canvas.opacity(0.48)], startPoint: .top, endPoint: .bottom)
        }
    }
}

private struct AmbientWeatherStatus: View {
    let snapshot: WeatherSnapshot?
    let configured: Bool

    var body: some View {
        VStack(alignment: .trailing, spacing: 5) {
            if let snapshot {
                Label("LIVE WEATHER", systemImage: snapshot.isDaylight ? "cloud.sun.fill" : "cloud.moon.fill")
                    .font(.system(size: 9, weight: .bold, design: .rounded)).tracking(1.1).foregroundStyle(.white.opacity(0.58))
                Text("\(snapshot.temperature.formatted(.number.precision(.fractionLength(0))))°F · \(snapshot.condition)")
                    .font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.90))
                Text(snapshot.place).font(.system(size: 10)).foregroundStyle(.white.opacity(0.52))
            } else {
                Label(configured ? "WEATHER UNAVAILABLE" : "WEATHER OFF", systemImage: "cloud")
                    .font(.system(size: 9, weight: .bold, design: .rounded)).tracking(1.1).foregroundStyle(.white.opacity(0.48))
                Text(configured ? "Refresh to retry" : "Set an address in Settings")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.52))
            }
        }
        .multilineTextAlignment(.trailing)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.10), lineWidth: 1))
    }
}

private struct CommandDeckPanel<Content: View>: View {
    let eyebrow: String
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(eyebrow).font(.system(size: 9, weight: .bold, design: .rounded)).tracking(1.15).foregroundStyle(.white.opacity(0.48))
                    Text(title).font(.system(size: 17, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                }
                Spacer()
                Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(DashboardPalette.accent)
            }
            content
        }
        .frame(maxWidth: .infinity, minHeight: 178, alignment: .topLeading)
        .padding(18)
        .background(.black.opacity(0.20), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.11), lineWidth: 1))
    }
}

private struct CommandDeckLines: View {
    let items: [String]
    let empty: String

    var body: some View {
        if items.isEmpty {
            Text(empty).font(.system(size: 12)).foregroundStyle(.white.opacity(0.56)).fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1)").font(.system(size: 9, weight: .black, design: .rounded)).foregroundStyle(DashboardPalette.accent).frame(width: 14, alignment: .leading)
                        Text(item).font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.83)).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

private struct CommandDeckContextBar: View {
    @ObservedObject var calendar: CalendarStore
    let planner: DailyPlannerPlan?

    var body: some View {
        HStack(spacing: 14) {
            Label(nextCalendarText, systemImage: "calendar")
            Divider().overlay(.white.opacity(0.16))
            Label(planner == nil ? "Planner brief awaiting refresh" : "Planner prepared \(planner!.generatedAt.formatted(date: .omitted, time: .shortened))", systemImage: "clock")
            Divider().overlay(.white.opacity(0.16))
            Label("Evidence and judgment remain distinct", systemImage: "checkmark.shield")
        }
        .font(.system(size: 10, weight: .medium, design: .rounded))
        .foregroundStyle(.white.opacity(0.58))
        .lineLimit(1)
        .padding(.horizontal, 13).padding(.vertical, 10)
        .background(.black.opacity(0.16), in: Capsule())
    }

    private var nextCalendarText: String {
        if case .unavailable = calendar.state { return "Calendar coverage is unknown or unavailable" }
        if case .notConnected = calendar.state { return "Calendar source is not connected" }
        if case .loading = calendar.state { return "Refreshing Calendar source" }
        guard let next = calendar.events.first else { return "Available Calendar source returned no events" }
        return "Scheduled: \(next.timeLabel) · \(next.title)"
    }
}

private struct DaySignalsCard: View {
    let projects: [Project]
    let isLoading: Bool

    private var attention: [Project] {
        projects.filter { $0.health == "intervention" || $0.health == "at-risk" || $0.health == "watch" }
    }

    var body: some View {
        CommandCard(eyebrow: "OPERATING SIGNAL", title: "What wants attention", icon: "scope") {
            if isLoading && projects.isEmpty {
                ProgressView().tint(DashboardPalette.accent).frame(maxWidth: .infinity, minHeight: 110)
            } else if projects.isEmpty {
                Text("No project data has been loaded yet.").foregroundStyle(.white.opacity(0.56))
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(attention.count)").font(.system(size: 38, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    Text(attention.count == 1 ? "project needs a closer look" : "projects need a closer look")
                        .font(.system(size: 13)).foregroundStyle(.white.opacity(0.56))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Divider().overlay(.white.opacity(0.10))
                ForEach(attention.prefix(2)) { project in
                    HStack(spacing: 8) {
                        Circle().fill(project.healthColor).frame(width: 7, height: 7)
                        Text(project.title).lineLimit(1).foregroundStyle(.white.opacity(0.84))
                        Spacer()
                        Text(project.healthLabel).font(.system(size: 10, weight: .semibold)).foregroundStyle(project.healthColor)
                    }
                    .font(.system(size: 12))
                }
                Text("Based on recorded project health—not an inferred priority list.")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.38))
                    .padding(.top, 2)
            }
        }
    }
}

private struct WeatherCard: View {
    @ObservedObject var store: WeatherStore
    @Binding var location: String
    @State private var draft = ""

    var body: some View {
        CommandCard(eyebrow: "WEATHER", title: store.snapshot?.place ?? "Set your weather location", icon: "cloud.sun.fill") {
            if let snapshot = store.snapshot {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(snapshot.temperature, format: .number.precision(.fractionLength(0)))°F")
                            .font(.system(size: 36, weight: .bold, design: .rounded)).foregroundStyle(.white)
                        Text(snapshot.condition)
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(DashboardPalette.accent)
                        Text("Feels like \(snapshot.apparentTemperature, format: .number.precision(.fractionLength(0)))°F · wind \(snapshot.windSpeed, format: .number.precision(.fractionLength(0))) mph")
                            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
                    }
                    Spacer()
                    WeatherArtwork(key: snapshot.artKey)
                        .frame(width: 104, height: 92)
                }
                HStack(spacing: 7) {
                    Image(systemName: "dot.radiowaves.left.and.right").font(.system(size: 10)).foregroundStyle(DashboardPalette.green)
                    Text("Live conditions from Open-Meteo · refreshed \(snapshot.updatedAt.formatted(date: .omitted, time: .shortened))")
                }
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.38))
            } else {
                HStack(spacing: 12) {
                    WeatherArtwork(key: "partly_cloudy_day", dimmed: true)
                        .frame(width: 88, height: 72)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("No location is assumed.").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.76))
                        Text("Add a city when you want a live weather signal. The illustration stays inactive until then.")
                            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.50))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            HStack(spacing: 8) {
                TextField("City or region", text: $draft)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10).padding(.vertical, 9)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(.white.opacity(0.10), lineWidth: 1))
                    .onSubmit { refresh() }
                    .onAppear { draft = location }
                Button(store.loading ? "Loading" : "Update") { refresh() }
                    .buttonStyle(CommandButtonStyle(prominent: true))
                    .disabled(store.loading || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let error = store.error {
                Text(error).font(.system(size: 10)).foregroundStyle(DashboardPalette.amber)
            }
        }
        .task {
            guard store.snapshot == nil, !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            draft = location
            await store.refresh(for: location)
        }
    }

    private func refresh() {
        let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        location = value
        Task { await store.refresh(for: value) }
    }
}

private struct CalendarSignalsCard: View {
    @ObservedObject var store: CalendarStore

    var body: some View {
        CommandCard(eyebrow: "DAY SIGNALS", title: "Today's calendar", icon: "calendar") {
            switch store.state {
            case .notConnected:
                Text("Choose the Planner shared-plan JSON in Settings. Codex owns the calendar connection; Command Center reads only today’s planned titles and times.")
                    .font(.system(size: 13)).foregroundStyle(.white.opacity(0.56))
                    .fixedSize(horizontal: false, vertical: true)
                Text("Settings → Planner shared plan")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(DashboardPalette.accent)
            case .loading:
                ProgressView("Loading shared plan…").tint(DashboardPalette.accent).foregroundStyle(.white.opacity(0.65))
                    .frame(maxWidth: .infinity, minHeight: 92)
            case .connected:
                if store.events.isEmpty {
                    Text("No events are recorded for the rest of today.").font(.system(size: 13)).foregroundStyle(.white.opacity(0.56))
                } else {
                    ForEach(store.events.prefix(3)) { event in
                        HStack(alignment: .top, spacing: 8) {
                            Text(event.timeLabel).font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(DashboardPalette.accent).frame(width: 48, alignment: .leading)
                            Text(event.title).font(.system(size: 12)).foregroundStyle(.white.opacity(0.84)).lineLimit(2)
                        }
                    }
                }
                HStack {
                    Text("Only today’s planned titles and times are shown here.").font(.system(size: 10)).foregroundStyle(.white.opacity(0.38))
                    Spacer()
                    Button("Refresh") { Task { await store.reloadToday() } }
                        .buttonStyle(.plain).font(.system(size: 10, weight: .semibold)).foregroundStyle(DashboardPalette.accent)
                }
            case .unavailable(let message):
                UnavailableInline(message: message)
            }
        }
    }
}

private struct ConversationHandoffCard: View {
    @State private var draft = ""
    @State private var copied = false

    var body: some View {
        CommandCard(eyebrow: "CONVERSATION", title: "Bring MONDAY the real thing", icon: "bubble.left.and.bubble.right.fill") {
            Text("Capture the thought, question, or decision you want to carry into the voice/chat conversation.")
                .font(.system(size: 13)).foregroundStyle(.white.opacity(0.56))
                .fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $draft)
                .font(.system(size: 12))
                .scrollContentBackground(.hidden)
                .frame(height: 68)
                .padding(7)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(.white.opacity(0.10), lineWidth: 1))
            HStack {
                Button(copied ? "Copied for MONDAY" : "Copy for MONDAY") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(draft, forType: .string)
                    copied = true
                }
                .buttonStyle(CommandButtonStyle(prominent: true))
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Spacer()
                Text("Handoff only — no hidden chat bridge.")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.38))
            }
        }
    }
}

private struct ProjectContextCard: View {
    let project: Project

    var body: some View {
        CommandCard(eyebrow: project.domainLabel, title: project.title, icon: project.healthIcon) {
            HStack(spacing: 8) {
                HealthPill(label: project.healthLabel, color: project.healthColor)
                if let stage = project.stage { Text(stage.replacingOccurrences(of: "-", with: " ")).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55)).lineLimit(1) }
                Spacer()
                if let priority = project.priority { Text("P\(priority)").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.44)) }
            }
            Divider().overlay(.white.opacity(0.10))
            DetailRow(label: "NEXT", value: project.nextAction ?? project.milestone ?? "No next action recorded")
            DetailRow(label: "GATE", value: project.gateSummary)
            if let updatedAt = project.updatedAt { Text("Registry updated \(updatedAt.formatted(date: .abbreviated, time: .omitted))").font(.system(size: 10)).foregroundStyle(.white.opacity(0.36)) }
        }
    }
}

private struct CommandCard<Content: View>: View {
    let eyebrow: String
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(eyebrow.uppercased()).font(.system(size: 9, weight: .bold, design: .rounded)).tracking(1.2).foregroundStyle(.white.opacity(0.43))
                    Text(title).font(.system(size: 18, weight: .semibold, design: .rounded)).foregroundStyle(.white).lineLimit(2)
                }
                Spacer()
                Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(DashboardPalette.accent)
                    .frame(width: 30, height: 30).background(DashboardPalette.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
            }
            content
        }
        .padding(17)
        .frame(maxWidth: .infinity, minHeight: 218, alignment: .topLeading)
        .background(DashboardPalette.card, in: RoundedRectangle(cornerRadius: 17))
        .overlay(RoundedRectangle(cornerRadius: 17).stroke(.white.opacity(0.10), lineWidth: 1))
        .shadow(color: .black.opacity(0.20), radius: 20, y: 9)
    }
}

private struct CommandButtonStyle: ButtonStyle {
    let prominent: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(prominent ? DashboardPalette.canvas : .white.opacity(0.88))
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(prominent ? DashboardPalette.accent.opacity(configuration.isPressed ? 0.75 : 1) : .white.opacity(configuration.isPressed ? 0.12 : 0.08), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(prominent ? .clear : .white.opacity(0.12), lineWidth: 1))
    }
}

private struct UnavailableCard: View {
    let title: String, message: String, icon: String
    var body: some View {
        CommandCard(eyebrow: "UNAVAILABLE", title: title, icon: icon) {
            Text(message).font(.system(size: 13)).foregroundStyle(.white.opacity(0.60))
            Text("No fallback data is shown.").font(.system(size: 11)).foregroundStyle(.white.opacity(0.38))
        }
    }
}

private struct UnavailableInline: View {
    let message: String
    var body: some View { Text(message).font(.system(size: 12)).foregroundStyle(DashboardPalette.amber).fixedSize(horizontal: false, vertical: true) }
}

private struct HealthPill: View {
    let label: String, color: Color
    var body: some View {
        Text(label.uppercased()).font(.system(size: 9, weight: .bold, design: .rounded)).tracking(0.7).foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 4).background(color.opacity(0.14), in: Capsule())
    }
}

private struct DetailRow: View {
    let label: String, value: String
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Text(label).font(.system(size: 9, weight: .bold, design: .rounded)).tracking(0.7).foregroundStyle(.white.opacity(0.38)).frame(width: 36, alignment: .leading)
            Text(value).font(.system(size: 12)).foregroundStyle(.white.opacity(0.72)).lineLimit(2)
        }
    }
}

private struct Legend: View {
    let label: String, color: Color
    var body: some View { HStack(spacing: 5) { Circle().fill(color).frame(width: 7, height: 7); Text(label).font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.48)) } }
}

private struct WeatherArtwork: View {
    let key: String
    var dimmed = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(DashboardPalette.accent.opacity(dimmed ? 0.05 : 0.10))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(DashboardPalette.accent.opacity(dimmed ? 0.12 : 0.22), lineWidth: 1))
            if let image = NSImage(named: key) ?? WeatherArtResource.image(for: key) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(7)
                    .opacity(dimmed ? 0.40 : 1)
            } else {
                Image(systemName: "cloud.sun.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(DashboardPalette.accent.opacity(0.65))
            }
        }
        .accessibilityLabel("Weather illustration")
    }

}

private enum WeatherArtResource {
    static func image(for key: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: key, withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }
}

private struct VaultEntry: Identifiable {
    let id: String
    let title: String
    let body: String
    let modified: Date
}

@MainActor private enum VaultShelf {
    static func entries(at root: URL?) -> [VaultEntry] {
        guard let root,
              let urls = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else { return [] }
        return urls.compactMap { url in
            guard url.pathExtension.lowercased() == "md", url.lastPathComponent != "README.md", let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            let cleaned = removeFrontMatter(from: text).trimmingCharacters(in: .whitespacesAndNewlines)
            let heading = cleaned.split(separator: "\n").first(where: { $0.hasPrefix("#") })?.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespaces) ?? url.deletingPathExtension().lastPathComponent
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return VaultEntry(id: url.path, title: heading, body: cleaned, modified: date)
        }
        .sorted { $0.modified > $1.modified }
    }

    private static func removeFrontMatter(from text: String) -> String {
        guard text.hasPrefix("---"), let end = text.range(of: "\n---", options: [], range: text.index(text.startIndex, offsetBy: 3)..<text.endIndex) else { return text }
        return String(text[end.upperBound...])
    }
}

private struct VaultTomeRoom: View {
    let title: String
    let subtitle: String
    let rootURL: URL?
    let emptyTitle: String
    @State private var entries: [VaultEntry] = []
    @State private var selectedID: String?

    init(title: String, subtitle: String, rootURL: URL?, emptyTitle: String) {
        self.title = title
        self.subtitle = subtitle
        self.rootURL = rootURL
        self.emptyTitle = emptyTitle
    }

    private var selected: VaultEntry? { entries.first { $0.id == selectedID } ?? entries.first }

    var body: some View {
        ZStack {
            TomePalette.background.ignoresSafeArea()
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 14) {
                    Label(title.uppercased(), systemImage: "book.closed.fill").font(.system(size: 10, weight: .bold, design: .rounded)).tracking(1.2).foregroundStyle(TomePalette.accent)
                    Text(subtitle).font(.system(size: 13)).foregroundStyle(.white.opacity(0.56)).fixedSize(horizontal: false, vertical: true)
                    if entries.isEmpty {
                        Text(emptyTitle).font(.system(size: 13)).foregroundStyle(.white.opacity(0.55))
                    } else {
                        ScrollView { VStack(alignment: .leading, spacing: 6) { ForEach(entries) { entry in
                            Button { selectedID = entry.id } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(entry.title).lineLimit(2).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(selected?.id == entry.id ? 0.96 : 0.70))
                                    Text(entry.modified.formatted(date: .abbreviated, time: .omitted)).font(.system(size: 10)).foregroundStyle(.white.opacity(0.42))
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(10).background(selected?.id == entry.id ? TomePalette.accent.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 9))
                            }.buttonStyle(.plain)
                        } } }
                    }
                    Spacer()
                    Text("Read-only from MONDAY Vault").font(.system(size: 10)).foregroundStyle(.white.opacity(0.34))
                }
                .frame(width: 276).padding(22).background(TomePalette.sidebar)
                TomePage(entry: selected, emptyTitle: emptyTitle)
            }
        }
        .task(id: rootURL?.path) { entries = VaultShelf.entries(at: rootURL); selectedID = entries.first?.id }
    }
}

private struct TomePage: View {
    let entry: VaultEntry?
    let emptyTitle: String
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let entry {
                    Text(entry.title).font(.system(size: 31, weight: .semibold, design: .serif)).foregroundStyle(TomePalette.primary)
                    Text(entry.modified.formatted(date: .long, time: .omitted)).font(.system(size: 12, weight: .medium)).foregroundStyle(TomePalette.muted)
                    TomeMarkdown(source: entry.body, suppressFirstTitle: true)
                } else {
                    Text(emptyTitle).font(.system(size: 28, weight: .semibold, design: .serif)).foregroundStyle(TomePalette.primary)
                    Text("When an entry exists in the connected vault, it will appear here as a page to return to—not a scorecard to complete.").font(.system(size: 16, design: .serif)).foregroundStyle(TomePalette.secondary)
                }
            }
            .padding(52).frame(maxWidth: 860, minHeight: 720, alignment: .topLeading)
            .background(TomePalette.page, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.38), radius: 28, y: 14)
            .padding(46)
        }
    }
}

private struct TomeMarkdown: View {
    private struct Block: Identifiable {
        enum Kind { case heading(Int), paragraph, quote, bullet(checked: Bool?), code, rule }
        let id = UUID()
        let kind: Kind
        let text: String
    }

    let source: String
    let suppressFirstTitle: Bool

    private var blocks: [Block] { Self.parse(source, suppressFirstTitle: suppressFirstTitle) }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            ForEach(blocks) { block in
                switch block.kind {
                case .heading(let level):
                    MarkdownInline(block.text)
                        .font(.system(size: level == 1 ? 27 : level == 2 ? 21 : 18, weight: .semibold, design: .serif))
                        .foregroundStyle(TomePalette.primary)
                        .padding(.top, level == 1 ? 8 : 16)
                case .paragraph:
                    MarkdownInline(block.text)
                        .font(.system(size: 17, design: .serif))
                        .foregroundStyle(TomePalette.primary)
                        .lineSpacing(7)
                        .textSelection(.enabled)
                case .quote:
                    HStack(alignment: .top, spacing: 13) {
                        Capsule().fill(TomePalette.accent).frame(width: 3)
                        MarkdownInline(block.text)
                            .font(.system(size: 17, design: .serif)).italic()
                            .foregroundStyle(TomePalette.secondary)
                            .lineSpacing(6)
                    }
                    .padding(.vertical, 7)
                case .bullet(let checked):
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: checked == true ? "checkmark.circle.fill" : checked == false ? "circle" : "smallcircle.fill")
                            .font(.system(size: checked == nil ? 7 : 14, weight: .semibold))
                            .foregroundStyle(TomePalette.accent)
                            .frame(width: 15)
                        MarkdownInline(block.text)
                            .font(.system(size: 16, design: .serif))
                            .foregroundStyle(TomePalette.primary)
                            .lineSpacing(5)
                    }
                case .code:
                    Text(block.text)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(TomePalette.secondary)
                        .textSelection(.enabled)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 8))
                case .rule:
                    Color.clear.frame(height: 5)
                }
            }
        }
    }

    private static func parse(_ source: String, suppressFirstTitle: Bool) -> [Block] {
        let lines = source.components(separatedBy: .newlines)
        var result: [Block] = []
        var index = 0
        var shouldSuppressTitle = suppressFirstTitle

        func heading(_ line: String) -> (level: Int, text: String)? {
            let level = line.prefix(while: { $0 == "#" }).count
            guard level > 0, line.dropFirst(level).first == " " else { return nil }
            return (level, String(line.dropFirst(level)).trimmingCharacters(in: .whitespaces))
        }
        func startsSpecial(_ line: String) -> Bool {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return heading(trimmed) != nil || trimmed == "---" || trimmed.hasPrefix(">") || trimmed.hasPrefix("```") || trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") || trimmed.range(of: "^[0-9]+\\\\.\\\\s+", options: .regularExpression) != nil
        }

        while index < lines.count {
            let raw = lines[index]
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { index += 1; continue }
            if let found = heading(line) {
                if !shouldSuppressTitle || found.level != 1 { result.append(Block(kind: .heading(found.level), text: found.text)) }
                shouldSuppressTitle = false
                index += 1
            } else if line == "---" {
                result.append(Block(kind: .rule, text: "")); index += 1
            } else if line.hasPrefix("```") {
                index += 1
                var code: [String] = []
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") { code.append(lines[index]); index += 1 }
                if index < lines.count { index += 1 }
                result.append(Block(kind: .code, text: code.joined(separator: "\\n")))
            } else if line.hasPrefix(">") {
                result.append(Block(kind: .quote, text: String(line.dropFirst()).trimmingCharacters(in: .whitespaces))); index += 1
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
                var text = String(line.dropFirst(2))
                var checked: Bool? = nil
                if text.hasPrefix("[x] ") || text.hasPrefix("[X] ") { checked = true; text = String(text.dropFirst(4)) }
                if text.hasPrefix("[ ] ") { checked = false; text = String(text.dropFirst(4)) }
                result.append(Block(kind: .bullet(checked: checked), text: text)); index += 1
            } else {
                var paragraph = [line]
                index += 1
                while index < lines.count {
                    let next = lines[index].trimmingCharacters(in: .whitespaces)
                    if next.isEmpty || startsSpecial(next) { break }
                    paragraph.append(next); index += 1
                }
                result.append(Block(kind: .paragraph, text: paragraph.joined(separator: " ")))
            }
        }
        return result
    }
}

private struct MarkdownInline: View {
    let source: String
    init(_ source: String) { self.source = source }
    var body: some View {
        if let markdown = try? AttributedString(markdown: source, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            Text(markdown)
        } else {
            Text(source)
        }
    }
}

private enum TomePalette {
    static let background = LinearGradient(colors: [Color(red: 0.006, green: 0.014, blue: 0.028), Color(red: 0.012, green: 0.037, blue: 0.064)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let sidebar = Color(red: 0.012, green: 0.030, blue: 0.053)
    static let page = Color(red: 0.018, green: 0.052, blue: 0.084)
    static let primary = Color(red: 0.88, green: 0.95, blue: 1.0)
    static let secondary = Color(red: 0.68, green: 0.80, blue: 0.89)
    static let muted = Color(red: 0.42, green: 0.63, blue: 0.74)
    static let accent = Color(red: 0.38, green: 0.81, blue: 0.94)
}

private enum PlannerArchive {
    static let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/monday-planner/history", isDirectory: true)
    static func url(for date: String) -> URL { root.appendingPathComponent("\(date).json") }
    static func savedDates(currentPlanURL: URL?) -> [String] {
        let archived = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        var dates = Set(archived.compactMap { url -> String? in
            guard url.pathExtension == "json" else { return nil }
            return String(url.deletingPathExtension().lastPathComponent)
        })
        if let currentPlanURL, let current = try? PlannerFeedReader.load(from: currentPlanURL) { dates.insert(current.date) }
        return dates.sorted(by: >)
    }
}

@MainActor
private final class DailyPlannerFeed: ObservableObject {
    @Published private(set) var plan: DailyPlannerPlan?
    @Published private(set) var message = "Reading the MONDAY plan…"

    func refresh(for requestedDate: String) async {
        plan = nil
        guard let url = CommandCenterPairing.shared.plannerFeedURL else {
            message = "Choose the Planner shared-plan JSON in Settings. The Codex Planner skill writes it, and Command Center reads it without calendar credentials."
            return
        }
        do {
            let candidate = try PlannerFeedReader.load(from: url)
            let source = candidate.date == requestedDate ? url : PlannerArchive.url(for: requestedDate)
            let selected = source == url ? candidate : try PlannerFeedReader.load(from: source)
            let today = Self.localDateKey(for: .now, timezone: selected.timezone)
            switch selected.validation(expectedDate: requestedDate, enforceFreshness: requestedDate == today) {
            case .current:
                break
            case .unsupportedSchema(let schema):
                throw PlannerContractError.unsupportedSchema(schema)
            case .wrongDate(let expected, let actual):
                throw PlannerContractError.wrongDate(expected: expected, actual: actual)
            case .expired(let date):
                throw PlannerContractError.expired(date)
            case .missingPlanIdentifier:
                throw PlannerContractError.missingPlanIdentifier
            }
            plan = selected
            if requestedDate == today,
               let readback = selected.readback(
                consumer: "MONDAY Command Center",
                appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
               ) {
                try CommandCenterReadbackWriter.write(readback)
                message = "Display verified for plan \(readback.planID)."
            } else {
                message = selected.schemaVersion == nil ? "Legacy plan displayed without readback verification." : ""
            }
        } catch {
            message = (error as? LocalizedError)?.errorDescription
                ?? "No saved plan is available for \(requestedDate). MONDAY will show only dates archived by the planning pipeline."
        }
    }

    private static func localDateKey(for date: Date, timezone: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: timezone) ?? .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

private struct PlannerRoom: View {
    @StateObject private var planner = DailyPlannerFeed()
    @StateObject private var meetingNotes = MeetingNoteIndex()
    @AppStorage("dailyFocus") private var dailyFocus = ""
    @State private var selectedDate = Calendar.current.startOfDay(for: .now)
    @State private var followsToday = true
    @State private var showingCalendar = false
    @State private var selectedNote: MeetingNote?
    @State private var isRefreshing = false
    private var dateKey: String { Self.dateFormatter.string(from: selectedDate) }
    private var displayDate: String { planner.plan?.date ?? dateKey }
    private static let dateFormatter: DateFormatter = { let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(identifier: "America/New_York"); formatter.dateFormat = "yyyy-MM-dd"; return formatter }()
    private static let titleFormatter: DateFormatter = { let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian); formatter.locale = Locale(identifier: "en_US"); formatter.timeZone = TimeZone(identifier: "America/New_York"); formatter.dateFormat = "EEEE, MMMM d, yyyy"; return formatter }()
    var body: some View {
        ZStack {
            PlannerPaper.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    HStack(alignment: .top, spacing: 22) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("DAILY PLANNING PAGE").font(.system(size: 11, weight: .black, design: .rounded)).tracking(1.5).foregroundStyle(PlannerPaper.ink.opacity(0.72))
                            HStack(spacing: 12) {
                                Text(Self.titleFormatter.string(from: selectedDate)).font(.system(size: 29, weight: .semibold, design: .serif)).foregroundStyle(PlannerPaper.ink)
                                Button { showingCalendar = true } label: {
                                    Label("Calendar", systemImage: "calendar")
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                        .foregroundStyle(PlannerPaper.ink)
                                        .padding(.horizontal, 11)
                                        .padding(.vertical, 8)
                                        .background(PlannerPaper.ink.opacity(0.12), in: Capsule())
                                        .overlay(Capsule().stroke(PlannerPaper.ink.opacity(0.34), lineWidth: 1))
                                }
                                .buttonStyle(.plain).help("Open saved calendar")
                                Button { Task { await refreshPage() } } label: {
                                    Label(isRefreshing ? "Refreshing" : "Refresh", systemImage: "arrow.clockwise")
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                        .foregroundStyle(PlannerPaper.ink)
                                        .padding(.horizontal, 11)
                                        .padding(.vertical, 8)
                                        .background(PlannerPaper.ink.opacity(0.12), in: Capsule())
                                        .overlay(Capsule().stroke(PlannerPaper.ink.opacity(0.34), lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                                .disabled(isRefreshing)
                                .help("Refresh the saved planner and meeting notes")
                            }
                            if let plan = planner.plan {
                                Text("Prepared \(plan.generatedAt.formatted(date: .omitted, time: .shortened)) · \(plan.sourceSummary)\(plan.planID.map { " · \($0)" } ?? "")")
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                                    .foregroundStyle(PlannerPaper.ink.opacity(0.58))
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 7) {
                            Text("PRIMARY FOCUS").font(.system(size: 10, weight: .bold, design: .rounded)).tracking(1.1).foregroundStyle(PlannerPaper.ink.opacity(0.64))
                            if let focus = planner.plan?.primaryFocus {
                                Text(focus).font(.system(size: 16, design: .serif)).foregroundStyle(PlannerPaper.ink).multilineTextAlignment(.trailing).frame(width: 315, alignment: .trailing)
                            } else {
                                TextField("Name what matters most today", text: $dailyFocus).textFieldStyle(.plain).font(.system(size: 16, design: .serif)).foregroundStyle(PlannerPaper.ink).frame(width: 315)
                            }
                        }
                    }
                    .padding(30)
                    HStack(alignment: .top, spacing: 0) {
                        MacPlannerSchedule(plan: planner.plan, selectedDate: displayDate, noteIndex: meetingNotes) { selectedNote = $0 }.frame(maxWidth: .infinity, alignment: .topLeading)
                        MacPlannerTaskList(plan: planner.plan).frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    HStack(alignment: .top, spacing: 0) {
                        MacPlannerNotes(plan: planner.plan).frame(maxWidth: .infinity, alignment: .topLeading)
                        MacPlannerCompass(plan: planner.plan).frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    MacPlannerCommandBrief(plan: planner.plan)
                    Text(planner.plan == nil ? planner.message : "FRANKLIN-STYLE DAILY PLANNING PAGE · PREPARED BY MONDAY · \(planner.message.isEmpty ? "DISPLAYED FROM A VERSIONED PROJECTION" : planner.message.uppercased())").font(.system(size: 9, weight: .bold, design: .rounded)).tracking(0.9).foregroundStyle(PlannerPaper.ink.opacity(0.48)).padding(.vertical, 15)
                }
                .background(PlannerPaper.page, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(0.48), radius: 26, y: 13)
                .padding(42)
                .frame(maxWidth: 1160)
            }
        }
        .sheet(isPresented: $showingCalendar) {
            SavedCalendarSheet(
                selectedDate: selectedDate,
                savedDates: PlannerArchive.savedDates(currentPlanURL: CommandCenterPairing.shared.plannerFeedURL)
            ) { openedDate in
                selectedDate = openedDate
                followsToday = Self.dateFormatter.string(from: openedDate) == Self.dateFormatter.string(from: .now)
            }
        }
        .sheet(item: $selectedNote) { MeetingNoteSheet(note: $0) }
        .task(id: dateKey) {
            while !Task.isCancelled {
                let rolloverDate = PlannerDayRollover.selection(current: selectedDate, now: .now, followsToday: followsToday)
                if rolloverDate != selectedDate {
                    selectedDate = rolloverDate
                    continue
                }
                await refreshPage()
                do { try await Task.sleep(for: .seconds(60)) }
                catch { return }
            }
        }
    }

    private func refreshPage() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await planner.refresh(for: dateKey)
        meetingNotes.reload()
    }
}

private struct MacPlannerSchedule: View {
    let plan: DailyPlannerPlan?
    let selectedDate: String
    @ObservedObject var noteIndex: MeetingNoteIndex
    let openNote: (MeetingNote) -> Void
    @State private var unmappedTitle: String?
    private var schedule: [PlannerScheduleItem] { (plan?.schedule ?? []).sorted { $0.time < $1.time } }
    private var calendarSource: PlannerSource? { plan?.sources.first { $0.kind == "calendar" } }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MacPlannerSectionTitle(title: "SCHEDULE", detail: "CALENDAR: \(calendarSource?.status.uppercased() ?? "UNKNOWN")")
            Text(plan == nil ? "No normalized MONDAY plan is available yet." : "Fixed commitments and intentional focus blocks, rendered in \(plan?.timezone ?? "local") time.")
                .font(.system(size: 11, design: .serif)).foregroundStyle(PlannerPaper.ink.opacity(0.65)).padding(.horizontal, 18).padding(.vertical, 11)
            if schedule.isEmpty {
                Text(emptyScheduleMessage).font(.system(size: 12, design: .serif)).foregroundStyle(PlannerPaper.ink.opacity(0.62)).padding(.horizontal, 18).padding(.bottom, 18)
            } else {
                ForEach(Array(schedule.enumerated()), id: \.offset) { _, item in
                    let eventColor = PlannerEventColor.forTitle(item.title)
                    let note = noteIndex.note(for: selectedDate, title: item.title)
                    Button { if let note { openNote(note) } else { unmappedTitle = item.title } } label: {
                        HStack(alignment: .center, spacing: 9) {
                            Capsule().fill(eventColor).frame(width: 5)
                            Text("\(displayTime(item.time))–\(displayTime(item.end))").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(eventColor.opacity(0.95)).frame(width: 106, alignment: .trailing)
                            Text(item.title).font(.system(size: 12, weight: .medium, design: .serif)).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 6)
                            Image(systemName: note == nil ? "doc.badge.questionmark" : "doc.text.fill").font(.system(size: 11)).foregroundStyle(note == nil ? PlannerPaper.ink.opacity(0.38) : eventColor)
                        }
                        .foregroundStyle(PlannerPaper.ink).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 6)
                        .background(eventColor.opacity(0.105), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain).padding(.horizontal, 12).padding(.vertical, 2)
                }
                .padding(.bottom, 12)
            }
        }
        .alert("No mapped meeting note", isPresented: Binding(get: { unmappedTitle != nil }, set: { if !$0 { unmappedTitle = nil } })) { Button("OK", role: .cancel) {} } message: { Text("\(unmappedTitle ?? "This meeting") does not have a governed note in Meeting Notes yet.") }
    }

    private var emptyScheduleMessage: String {
        guard let source = calendarSource else {
            return "Calendar coverage is unknown. This is not evidence that the day is clear."
        }
        switch source.status {
        case "available":
            return "The available Calendar source returned no scheduled events for this plan."
        case "partial":
            return "Calendar coverage is partial. Some commitments may be missing. \(source.detail ?? "")"
        case "stale":
            return "Calendar coverage is stale. Refresh the planning pipeline before relying on this schedule."
        case "blocked", "unavailable":
            return "Calendar is \(source.status). This is not evidence that the day is clear. \(source.detail ?? source.error ?? "")"
        default:
            return "Calendar coverage is unknown. This is not evidence that the day is clear. \(source.detail ?? "")"
        }
    }

    private func displayTime(_ time: String) -> String { let pieces = time.split(separator: ":"); guard let hour = Int(pieces[0]), let minute = pieces.last else { return time }; let shown = hour > 12 ? hour - 12 : hour; return "\(shown):\(minute) \(hour >= 12 ? "PM" : "AM")" }
}

private struct SavedCalendarSheet: View {
    let selectedDate: Date
    let savedDates: [String]
    let openDate: (Date) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var candidate = Calendar.current.startOfDay(for: .now)
    private static let formatter: DateFormatter = { let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(identifier: "America/New_York"); formatter.dateFormat = "yyyy-MM-dd"; return formatter }()
    private var candidateKey: String { Self.formatter.string(from: candidate) }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("SAVED CALENDAR", systemImage: "calendar").font(.system(size: 12, weight: .black, design: .rounded)).tracking(1.1)
            Text("Move through days, months, or years. Only dates with a saved MONDAY plan can be opened.").foregroundStyle(.secondary)
            DatePicker("Calendar date", selection: $candidate, displayedComponents: .date).datePickerStyle(.graphical)
            if savedDates.contains(candidateKey) { Label("A saved plan is available for \(candidateKey).", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
            else { Label("No saved plan exists for \(candidateKey).", systemImage: "questionmark.circle").foregroundStyle(.secondary) }
            Divider()
            Text("RECENTLY SAVED").font(.system(size: 10, weight: .bold, design: .rounded)).tracking(1)
            ScrollView { VStack(alignment: .leading, spacing: 6) { ForEach(savedDates.prefix(20), id: \.self) { date in Button(date) { candidate = Self.formatter.date(from: date) ?? candidate }.buttonStyle(.plain) } } }.frame(maxHeight: 130, alignment: .topLeading)
            HStack { Spacer(); Button("Cancel") { dismiss() }; Button("Open Date") { openDate(candidate); dismiss() }.buttonStyle(.borderedProminent).disabled(!savedDates.contains(candidateKey)) }
        }
        .padding(26).frame(width: 430)
        .onAppear { candidate = selectedDate }
    }
}

private struct MacPlannerTaskList: View {
    let plan: DailyPlannerPlan?
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MacPlannerSectionTitle(title: "PRIORITIZED DAILY TASK LIST", detail: "A / B / C")
            if items.isEmpty {
                Text("No prioritized work has been prepared yet.")
                    .font(.system(size: 12, design: .serif)).foregroundStyle(PlannerPaper.ink.opacity(0.62))
                    .padding(.horizontal, 18).padding(.vertical, 14)
            } else {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: 9) { Text(item.0).font(.system(size: 10, weight: .black, design: .rounded)).foregroundStyle(priorityColor(index)).frame(width: 24); Text(item.1).font(.system(size: 12, design: .serif)).foregroundStyle(PlannerPaper.ink).fixedSize(horizontal: false, vertical: true) }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 8).background(priorityColor(index).opacity(0.11), in: RoundedRectangle(cornerRadius: 7, style: .continuous)).padding(.horizontal, 12).padding(.vertical, 2)
                }
            }
            Spacer(minLength: 14)
        }
    }
    private var items: [(String, String)] { let a = (plan?.priorities.a ?? []).enumerated().map { ("A\($0.offset + 1)", $0.element) }; let b = (plan?.priorities.b ?? []).enumerated().map { ("B\($0.offset + 1)", $0.element) }; let c = (plan?.priorities.c ?? []).enumerated().map { ("C\($0.offset + 1)", $0.element) }; return a + b + c }
    private func priorityColor(_ index: Int) -> Color { let a = plan?.priorities.a.count ?? 0; let b = plan?.priorities.b.count ?? 0; return index < a ? PlannerEventColor.urgent : index < a + b ? PlannerEventColor.forTitle("planning") : PlannerEventColor.forTitle("workout") }
}

private struct MacPlannerNotes: View {
    let plan: DailyPlannerPlan?
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MacPlannerSectionTitle(title: "NOTES & IDEAS", detail: "CAPTURE")
            if let notes = plan?.notes, !notes.isEmpty {
                ForEach(Array(notes.enumerated()), id: \.offset) { _, note in Text(note).font(.system(size: 12, design: .serif)).lineSpacing(4).foregroundStyle(PlannerPaper.ink.opacity(0.86)).padding(.horizontal, 18).padding(.vertical, 9).fixedSize(horizontal: false, vertical: true) }
            } else {
                Text("No notes were prepared for this plan.").font(.system(size: 12, design: .serif)).foregroundStyle(PlannerPaper.ink.opacity(0.62)).padding(.horizontal, 18).padding(.vertical, 14)
            }
            Spacer(minLength: 14)
        }
    }
}

private struct MacPlannerCompass: View {
    let plan: DailyPlannerPlan?
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MacPlannerSectionTitle(title: "DAILY COMPASS", detail: "ROLES / GOALS")
            if let compass = plan?.compass, !compass.isEmpty {
                ForEach(Array(compass.enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading, spacing: 7) { HStack { Text("ROLE").frame(width: 33, alignment: .leading); Text(item.role).font(.system(size: 12, design: .serif)) }; HStack(alignment: .top) { Text("GOAL").frame(width: 33, alignment: .leading); Text(item.goal).font(.system(size: 12, design: .serif)).fixedSize(horizontal: false, vertical: true) } }.font(.system(size: 9, weight: .bold, design: .rounded)).tracking(0.6).foregroundStyle(PlannerPaper.ink.opacity(0.72)).padding(.horizontal, 18).padding(.vertical, 10)
                }
            } else {
                Text("No roles or goals were prepared for this plan.").font(.system(size: 12, design: .serif)).foregroundStyle(PlannerPaper.ink.opacity(0.62)).padding(.horizontal, 18).padding(.vertical, 14)
            }
        }
    }
}

private struct MacPlannerCommandBrief: View {
    let plan: DailyPlannerPlan?
    private var brief: PlannerBrief? { plan?.brief }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MacPlannerSectionTitle(title: "MONDAY COMMAND BRIEF", detail: "EVIDENCE / PULL-FORWARDS / SOURCE HEALTH")
            if let brief {
                HStack(alignment: .top, spacing: 0) {
                    BriefColumn(title: "PULL FORWARDS", items: brief.pullForwards, empty: "No pull-forwards were prepared.")
                    BriefColumn(title: "WATCH", items: brief.risks, empty: "No source or planning risks were reported.")
                    PortfolioColumn(title: "WORK PROJECTS", items: brief.workPortfolio, empty: "No active work-project records were read.")
                }
                if !brief.personalPortfolio.isEmpty {
                    PortfolioColumn(title: "PERSONAL PROJECTS", items: brief.personalPortfolio, empty: "")
                        .padding(.horizontal, 16).padding(.bottom, 12)
                }
                SourceHealthRow(sources: brief.sourceHealth)
            } else {
                Text("The connected plan has not supplied a MONDAY Command Brief yet.")
                    .font(.system(size: 12, design: .serif)).foregroundStyle(PlannerPaper.ink.opacity(0.62))
                    .padding(.horizontal, 18).padding(.vertical, 14)
            }
        }
    }
}

private struct BriefColumn: View {
    let title: String
    let items: [String]
    let empty: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 9, weight: .black, design: .rounded)).tracking(0.8).foregroundStyle(PlannerPaper.ink.opacity(0.58))
            if items.isEmpty {
                Text(empty).font(.system(size: 11, design: .serif)).foregroundStyle(PlannerPaper.ink.opacity(0.6))
            } else {
                ForEach(Array(items.prefix(4).enumerated()), id: \.offset) { _, item in
                    Text(item).font(.system(size: 11, design: .serif)).foregroundStyle(PlannerPaper.ink.opacity(0.9)).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading).padding(16)
    }
}

private struct PortfolioColumn: View {
    let title: String
    let items: [PlannerPortfolioItem]
    let empty: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 9, weight: .black, design: .rounded)).tracking(0.8).foregroundStyle(PlannerPaper.ink.opacity(0.58))
            if items.isEmpty {
                Text(empty).font(.system(size: 11, design: .serif)).foregroundStyle(PlannerPaper.ink.opacity(0.6))
            } else {
                ForEach(Array(items.prefix(4).enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(item.status.uppercased()).font(.system(size: 8, weight: .black, design: .rounded)).foregroundStyle(PlannerEventColor.forTitle(item.status))
                        Text(item.title).font(.system(size: 11, design: .serif)).foregroundStyle(PlannerPaper.ink.opacity(0.9)).lineLimit(1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading).padding(16)
    }
}

private struct SourceHealthRow: View {
    let sources: [PlannerSource]
    var body: some View {
        HStack(spacing: 9) {
            Text("SOURCE HEALTH").font(.system(size: 9, weight: .black, design: .rounded)).tracking(0.8).foregroundStyle(PlannerPaper.ink.opacity(0.58))
            ForEach(Array(sources.prefix(8).enumerated()), id: \.offset) { _, source in
                Text("\(source.name): \(source.status)")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(color(for: source.status))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PlannerPaper.ink.opacity(0.045))
    }

    private func color(for status: String) -> Color {
        switch status {
        case "available": DashboardPalette.green
        case "partial", "stale": DashboardPalette.amber
        case "blocked", "unavailable": DashboardPalette.red
        default: PlannerPaper.ink.opacity(0.58)
        }
    }
}

private extension DailyPlannerPlan {
    var isCurrentForLocalDay: Bool {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: timezone) ?? .current
        formatter.dateFormat = "yyyy-MM-dd"
        return date == formatter.string(from: .now)
    }

    var sourceSummary: String {
        let available = sources.filter { $0.status == "available" }.map(\.name)
        guard !available.isEmpty else { return "No verified sources" }
        let shown = available.prefix(4).joined(separator: " · ")
        return available.count > 4 ? "\(shown) + \(available.count - 4) sources" : shown
    }
}

private struct MacPlannerSectionTitle: View {
    let title: String; let detail: String
    var body: some View { HStack { Text(title).font(.system(size: 11, weight: .black, design: .rounded)).tracking(0.9); Spacer(); Text(detail).font(.system(size: 9, weight: .bold, design: .rounded)).tracking(0.7).foregroundStyle(PlannerPaper.ink.opacity(0.54)) }.foregroundStyle(PlannerPaper.ink).padding(.horizontal, 18).padding(.vertical, 13).background(PlannerPaper.ink.opacity(0.07)) }
}

private enum PlannerPaper {
    static let ink = Color(red: 0.88, green: 0.95, blue: 1.0)
    static let background = Color(red: 0.006, green: 0.014, blue: 0.028)
    static let page = Color(red: 0.018, green: 0.052, blue: 0.084)
}

private enum PlannerEventColor {
    static let urgent = Color(red: 0.95, green: 0.38, blue: 0.43)
    static func forTitle(_ title: String) -> Color {
        let event = title.lowercased()
        if event.contains("devotional") || event.contains("prayer") || event.contains("church") {
            return Color(red: 0.69, green: 0.40, blue: 0.12)
        }
        if event.contains("walk") || event.contains("workout") || event.contains("breakfast") {
            return Color(red: 0.18, green: 0.45, blue: 0.31)
        }
        if event.contains("lunch") {
            return Color(red: 0.72, green: 0.38, blue: 0.10)
        }
        if event.contains("focus") || event.contains("planning") {
            return Color(red: 0.08, green: 0.38, blue: 0.64)
        }
        if event.contains("review") || event.contains("demo") || event.contains("meeting") || event.contains("stand up") || event.contains("sync") {
            return Color(red: 0.39, green: 0.25, blue: 0.62)
        }
        return Color(red: 0.12, green: 0.43, blue: 0.57)
    }
}

enum DashboardPalette {
    static let canvas = Color(red: 0.027, green: 0.043, blue: 0.075)
    static let card = Color(red: 0.070, green: 0.098, blue: 0.150)
    static let accent = Color(red: 0.38, green: 0.81, blue: 0.94)
    static let green = Color(red: 0.38, green: 0.84, blue: 0.64)
    static let amber = Color(red: 0.96, green: 0.69, blue: 0.28)
    static let red = Color(red: 0.95, green: 0.39, blue: 0.42)
}

@MainActor
private final class ProjectStore: ObservableObject {
    @Published private(set) var projects: [Project] = []
    @Published private(set) var error: String?
    @Published private(set) var loading = false

    func reload() async {
        guard !loading else { return }
        guard let path = CommandCenterPairing.shared.projectsDirectoryURL?.path else {
            projects = []
            error = "Pair Command Center with your installed MONDAY plugin and Project Knowledge vault before project context can be read."
            return
        }
        loading = true
        defer { loading = false }
        do { projects = try Registry.read(path: path); error = nil }
        catch let readError { error = readError.localizedDescription }
    }
}

private struct Project: Identifiable {
    let id: String
    let title: String
    let status: String
    let health: String
    let domain: String?
    let stage: String?
    let gateState: String?
    let milestone: String?
    let nextAction: String?
    let priority: Int?
    let gateDate: Date?
    let updatedAt: Date?

    var healthColor: Color { switch health { case "ready": DashboardPalette.green; case "watch": DashboardPalette.amber; case "at-risk", "intervention": DashboardPalette.red; default: .gray } }
    var healthLabel: String { health.replacingOccurrences(of: "-", with: " ") }
    var healthIcon: String { switch health { case "intervention", "at-risk": "exclamationmark.triangle.fill"; case "watch": "eye.fill"; case "ready": "checkmark.seal.fill"; default: "questionmark.circle.fill" } }
    var domainLabel: String { domain?.isEmpty == false ? domain! : "Domain not recorded" }
    var gateSummary: String {
        let state = gateState?.replacingOccurrences(of: "_", with: " ") ?? "not assessed"
        let date = gateDate?.formatted(.dateTime.month(.abbreviated).day())
        return date.map { "\(state) · \($0)" } ?? state
    }
}

private enum Registry {
    static func read(path: String) throws -> [Project] {
        guard FileManager.default.fileExists(atPath: path) else { throw RegistryError.missing(path) }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            .filter { $0.pathExtension.lowercased() == "md" }
            .compactMap(project(from:))
            .sorted {
                if $0.status == "active" && $1.status != "active" { return true }
                if $0.status != "active" && $1.status == "active" { return false }
                return ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast)
            }
    }

    private static func project(from url: URL) throws -> Project? {
        let metadata = frontMatter(in: try String(contentsOf: url, encoding: .utf8))
        guard metadata["type"] == "project" else { return nil }
        let title = url.deletingPathExtension().lastPathComponent
        return Project(
            id: metadata["id"] ?? title.lowercased().replacingOccurrences(of: " ", with: "-"),
            title: title,
            status: metadata["status"] ?? "unknown",
            health: metadata["health"] ?? "unknown",
            domain: metadata["organization"],
            stage: metadata["stage"],
            gateState: metadata["gate_state"],
            milestone: metadata["next_milestone"],
            nextAction: metadata["next_action"],
            priority: Int(metadata["priority"] ?? ""),
            gateDate: date(metadata["gate_date"]),
            updatedAt: date(metadata["updated"] ?? metadata["last_evidence_review"])
        )
    }

    private static func frontMatter(in content: String) -> [String: String] {
        let lines = content.components(separatedBy: .newlines)
        guard lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") else { return [:] }
        return Dictionary(uniqueKeysWithValues: lines[1..<end].compactMap { line in
            guard let separator = line.firstIndex(of: ":") else { return nil }
            let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: separator)...])
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\\\""))
            return key.isEmpty ? nil : (key, value)
        })
    }

    private static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value) { return date }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }
}

private enum RegistryError: LocalizedError {
    case missing(String), unreadable
    var errorDescription: String? { switch self { case .missing(let path): "The governed project registry was not found at \(path)."; case .unreadable: "The governed project registry could not be read." } }
}

private struct WeatherSnapshot {
    let place: String
    let temperature: Double
    let apparentTemperature: Double
    let windSpeed: Double
    let weatherCode: Int
    let isDaylight: Bool
    let moonPhase: MoonPhase
    let hasTornadoWarning: Bool
    let updatedAt: Date
    var artKey: String {
        if hasTornadoWarning { return "tornado" }
        switch weatherCode {
        case 0: return isDaylight ? "clear_day" : moonPhase.artKey
        case 1...3, 45, 48: return isDaylight ? "partly_cloudy_day" : moonPhase.artKey
        case 51...57, 61...63, 80, 81: return "light_rain"
        case 65...67, 82: return "heavy_rain"
        case 71...73, 85: return "light_snow"
        case 75...77, 86: return windSpeed >= 25 ? "blizzard" : "heavy_snow"
        case 95...99: return "thunderstorm"
        default: return "partly_cloudy_day"
        }
    }
    var condition: String {
        if hasTornadoWarning { return "Tornado warning" }
        switch weatherCode {
        case 0: return "Clear"
        case 1...3: return "Partly cloudy"
        case 45, 48: return "Fog"
        case 51...67, 80...82: return "Rain"
        case 71...77, 85, 86: return "Snow"
        case 95...99: return "Thunderstorm"
        default: return "Conditions reported"
        }
    }
}

private enum MoonPhase: CaseIterable {
    case new, waxingCrescent, firstQuarter, waxingGibbous, full, waningGibbous, lastQuarter, waningCrescent

    var artKey: String {
        switch self {
        case .new: "moon_new"
        case .waxingCrescent: "moon_waxing_crescent"
        case .firstQuarter: "moon_first_quarter"
        case .waxingGibbous: "moon_waxing_gibbous"
        case .full: "moon_full"
        case .waningGibbous: "moon_waning_gibbous"
        case .lastQuarter: "moon_last_quarter"
        case .waningCrescent: "moon_waning_crescent"
        }
    }

    static func current(at date: Date) -> MoonPhase {
        let calendar = Calendar(identifier: .gregorian)
        let reference = calendar.date(from: DateComponents(calendar: calendar, timeZone: TimeZone(secondsFromGMT: 0), year: 2000, month: 1, day: 6, hour: 18, minute: 14))!
        let synodicMonth = 29.530588853 * 86_400
        let progress = (date.timeIntervalSince(reference) / synodicMonth).truncatingRemainder(dividingBy: 1)
        let normalized = progress < 0 ? progress + 1 : progress
        let index = Int((normalized * Double(allCases.count) + 0.5).rounded(.down)) % allCases.count
        return allCases[index]
    }
}

@MainActor
private final class WeatherStore: ObservableObject {
    @Published private(set) var snapshot: WeatherSnapshot?
    @Published private(set) var error: String?
    @Published private(set) var loading = false

    func refresh(for query: String) async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
            guard let geocodeURL = URL(string: "https://geocoding-api.open-meteo.com/v1/search?name=\(encoded)&count=1&language=en&format=json") else { throw WeatherError.invalidLocation }
            let (geoData, _) = try await URLSession.shared.data(from: geocodeURL)
            let geocode = try JSONDecoder().decode(GeocodeResponse.self, from: geoData)
            guard let result = geocode.results?.first else { throw WeatherError.invalidLocation }
            guard let forecastURL = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(result.latitude)&longitude=\(result.longitude)&current=temperature_2m,apparent_temperature,weather_code,wind_speed_10m,is_day&temperature_unit=fahrenheit&wind_speed_unit=mph") else { throw WeatherError.unavailable }
            let (forecastData, _) = try await URLSession.shared.data(from: forecastURL)
            let forecast = try JSONDecoder().decode(ForecastResponse.self, from: forecastData)
            async let tornadoWarning = TornadoAlertDetector.hasActiveWarning(latitude: result.latitude, longitude: result.longitude, countryCode: result.countryCode)
            snapshot = WeatherSnapshot(place: [result.name, result.admin1].compactMap { $0 }.joined(separator: ", "), temperature: forecast.current.temperature2m, apparentTemperature: forecast.current.apparentTemperature, windSpeed: forecast.current.windSpeed10m, weatherCode: forecast.current.weatherCode, isDaylight: forecast.current.isDay == 1, moonPhase: MoonPhase.current(at: .now), hasTornadoWarning: await tornadoWarning, updatedAt: .now)
            error = nil
        } catch let weatherError {
            error = weatherError.localizedDescription
        }
    }
}

private struct GeocodeResponse: Decodable { let results: [GeocodeResult]? }
private struct GeocodeResult: Decodable { let name: String; let admin1: String?; let countryCode: String?; let latitude: Double; let longitude: Double; enum CodingKeys: String, CodingKey { case name, admin1, latitude, longitude; case countryCode = "country_code" } }
private struct ForecastResponse: Decodable { let current: CurrentWeather; struct CurrentWeather: Decodable { let temperature2m: Double; let apparentTemperature: Double; let weatherCode: Int; let windSpeed10m: Double; let isDay: Int; enum CodingKeys: String, CodingKey { case temperature2m = "temperature_2m"; case apparentTemperature = "apparent_temperature"; case weatherCode = "weather_code"; case windSpeed10m = "wind_speed_10m"; case isDay = "is_day" } } }

private enum TornadoAlertDetector {
    static func hasActiveWarning(latitude: Double, longitude: Double, countryCode: String?) async -> Bool {
        guard countryCode?.uppercased() == "US",
              let url = URL(string: "https://api.weather.gov/alerts/active?point=\(latitude),\(longitude)") else { return false }
        var request = URLRequest(url: url)
        request.setValue("MONDAY Command Center weather status", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 5
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let alerts = try? JSONDecoder().decode(NWSAlertResponse.self, from: data) else { return false }
        return alerts.features.contains { feature in
            feature.properties.status.caseInsensitiveCompare("Actual") == .orderedSame && feature.properties.event.localizedCaseInsensitiveContains("tornado")
        }
    }
}

private struct NWSAlertResponse: Decodable {
    struct Feature: Decodable { let properties: Properties }
    struct Properties: Decodable { let event: String; let status: String }
    let features: [Feature]
}
private enum WeatherError: LocalizedError { case invalidLocation, unavailable; var errorDescription: String? { switch self { case .invalidLocation: "That location could not be found. Try city and state or region."; case .unavailable: "Weather is unavailable right now." } } }

private struct DayEvent: Identifiable {
    let id: String
    let title: String
    let timeLabel: String
}

private enum CalendarState: Equatable { case notConnected, loading, connected, unavailable(String) }

@MainActor
private final class CalendarStore: ObservableObject {
    @Published private(set) var state: CalendarState = .notConnected
    @Published private(set) var events: [DayEvent] = []

    func connect() async {
        await reloadToday()
    }

    func reloadToday() async {
        events = []
        guard let url = CommandCenterPairing.shared.plannerFeedURL else {
            state = .notConnected
            return
        }
        state = .loading
        do {
            let plan = try PlannerFeedReader.load(from: url)
            let expected = Self.localDateKey(timezone: plan.timezone)
            guard plan.validation(expectedDate: expected, enforceFreshness: true) == .current else {
                state = .unavailable("The Planner projection is not current and verified. Refresh it in Codex before using it in Command Center.")
                return
            }
            guard let calendarSource = plan.sources.first(where: { $0.kind == "calendar" }), calendarSource.status == "available" else {
                let source = plan.sources.first(where: { $0.kind == "calendar" })
                state = .unavailable(source?.detail ?? "Calendar coverage is unknown. This is not evidence that the day is clear.")
                return
            }
            events = plan.schedule
                .sorted { $0.time < $1.time }
                .map { DayEvent(id: "\($0.time)-\($0.end)-\($0.title)", title: $0.title, timeLabel: $0.time) }
            state = .connected
        } catch {
            state = .unavailable("The Planner shared plan could not be read: \(error.localizedDescription)")
        }
    }

    private static func localDateKey(timezone: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: timezone) ?? .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: .now)
    }
}
