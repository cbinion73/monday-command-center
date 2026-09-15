import Foundation
import SwiftUI

struct CommandCenterView: View {
    @StateObject private var store = ProjectStore()
    @StateObject private var workflows = ProjectWorkflowStore()
    @State private var search = ""
    @State private var selectedProject: Project?
    @State private var collapsedTypes: Set<String> = []

    private var visibleProjects: [Project] {
        guard !search.isEmpty else { return store.projects }
        return store.projects.filter {
            $0.title.localizedCaseInsensitiveContains(search) ||
            ($0.stage?.localizedCaseInsensitiveContains(search) ?? false) ||
            ($0.milestone?.localizedCaseInsensitiveContains(search) ?? false)
        }
    }

    private var projectGroups: [ProjectGroup] {
        let grouped = Dictionary(grouping: visibleProjects, by: \.presentationType)
        return grouped.map { ProjectGroup(typeKey: $0.key, projects: $0.value) }
            .sorted { $0.sortRank < $1.sortRank }
    }

    var body: some View {
        Group {
            if let selectedProject {
                ProjectDetailView(project: selectedProject, workflow: workflows.plan(for: selectedProject.id)) { self.selectedProject = nil }
            } else {
                portfolioView
            }
        }
        .preferredColorScheme(.dark)
        .task { await store.reload(); await workflows.reload() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                await store.reload(); await workflows.reload()
            }
        }
    }

    private var portfolioView: some View {
        ZStack {
            DashboardPalette.canvas.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    masthead
                    VStack(alignment: .leading, spacing: 18) {
                        portfolioHeader
                        if let error = store.error { unavailable(error) } else { routeList; truthNote }
                    }
                    .padding(22).frame(maxWidth: 1760)
                }
            }
        }
    }

    private var masthead: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 5) {
                Text("MONDAY COMMAND CENTER").font(.system(size: 11, weight: .bold, design: .rounded)).tracking(1.7).foregroundStyle(DashboardPalette.accent)
                Text("The big picture, honestly.").font(.system(size: 31, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                Text("A shared map of what is moving, what needs evidence, and what needs your judgment.").font(.system(size: 13)).foregroundStyle(Color.white.opacity(0.72))
            }
            Spacer(minLength: 10)
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Color.white.opacity(0.65))
                    TextField("Search projects", text: $search).textFieldStyle(.plain).frame(minWidth: 200).foregroundStyle(.white)
                }
                .padding(.horizontal, 12).padding(.vertical, 10).background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.20), lineWidth: 0.7))
                Button { Task { await store.reload(); await workflows.reload() } } label: { Label(store.loading ? "Refreshing…" : "Refresh", systemImage: "arrow.clockwise") }
                    .buttonStyle(.bordered).tint(.white).foregroundStyle(.white).disabled(store.loading)
            }
        }
        .padding(.horizontal, 42).padding(.vertical, 25)
        .background(DashboardPalette.card, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.10), lineWidth: 1))
    }

    private var portfolioHeader: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 5) {
                Text("WORK PROJECTS").font(.system(size: 10, weight: .bold, design: .rounded)).tracking(1.4).foregroundStyle(DashboardPalette.accent)
                Text("Projects I’m holding with you").font(.system(size: 21, weight: .semibold, design: .rounded)).foregroundStyle(.white)
            }
            Spacer()
            HStack(spacing: 15) { Legend(label: "Ready", color: .green); Legend(label: "Active", color: .blue); Legend(label: "Your judgment", color: .orange); Legend(label: "Needs attention", color: .red) }
        }
        .padding(.horizontal, 4)
    }

    private var routeList: some View {
        VStack(alignment: .leading, spacing: 18) {
            if visibleProjects.isEmpty { Text("No accessible projects match this view.").font(.system(size: 13)).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 130) }
            ForEach(projectGroups) { group in
                VStack(alignment: .leading, spacing: 9) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            if collapsedTypes.contains(group.id) { collapsedTypes.remove(group.id) }
                            else { collapsedTypes.insert(group.id) }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: collapsedTypes.contains(group.id) ? "chevron.right" : "chevron.down")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.blue)
                                .frame(width: 12)
                            Text(group.title.uppercased()).font(.system(size: 10, weight: .bold, design: .rounded)).tracking(1.3).foregroundStyle(.white.opacity(0.58))
                            Text("\(group.projects.count)").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.62)).padding(.horizontal, 6).padding(.vertical, 2).background(.white.opacity(0.08), in: Capsule())
                            Spacer()
                            Text(collapsedTypes.contains(group.id) ? "Expand" : "Collapse")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.52))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(collapsedTypes.contains(group.id) ? "Expand" : "Collapse") \(group.title)")
                    if !collapsedTypes.contains(group.id) {
                        ForEach(group.projects) { project in Button { selectedProject = project } label: { ProjectRouteRow(project: project, workflow: workflows.plan(for: project.id)) }.buttonStyle(.plain) }
                    }
                }
            }
        }
    }

    private var truthNote: some View {
        HStack(spacing: 9) {
            Image(systemName: "checkmark.shield").foregroundStyle(DashboardPalette.accent)
            Text("Routes show the recorded stage, next milestone, and gate. Evidence, approval, and human judgment remain distinct; unknown information stays unknown.").font(.system(size: 11)).foregroundStyle(.white.opacity(0.58))
        }.padding(.horizontal, 8).padding(.top, 4)
    }

    private func unavailable(_ message: String) -> some View {
        ContentCard { VStack(alignment: .leading, spacing: 10) { Label("Project registry unavailable", systemImage: "externaldrive.badge.exclamationmark").font(.system(size: 18, weight: .semibold)).foregroundStyle(.orange); Text(message).font(.system(size: 13)).foregroundStyle(.secondary); Text("No fallback data is shown.").font(.system(size: 11)).foregroundStyle(.tertiary) }.frame(maxWidth: .infinity, alignment: .leading) }
    }
}

