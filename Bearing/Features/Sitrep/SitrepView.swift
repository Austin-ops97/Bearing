import SwiftData
import SwiftUI

struct SitrepView: View {
    @Query private var actions: [BearingAction]
    @Query private var assets: [BearingAsset]
    @Query private var routines: [BearingRoutine]
    let onSearch: () -> Void

    private var priorityActions: [BearingAction] {
        actions.filter { $0.status != .waiting && AttentionEngine.requiresAttention($0) }
            .sorted { AttentionEngine.rank($0, $1) }
            .prefix(3).map { $0 }
    }

    private var waiting: [BearingAction] {
        actions.filter { $0.status == .waiting && $0.status != .complete }
            .sorted { ($0.followUpAt ?? .distantFuture) < ($1.followUpAt ?? .distantFuture) }
            .prefix(3).map { $0 }
    }

    private var attentionCount: Int {
        actions.filter { AttentionEngine.requiresAttention($0) }.count + assets.filter { $0.status == .attention || $0.status == .unavailable }.count
    }

    var body: some View {
        ZStack {
            PaperBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 28) {
                            VStack(spacing: 28) { nextSection; prioritySection }.frame(maxWidth: .infinity)
                            VStack(spacing: 28) { waitingSection; opsSection; routinesSection }.frame(maxWidth: .infinity)
                        }
                        VStack(spacing: 28) { nextSection; prioritySection; waitingSection; opsSection; routinesSection }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 24)
                .frame(maxWidth: 1100)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("SITREP")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onSearch) { Image(systemName: "magnifyingglass") }
                    .accessibilityLabel("Search Bearing")
                    .accessibilityIdentifier("search.open")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.system(.title, design: .serif, weight: .semibold))
            Text(attentionCount == 1 ? "1 thing needs your attention." : "\(attentionCount) things need your attention.")
                .font(.title3)
                .foregroundStyle(attentionCount > 0 ? BearingTheme.urgent : BearingTheme.olive)
                .accessibilityIdentifier("sitrep.attentionSummary")
        }
    }

    private var nextSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading(title: "NEXT", trailing: "TODAY")
            TimelineRow(time: "07:00", title: "Shift Turnover")
            TimelineRow(time: "08:30", title: "Unit Checks")
            TimelineRow(time: "09:30", title: "Operations Meeting")
        }
    }

    private var prioritySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading(title: "PRIORITY")
            if priorityActions.isEmpty {
                QuietState(text: "No actions require immediate attention.")
            } else {
                ForEach(priorityActions) { action in ActionSummaryRow(action: action) }
            }
        }
    }

    private var waitingSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading(title: "WAITING ON")
            if waiting.isEmpty {
                QuietState(text: "Nothing is waiting on someone else.")
            } else {
                ForEach(waiting) { action in WaitingSummaryRow(action: action) }
            }
        }
    }

    private var opsSection: some View {
        NavigationLink {
            OpsView()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 7) {
                    SectionHeading(title: "OPS")
                    let attention = assets.filter { $0.status != .normal }.count
                    Text(attention == 0 ? "\(assets.count) / \(assets.count) NORMAL" : "\(attention) REQUIRES ATTENTION")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundStyle(attention == 0 ? BearingTheme.olive : BearingTheme.urgent)
                }
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }
            .bearingSurface()
        }
        .buttonStyle(.plain)
    }

    private var routinesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading(title: "ROUTINES")
            let due = routines.filter { $0.isEnabled && ($0.nextDue ?? .distantFuture) <= .now }
            if due.isEmpty {
                QuietState(text: "No routines are due.")
            } else {
                ForEach(due) { routine in
                    HStack {
                        Image(systemName: "checklist").foregroundStyle(BearingTheme.olive)
                        VStack(alignment: .leading) {
                            Text(routine.title).font(.headline)
                            Text(routine.scheduleDescription).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        OperationalBadge(text: "Due", tone: .attention)
                    }
                    .padding(.vertical, 12)
                }
            }
        }
    }
}

private struct TimelineRow: View {
    let time: String
    let title: String
    var body: some View {
        HStack(spacing: 18) {
            Text(time).font(.system(.subheadline, design: .monospaced, weight: .medium)).foregroundStyle(BearingTheme.olive)
            Text(title).font(.body.weight(.medium))
            Spacer()
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(BearingTheme.line).frame(height: 0.5) }
    }
}

struct ActionSummaryRow: View {
    let action: BearingAction
    var body: some View {
        NavigationLink { ActionDetailView(action: action) } label: {
            HStack(spacing: 12) {
                Rectangle().fill(action.priority == .immediate ? BearingTheme.urgent : BearingTheme.amber).frame(width: 3, height: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text(action.asset?.name ?? action.source ?? action.priority.code)
                        .font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    Text(action.title).font(.body.weight(.semibold)).foregroundStyle(.primary)
                }
                Spacer()
                if let dueAt = action.dueAt {
                    OperationalBadge(text: dueAt < .now ? "Overdue" : dueAt.formatted(date: .omitted, time: .shortened), tone: dueAt < .now ? .urgent : .attention)
                }
            }
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }
}

private struct WaitingSummaryRow: View {
    let action: BearingAction
    var body: some View {
        NavigationLink { ActionDetailView(action: action) } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(action.person?.displayName ?? "Unassigned").font(.headline).foregroundStyle(.primary)
                    Text(action.title).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                if let since = action.waitingSince {
                    Text("Waiting \(AttentionEngine.waitingDuration(from: since))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }
}

private struct QuietState: View {
    let text: String
    var body: some View {
        Text(text).font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 18)
    }
}