struct PersonalProjectsRoom: View {
    @StateObject private var store = PersonalProjectStore()
    @State private var search = ""
    @State private var selectedProject: Project?

    private var visibleProjects: [Project] {
        guard !search.isEmpty else { return store.projects }
        return store.projects.filter {
            $0.title.localizedCaseInsensitiveContains(search) ||
            ($0.stage?.localizedCaseInsensitiveContains(search) ?? false) ||
            ($0.milestone?.localizedCaseInsensitiveContains(search) ?? false)
        }
    }

    var body: some View {
        Group {
            if let selectedProject {
                ProjectDetailView(project: selectedProject, workflow: nil) { self.selectedProject = nil }
            } else {
                room
            }
        }
        .preferredColorScheme(.dark)
        .task { await store.reload() }
    }

    private var room: some View {
        ZStack {
            DashboardPalette.canvas.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    if let error = store.error {
                        ContentCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("PERSONAL PROJECT KNOWLEDGE", systemImage: "lock.shield")
                                    .font(.system(size: 11, weight: .black, design: .rounded))
                                    .tracking(1.1).foregroundStyle(DashboardPalette.accent)
                                Text("Personal Projects is ready when you are.")
                                    .font(.system(size: 22, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                                Text(error).font(.system(size: 14)).foregroundStyle(.white.opacity(0.66))
                                Text("This private source is intentionally separate from Project Knowledge and is never reported to JARVIS.")
                                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.48))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else if visibleProjects.isEmpty {
                        ContentCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("No active personal projects are recorded.")
                                    .font(.system(size: 18, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                                Text("When the private project registry contains active records, they will appear here and in MONDAY’s planning brief.")
                                    .font(.system(size: 13)).foregroundStyle(.white.opacity(0.58))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 310), spacing: 14)], spacing: 14) {
                            ForEach(visibleProjects) { project in
                                Button { selectedProject = project } label: { PersonalProjectCard(project: project) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                    Text("PRIVATE SOURCE · LOCAL TO THIS MAC · NOT REPORTED TO JARVIS")
                        .font(.system(size: 9, weight: .bold, design: .rounded)).tracking(1.1)
                        .foregroundStyle(.white.opacity(0.40))
                }
                .padding(34).frame(maxWidth: 1320, alignment: .leading)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 7) {
                Text("PERSONAL PROJECTS").font(.system(size: 11, weight: .black, design: .rounded)).tracking(1.5).foregroundStyle(DashboardPalette.accent)
                Text("The work that belongs to your life.").font(.system(size: 31, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                Text("A private operating view for the projects MONDAY helps you steward outside the Thermo portfolio.")
                    .font(.system(size: 14)).foregroundStyle(.white.opacity(0.62))
            }
            Spacer(minLength: 16)
            HStack(spacing: 9) {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.52))
                    TextField("Find a personal project", text: $search).textFieldStyle(.plain).frame(width: 210).foregroundStyle(.white)
                }
                .padding(.horizontal, 11).padding(.vertical, 9)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.12), lineWidth: 1))
                Button { Task { await store.reload() } } label: { Label(store.loading ? "Refreshing" : "Refresh", systemImage: "arrow.clockwise") }
                    .buttonStyle(.bordered).tint(.white.opacity(0.18)).foregroundStyle(.white).disabled(store.loading)
            }
        }
        .padding(24).background(DashboardPalette.card, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.10), lineWidth: 1))
    }
}

private struct PersonalProjectCard: View {
    let project: Project
    var body: some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    StatusBadge(label: project.status, color: project.healthColor)
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.45))
                }
                Text(project.title).font(.system(size: 19, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                if let milestone = project.milestone {
                    Text(milestone).font(.system(size: 12)).foregroundStyle(.white.opacity(0.62)).lineLimit(2)
                } else {
                    Text("No next milestone recorded.").font(.system(size: 12)).foregroundStyle(.white.opacity(0.46))
                }
                Text("UPDATED \(project.updatedAt?.formatted(date: .abbreviated, time: .omitted) ?? "UNKNOWN")")
                    .font(.system(size: 9, weight: .bold, design: .rounded)).tracking(0.8).foregroundStyle(.white.opacity(0.42))
            }
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
        }
    }
}

private struct ProjectRouteRow: View {
    let project: Project
    let workflow: WorkflowProject?
    var body: some View {
        ContentCard { HStack(spacing: 22) {
            VStack(alignment: .leading, spacing: 5) {
                Text(project.title).font(.system(size: 16, weight: .semibold, design: .rounded))
                HStack(spacing: 6) { Text(project.healthLabel.capitalized); Text("·"); Text(project.gateSummary) }
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }.frame(width: 220, alignment: .leading)
            ProjectFlowSummary(project: project, workflow: workflow).frame(maxWidth: .infinity)
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(.tertiary)
        }.frame(minHeight: 154) }
    }
}

private struct ProjectFlowSummary: View {
    let project: Project
    let workflow: WorkflowProject?
    private var blueprint: WorkflowBlueprint { WorkflowBlueprints.forType(project.presentationType) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(Array(blueprint.stations.enumerated()), id: \.element.id) { index, station in
                        PortfolioStationNode(
                            station: station,
                            isCurrent: station.key == project.currentStationKey,
                            isDecision: station.key == "RESET"
                        )
                        if index < blueprint.stations.count - 1 {
                            Rectangle()
                                .fill(station.key == "REVIEW" ? Color.orange.opacity(0.7) : Color.blue.opacity(0.45))
                                .frame(width: 21, height: 2)
                                .padding(.bottom, 24)
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
            .scrollIndicators(.hidden)
            HStack(alignment: .top, spacing: 14) {
                FlowFact(label: "CURRENT PHASE", value: workflow?.currentPhaseLabel ?? project.currentPhaseLabel, tint: project.currentStationKey == nil ? .orange : .blue)
                FlowFact(label: "NEXT EVIDENCE GATE", value: workflow?.nextEvidenceGate ?? project.nextEvidenceGate, tint: .blue)
                FlowFact(label: "DECISION OWNER", value: workflow?.decision_owner ?? project.decisionOwner, tint: (workflow?.decision_owner ?? project.owner) == nil ? .orange : .green)
            }
        }
    }
}

private struct PortfolioStationNode: View {
    let station: WorkflowStation
    let isCurrent: Bool
    let isDecision: Bool

    var body: some View {
        VStack(spacing: 3) {
            Text(station.key.replacingOccurrences(of: "_", with: " "))
                .font(.system(size: 7, weight: .bold, design: .rounded))
                .tracking(0.5)
                .foregroundStyle(isCurrent ? .blue : .secondary)
                .lineLimit(1)
            ZStack {
                Circle().fill(isCurrent ? Color.blue.opacity(0.14) : .clear).frame(width: 27, height: 27)
                Circle().fill(.white).frame(width: 13, height: 13).overlay(Circle().stroke(isDecision ? .orange : Color.blue, lineWidth: isCurrent ? 4 : 2))
            }
            HStack(spacing: 3) {
                ForEach(station.stops, id: \.self) { _ in
                    Circle().fill(isCurrent ? Color.blue : Color.blue.opacity(0.42)).frame(width: 4, height: 4)
                }
            }
            Text(station.name).font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary).lineLimit(1).frame(width: 66)
        }
        .frame(width: 70, height: 78, alignment: .top)
    }
}

private struct FlowFact: View {
    let label, value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 8, weight: .bold, design: .rounded)).tracking(0.8).foregroundStyle(tint)
            Text(value).font(.system(size: 10, weight: .semibold)).foregroundStyle(.primary).lineLimit(2)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RouteConnector: View { let color: Color; var body: some View { Rectangle().fill(color.opacity(0.45)).frame(height: 2).frame(maxWidth: .infinity).padding(.top, 40) } }
private enum RouteState { case active, complete, decision, blocked, unknown }
private struct RouteStation: View {
    let eyebrow, title, caption: String; let color: Color; let state: RouteState
    var body: some View {
        VStack(spacing: 5) {
            Text(eyebrow).font(.system(size: 9, weight: .bold, design: .rounded)).tracking(1).foregroundStyle(.secondary)
            Circle().fill(fill).frame(width: 16, height: 16).overlay(Circle().stroke(color, lineWidth: state == .complete ? 0 : 3))
            Text(title).font(.system(size: 11, weight: .semibold)).lineLimit(2).multilineTextAlignment(.center).frame(maxWidth: 150)
            Text(caption).font(.system(size: 9)).foregroundStyle(color).lineLimit(1)
        }.frame(width: 156, height: 94, alignment: .top)
    }
    private var fill: Color { switch state { case .complete: color; case .active: color.opacity(0.25); case .decision, .unknown: .white; case .blocked: Color.red.opacity(0.12) } }
}

private struct ProjectMapWorkspace: View {
    let project: Project
    @State private var selectedStationKey: String?
    @State private var selectedStop: String?

    private var blueprint: WorkflowBlueprint { WorkflowBlueprints.forType(project.presentationType) }
    private var selectedStation: WorkflowStation {
        blueprint.stations.first { $0.key == selectedStationKey }
            ?? blueprint.stations.first { $0.key == project.currentStationKey }
            ?? blueprint.stations[0]
    }
    private var activeStop: String { selectedStop ?? selectedStation.stops[0] }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("PROJECT PROGRESS MAP").font(.system(size: 10, weight: .bold, design: .rounded)).tracking(1.4).foregroundStyle(.secondary)
                Text("\(blueprint.type) stations and deliverables").font(.system(size: 20, weight: .semibold, design: .rounded))
            }
            StationRail(stations: blueprint.stations, selectedStationKey: selectedStation.key, currentStationKey: project.currentStationKey) { station in
                selectedStationKey = station.key
                selectedStop = nil
            }
            HStack(alignment: .top, spacing: 14) {
                StopsPanel(station: selectedStation, selectedStop: activeStop) { selectedStop = $0 }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                EvidencePanel(stop: activeStop, station: selectedStation)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                SelectionSummary(project: project, station: selectedStation, stop: activeStop)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .padding(28)
        .frame(maxWidth: 1360)
    }
}

private struct StationRail: View {
    let stations: [WorkflowStation]
    let selectedStationKey: String
    let currentStationKey: String?
    let select: (WorkflowStation) -> Void

    var body: some View {
        ContentCard {
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(Array(stations.enumerated()), id: \.element.id) { index, station in
                        StationRailNode(station: station, isSelected: station.key == selectedStationKey, isCurrent: station.key == currentStationKey) { select(station) }
                        if index < stations.count - 1 { Rectangle().fill(Color.blue.opacity(0.55)).frame(width: 38, height: 3).padding(.top, 53) }
                    }
                }
                .padding(.horizontal, 6)
            }
            .scrollIndicators(.visible)
        }
    }
}

private struct StationRailNode: View {
    let station: WorkflowStation
    let isSelected: Bool
    let isCurrent: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(spacing: 5) {
                Text(station.key.replacingOccurrences(of: "_", with: " ")).font(.system(size: 8, weight: .bold, design: .rounded)).tracking(0.7).foregroundStyle(isSelected ? .blue : .secondary).lineLimit(1)
                ZStack {
                    Circle().fill(isSelected || isCurrent ? Color.blue.opacity(0.14) : .clear).frame(width: 34, height: 34)
                    Circle().fill(.white).frame(width: 16, height: 16).overlay(Circle().stroke(isCurrent ? Color.blue : Color.blue.opacity(0.8), lineWidth: isCurrent ? 5 : 2))
                }
                Text(station.name).font(.system(size: 10, weight: .semibold)).foregroundStyle(.primary).multilineTextAlignment(.center).lineLimit(2).frame(width: 112)
                HStack(spacing: 4) { ForEach(station.stops, id: \.self) { _ in Circle().fill(isSelected ? Color.blue : Color.blue.opacity(0.45)).frame(width: 5, height: 5) } }
                Text("\(station.stops.count) stops").font(.system(size: 8)).foregroundStyle(.secondary)
            }
            .frame(width: 116, height: 128, alignment: .top)
        }
        .buttonStyle(.plain)
    }
}

private struct StopsPanel: View {
    let station: WorkflowStation
    let selectedStop: String
    let select: (String) -> Void

    var body: some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("STATION").font(.system(size: 10, weight: .bold, design: .rounded)).tracking(1.2).foregroundStyle(.secondary)
                Text(station.name).font(.system(size: 18, weight: .semibold, design: .rounded))
                Text(station.purpose).font(.system(size: 12)).foregroundStyle(.secondary)
                Divider()
                ForEach(station.stops, id: \.self) { stop in
                    Button { select(stop) } label: {
                        HStack(alignment: .center, spacing: 9) {
                            Circle().fill(stop == selectedStop ? Color.blue : .white).frame(width: 11, height: 11).overlay(Circle().stroke(Color.blue, lineWidth: 2))
                            Text(stop).font(.system(size: 12, weight: .medium)).foregroundStyle(.primary).multilineTextAlignment(.leading)
                            Spacer()
                            Text(stop == selectedStop ? "Selected" : "Expected").font(.system(size: 9, weight: .bold)).foregroundStyle(stop == selectedStop ? .blue : .secondary)
                        }
                        .padding(.vertical, 7).padding(.horizontal, 6)
                        .background(stop == selectedStop ? Color.blue.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(minHeight: 300, alignment: .topLeading)
        }
    }
}

private struct EvidencePanel: View {
    let stop: String
    let station: WorkflowStation

    var body: some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("DELIVERABLE").font(.system(size: 10, weight: .bold, design: .rounded)).tracking(1.2).foregroundStyle(.secondary)
                Text("Evidence for this stop").font(.system(size: 18, weight: .semibold, design: .rounded))
                Divider()
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "doc.text").foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(stop).font(.system(size: 13, weight: .semibold))
                        Text("Required deliverable in \(station.name)").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("Not evidenced").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary).padding(.horizontal, 7).padding(.vertical, 4).background(.black.opacity(0.05), in: Capsule())
                }
                Spacer()
                Text("When an accepted artifact is recorded, it will appear here with its source and standing. This map does not infer acceptance from the planned workflow.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .frame(minHeight: 300, alignment: .topLeading)
        }
    }
}

private struct SelectionSummary: View {
    let project: Project
    let station: WorkflowStation
    let stop: String

    var body: some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("CURRENT SELECTION").font(.system(size: 10, weight: .bold, design: .rounded)).tracking(1.2).foregroundStyle(.secondary)
                Text("Summary").font(.system(size: 18, weight: .semibold, design: .rounded))
                Divider()
                SummaryLine(label: "Type", value: "Activity stop")
                SummaryLine(label: "Station", value: station.name)
                SummaryLine(label: "Stop", value: stop)
                SummaryLine(label: "Status", value: station.key == project.currentStationKey ? "active" : "planned")
                SummaryLine(label: "Evidence", value: "not yet recorded")
                SummaryLine(label: "Gate", value: project.gateState?.replacingOccurrences(of: "_", with: " ") ?? "not assessed")
                SummaryLine(label: "Source basis", value: "workflow plan plus governed project registry")
                Spacer()
                Text("The workflow prepares the case. You retain the decision; recorded evidence determines whether a stop is accepted.").font(.system(size: 11)).foregroundStyle(Color(red: 0.40, green: 0.30, blue: 0.12)).padding(10).background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }
            .frame(minHeight: 300, alignment: .topLeading)
        }
    }
}

private struct SummaryLine: View {
    let label, value: String
    var body: some View { HStack(alignment: .top, spacing: 8) { Text(label).font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 70, alignment: .leading); Text(value).font(.system(size: 11, weight: .semibold)).foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading) } }
}

private struct WorkflowStationPlan: View {
    let project: Project
    private var blueprint: WorkflowBlueprint { WorkflowBlueprints.forType(project.presentationType) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("STATIONS & STOPS").font(.system(size: 10, weight: .bold, design: .rounded)).tracking(1.3).foregroundStyle(.secondary)
                    Text(blueprint.type).font(.system(size: 20, weight: .semibold, design: .rounded))
                }
                Spacer()
                Text("Current source stage: \(project.stage?.replacingOccurrences(of: "-", with: " ") ?? "unknown")").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 14)], spacing: 14) {
                ForEach(blueprint.stations) { station in
                    WorkflowStationCard(station: station, isCurrent: project.currentStationKey == station.key)
                }
            }
        }
    }
}

private struct WorkflowStationCard: View {
    let station: WorkflowStation
    let isCurrent: Bool

    var body: some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(station.key.replacingOccurrences(of: "_", with: " ")).font(.system(size: 9, weight: .bold, design: .rounded)).tracking(0.8).foregroundStyle(isCurrent ? .blue : .secondary)
                        Text(station.name).font(.system(size: 16, weight: .semibold, design: .rounded))
                    }
                    Spacer()
                    if isCurrent { Text("CURRENT").font(.system(size: 9, weight: .bold, design: .rounded)).tracking(0.7).foregroundStyle(.blue).padding(.horizontal, 7).padding(.vertical, 4).background(Color.blue.opacity(0.10), in: Capsule()) }
                }
                Text(station.purpose).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                Divider()
                ForEach(station.stops, id: \.self) { stop in
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: "circle").font(.system(size: 9)).foregroundStyle(.tertiary).padding(.top, 2)
                        Text(stop).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 205, alignment: .topLeading)
        }
    }
}

private struct ProjectDetailView: View {
    let project: Project; let workflow: WorkflowProject?; let close: () -> Void
    var body: some View {
        ZStack { DashboardPalette.canvas.ignoresSafeArea(); ScrollView { VStack(spacing: 0) { detailMasthead; ProjectMapWorkspace(project: project); if let workflow { WorkflowEvidencePlan(workflow: workflow).padding(.horizontal, 28).padding(.bottom, 20).frame(maxWidth: 1360) }; evidenceNote.padding(.horizontal, 28).padding(.bottom, 28).frame(maxWidth: 1360) } } }.preferredColorScheme(.dark)
    }
    private var detailMasthead: some View {
        HStack(alignment: .top, spacing: 18) {
            Button(action: close) { Label("All projects", systemImage: "chevron.left") }.buttonStyle(.bordered).tint(.white).foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 6) { Text("SELECTED PROJECT").font(.system(size: 10, weight: .bold, design: .rounded)).tracking(1.4).foregroundStyle(Color(red: 0.55, green: 0.77, blue: 1.0)); Text(project.title).font(.system(size: 28, weight: .semibold, design: .rounded)).foregroundStyle(.white); Text("The precise operating picture: what is known, what is needed, and what needs a decision.").font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.72)) }
            Spacer(); StatusBadge(label: project.healthLabel, color: project.healthColor)
        }.padding(.horizontal, 38).padding(.vertical, 25).background(DashboardPalette.card)
    }
    private var detailPanels: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 15) {
            DetailPanel(title: "Current stage", eyebrow: "NOW", icon: "location.fill", color: project.healthColor) { DetailLine(label: "Stage", value: project.stage?.replacingOccurrences(of: "-", with: " ") ?? "Unknown"); DetailLine(label: "Health", value: project.healthLabel); DetailLine(label: "Recorded", value: project.updatedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Unknown") }
            DetailPanel(title: "Next evidence", eyebrow: "NEXT", icon: "doc.text.fill", color: .blue) { DetailLine(label: "Milestone", value: project.milestone ?? "Not recorded"); DetailLine(label: "Action", value: project.action ?? "Not recorded"); DetailLine(label: "Actual hours", value: project.actualHours.map { "\(Int($0)) h" } ?? "Unknown") }
            DetailPanel(title: "Gate & judgment", eyebrow: "GATE", icon: "person.badge.key.fill", color: project.gateColor) { DetailLine(label: "Gate", value: project.gateState?.replacingOccurrences(of: "_", with: " ") ?? "Not assessed"); DetailLine(label: "Date", value: project.gateLabel); DetailLine(label: "Planned hours", value: project.plannedHours.map { "\(Int($0)) h" } ?? "Unknown") }
        }
    }
    private var evidenceNote: some View { HStack(alignment: .top, spacing: 10) { Image(systemName: "checkmark.shield").foregroundStyle(.blue); Text("This view is intentionally factual. A recorded milestone is not proof of completion; a gate is not approval; and missing evidence remains unknown until the registry says otherwise.").font(.system(size: 12)).foregroundStyle(.secondary) }.padding(15).background(Color.blue.opacity(0.055), in: RoundedRectangle(cornerRadius: 12)) }
}

private struct WorkflowEvidencePlan: View {
    let workflow: WorkflowProject
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("EVIDENCE-LINKED SUBSTEPS").font(.system(size: 10, weight: .bold, design: .rounded)).tracking(1.3).foregroundStyle(DashboardPalette.accent)
            Text("\(workflow.steps.count) substeps, refreshed from the governed project record").font(.system(size: 20, weight: .semibold, design: .rounded))
            Text("Proposed substeps identify needed work. They are not completion claims and carry no evidence until an accepted record is available.").font(.system(size: 12)).foregroundStyle(.secondary)
            ForEach(workflow.steps) { step in
                ContentCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Text(step.station.replacingOccurrences(of: "_", with: " ")).font(.system(size: 9, weight: .bold, design: .rounded)).tracking(0.8).foregroundStyle(step.state == "recorded" ? DashboardPalette.green : DashboardPalette.amber); Spacer(); Text(step.evidence_status.uppercased()).font(.system(size: 9, weight: .bold, design: .rounded)).foregroundStyle(step.state == "recorded" ? DashboardPalette.green : DashboardPalette.amber) }
                        Text(step.title).font(.system(size: 16, weight: .semibold, design: .rounded))
                        Text(step.purpose).font(.system(size: 12)).foregroundStyle(.secondary)
                        if step.evidence.isEmpty { Text("Evidence: no accepted artifact recorded yet.").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary) }
                        else { ForEach(step.evidence.prefix(3)) { evidence in Text("Evidence · \(evidence.kind): \(evidence.label) [\(evidence.standing)]").font(.system(size: 11)).foregroundStyle(.secondary) } }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

private struct DetailPanel<Content: View>: View { let title, eyebrow, icon: String; let color: Color; @ViewBuilder let content: Content; var body: some View { ContentCard { VStack(alignment: .leading, spacing: 13) { Label(eyebrow, systemImage: icon).font(.system(size: 10, weight: .bold, design: .rounded)).tracking(0.9).foregroundStyle(color); Text(title).font(.system(size: 18, weight: .semibold, design: .rounded)); Divider(); content }.frame(maxWidth: .infinity, minHeight: 210, alignment: .topLeading) } } }
private struct DetailLine: View { let label, value: String; var body: some View { VStack(alignment: .leading, spacing: 3) { Text(label.uppercased()).font(.system(size: 9, weight: .bold)).tracking(0.8).foregroundStyle(.tertiary); Text(value).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(3) } } }
private struct Legend: View { let label: String; let color: Color; var body: some View { HStack(spacing: 5) { Circle().fill(color).frame(width: 8, height: 8); Text(label).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary) } } }
private struct StatusBadge: View { let label: String; let color: Color; var body: some View { Text(label.uppercased()).font(.system(size: 10, weight: .bold, design: .rounded)).tracking(0.8).foregroundStyle(color).padding(.horizontal, 10).padding(.vertical, 6).background(color.opacity(0.12), in: Capsule()).overlay(Capsule().stroke(color.opacity(0.35), lineWidth: 0.8)) } }
private struct ContentCard<Content: View>: View { @ViewBuilder let content: Content; var body: some View { content.padding(18).background(DashboardPalette.card, in: RoundedRectangle(cornerRadius: 15)).overlay(RoundedRectangle(cornerRadius: 15).stroke(.white.opacity(0.10), lineWidth: 0.8)).shadow(color: .black.opacity(0.22), radius: 12, y: 4) } }

@MainActor private final class ProjectStore: ObservableObject {
    @Published private(set) var projects: [Project] = []; @Published private(set) var error: String?; @Published private(set) var loading = false
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

@MainActor private final class PersonalProjectStore: ObservableObject {
    @Published private(set) var projects: [Project] = []
    @Published private(set) var error: String?
    @Published private(set) var loading = false

    func reload() async {
        guard !loading else { return }
        guard let path = CommandCenterPairing.shared.personalProjectsDirectoryURL?.path else {
            projects = []
            error = "Choose the Personal Project Knowledge vault in Settings when you are ready. It should contain a private 03 Projects folder."
            return
        }
        loading = true
        defer { loading = false }
        do {
            projects = try Registry.read(path: path)
            error = nil
        } catch {
            projects = []
            self.error = error.localizedDescription
        }
    }
}

private struct WorkflowFeed: Decodable {
    let schema_version: Int
    let generated_at: String
    let projects: [WorkflowProject]
}

private struct WorkflowProject: Decodable, Identifiable {
    let project_id: String
    let project_title: String
    let source_path: String
    let source_modified_at: String
    let project_status: String
    let current_station: String
    let decision_owner: String?
    let steps: [WorkflowStep]
    var id: String { project_id }
    var currentPhaseLabel: String { current_station.replacingOccurrences(of: "_", with: " ").capitalized }
    var nextEvidenceGate: String { steps.first { $0.state != "recorded" }?.purpose ?? "No additional evidence gate recorded" }
}

private struct WorkflowStep: Decodable, Identifiable {
    let id: String
    let station: String
    let title: String
    let purpose: String
    let state: String
    let evidence_status: String
    let evidence: [WorkflowEvidence]
}

private struct WorkflowEvidence: Decodable, Identifiable {
    let label: String
    let locator: String
    let standing: String
    let kind: String
    var id: String { "\(kind):\(locator)" }
}

@MainActor private final class ProjectWorkflowStore: ObservableObject {
    @Published private(set) var plans: [String: WorkflowProject] = [:]
    @Published private(set) var error: String?

    func plan(for projectID: String) -> WorkflowProject? { plans[projectID] }

    func reload() async {
        guard let url = CommandCenterPairing.shared.projectWorkflowFeedURL else { plans = [:]; return }
        do {
            let feed = try JSONDecoder().decode(WorkflowFeed.self, from: Data(contentsOf: url))
            guard feed.schema_version == 1 else { throw WorkflowFeedError.unsupportedSchema }
            plans = Dictionary(uniqueKeysWithValues: feed.projects.map { ($0.project_id, $0) })
            error = nil
        } catch {
            plans = [:]
            self.error = error.localizedDescription
        }
    }
}

private enum WorkflowFeedError: LocalizedError {
    case unsupportedSchema
    var errorDescription: String? { "The project workflow feed has an unsupported schema." }
}

private struct Project: Identifiable {
    let id, title, status, health: String; let domain, stage, gateState, milestone, action, owner: String?; let priority: Int?; let gateDate, updatedAt: Date?; let plannedHours, actualHours: Double?
    var healthColor: Color { switch health { case "ready": .green; case "watch": .orange; case "at-risk", "intervention": .red; default: .gray } }
    var gateColor: Color { gateState?.contains("blocked") == true ? .red : gateState == nil ? .gray : .orange }
    var healthLabel: String { health.replacingOccurrences(of: "-", with: " ") }
    var gateLabel: String { gateDate?.formatted(.dateTime.month(.abbreviated).day().year()) ?? "Undated" }
    var gateSummary: String { "gate \(gateState?.replacingOccurrences(of: "_", with: " ") ?? "not assessed")" }
    var currentPhaseLabel: String {
        guard let currentStationKey else { return "Assessment required" }
        return WorkflowBlueprints.forType(presentationType).stations.first { $0.key == currentStationKey }?.name ?? currentStationKey.replacingOccurrences(of: "_", with: " ")
    }
    var nextEvidenceGate: String {
        guard let currentStationKey,
              let station = WorkflowBlueprints.forType(presentationType).stations.first(where: { $0.key == currentStationKey }) else {
            return "Record current stage, evidence, and accountable owner"
        }
        return action ?? milestone ?? station.stops.first ?? "Not recorded"
    }
    var decisionOwner: String { owner ?? "Not recorded" }
    var presentationType: String {
        let recorded = domain?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        switch recorded {
        case "publishing": return "books & publishing"
        case "software", "professional research": return recorded
        case "": break
        default: return recorded
        }

        switch title {
        case "Dust and Acts 4:13": return "faith & formation"
        case "The Thinking Partner", "The Influence Engine", "The Lean Lab": return "books & publishing"
        case "Portfolio Operating System": return "portfolio & operations"
        default: return "type not recorded"
        }
    }

    var currentStationKey: String? {
        let sourceStage = stage?.lowercased() ?? ""
        switch presentationType {
        case "books & publishing":
            if sourceStage.contains("production") { return "PRODUCTION" }
            if sourceStage.contains("beta") || sourceStage.contains("peer") { return "PEER_REVIEW" }
            if sourceStage.contains("revision") { return "AUTHOR_REVISION" }
            if sourceStage.contains("final") || sourceStage.contains("editing") { return "COPY_EDIT" }
            if sourceStage.contains("published") { return "POST_PUBLICATION" }
            if sourceStage.contains("draft") { return "CHAPTER_DRAFT" }
        case "website":
            if sourceStage.contains("build") { return "BUILD" }
        case "software":
            if sourceStage.contains("acceptance") { return "ACCEPT" }
            if sourceStage.contains("build") { return "BUILD" }
        case "professional research":
            if sourceStage.contains("research") { return "COLLECT" }
        case "portfolio & operations":
            if sourceStage.contains("baseline") { return "BASELINE" }
        default:
            break
        }
        return nil
    }
}

private struct ProjectGroup: Identifiable {
    let typeKey: String
    let projects: [Project]
    var id: String { typeKey }
    var title: String { typeKey.isEmpty ? "Type not recorded" : typeKey }
    var sortRank: Int { switch typeKey { case "faith & formation": 0; case "books & publishing": 1; case "website": 2; case "software": 3; case "professional research": 4; case "portfolio & operations": 5; case "type not recorded": 6; default: 7 } }
}

private enum Registry {
    static func read(path: String) throws -> [Project] {
        guard FileManager.default.fileExists(atPath: path) else { throw RegistryError.missing(path) }
        return try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: path, isDirectory: true), includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
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
        return Project(id: metadata["id"] ?? title.lowercased().replacingOccurrences(of: " ", with: "-"), title: title, status: metadata["status"] ?? "unknown", health: metadata["health"] ?? "unknown", domain: metadata["organization"], stage: metadata["stage"], gateState: metadata["gate_state"], milestone: metadata["next_milestone"], action: metadata["next_action"], owner: metadata["owner"], priority: Int(metadata["priority"] ?? ""), gateDate: date(metadata["gate_date"]), updatedAt: date(metadata["updated"] ?? metadata["last_evidence_review"]), plannedHours: Double(metadata["planned_hours_6m"] ?? ""), actualHours: Double(metadata["actual_hours_6m"] ?? ""))
    }
    private static func frontMatter(in content: String) -> [String: String] {
        let lines = content.components(separatedBy: .newlines)
        guard lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") else { return [:] }
        return Dictionary(uniqueKeysWithValues: lines[1..<end].compactMap { line in
            guard let separator = line.firstIndex(of: ":") else { return nil }
            let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\\\""))
            return key.isEmpty ? nil : (key, value)
        })
    }
    private static func date(_ value: String?) -> Date? { guard let value else { return nil }; let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; if let date = fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value) { return date }; let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"; return formatter.date(from: value) }
}
private enum RegistryError: LocalizedError { case missing(String), unreadable; var errorDescription: String? { switch self { case .missing(let path): "The governed project registry was not found at \(path)."; case .unreadable: "The governed project registry could not be read." } } }
