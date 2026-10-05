import SwiftData
import SwiftUI

private enum PlanScale: String, CaseIterable, Identifiable {
    case day = "DAY"
    case week = "WEEK"
    case month = "MONTH"
    var id: String { rawValue }
}

struct PlanView: View {
    @Environment(\.modelContext) private var context
    @Query private var actions: [CailynAction]
    @Query private var events: [CailynCalendarEvent]
    @State private var scale: PlanScale = .day
    @State private var selectedDate = Date.now
    @State private var showsNewEvent = false

    var body: some View {
        ZStack {
            PaperBackground()
            VStack(spacing: 0) {
                Picker("Planning range", selection: $scale) {
                    ForEach(PlanScale.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 22)
                .padding(.vertical, 14)

                switch scale {
                case .day: DayPlanView(date: $selectedDate, actions: actions, events: events)
                case .week: WeekPlanView(date: $selectedDate, actions: actions, events: events) { scale = .day }
                case .month: MonthPlanView(date: $selectedDate, actions: actions, events: events) { scale = .day }
                }
            }
        }
        .navigationTitle("PLAN")
        .toolbar {
            Button { showsNewEvent = true } label: { Label("Add Event", systemImage: "plus") }
        }
        .sheet(isPresented: $showsNewEvent) { EventEditorView(suggestedDate: selectedDate) }
    }
}

private struct DayPlanView: View {
    @Binding var date: Date
    let actions: [CailynAction]
    let events: [CailynCalendarEvent]

    private var dayActions: [CailynAction] { PlanningEngine.actions(actions, on: date).sorted { AttentionEngine.rank($0, $1) } }
    private var dayEvents: [CailynCalendarEvent] { PlanningEngine.events(events, on: date) }
    private var summary: DayPlanSummary { PlanningEngine.summary(actions: actions, events: events, on: date) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                DateNavigator(date: $date, unit: .day)
                workloadSummary

                if let now = currentItem {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeading(title: "NOW")
                        Label(now, systemImage: "location.fill").font(.title3.weight(.semibold)).foregroundStyle(CailynTheme.champagne)
                    }
                    .cailynSurface()
                }

                VStack(alignment: .leading, spacing: 0) {
                    SectionHeading(title: "EVENTS", trailing: "\(dayEvents.count)")
                    if dayEvents.isEmpty { EmptyPlanRow(text: "No events scheduled.") }
                    ForEach(dayEvents) { CalendarEventRow(event: $0) }
                }

                VStack(alignment: .leading, spacing: 0) {
                    SectionHeading(title: "ACTIONS", trailing: "\(dayActions.count)")
                    if dayActions.isEmpty { EmptyPlanRow(text: "No actions planned for this day.") }
                    ForEach(dayActions) { ActionSummaryRow(action: $0) }
                }
            }
            .padding(22).frame(maxWidth: 900).frame(maxWidth: .infinity)
        }
    }

    private var currentItem: String? {
        guard Calendar.current.isDateInToday(date) else { return nil }
        if let active = dayEvents.first(where: { $0.startAt <= .now && $0.endAt >= .now }) { return active.title }
        return dayActions.first?.title
    }

    private var workloadSummary: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("\(summary.actionCount) Actions  ·  \(summary.eventCount) Events").font(.headline)
                Text("Estimated workload: \(PlanningEngine.durationText(minutes: summary.estimatedWorkMinutes))")
                Text("Available working time: \(PlanningEngine.durationText(minutes: summary.availableMinutes))")
            }
            .font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            OperationalBadge(
                text: summary.isFeasible ? "Feasible" : "Over capacity · \(PlanningEngine.durationText(minutes: summary.overCapacityMinutes))",
                tone: summary.isFeasible ? .normal : .urgent
            )
        }
        .cailynSurface()
        .accessibilityIdentifier("plan.workloadSummary")
    }
}

private struct WeekPlanView: View {
    @Binding var date: Date
    let actions: [CailynAction]
    let events: [CailynCalendarEvent]
    let openDay: () -> Void

    private var days: [Date] {
        let calendar = Calendar.current
        let interval = calendar.dateInterval(of: .weekOfYear, for: date)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: interval?.start ?? date) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                DateNavigator(date: $date, unit: .weekOfYear)
                ForEach(days, id: \.self) { day in
                    let summary = PlanningEngine.summary(actions: actions, events: events, on: day)
                    Button {
                        date = day
                        openDay()
                    } label: {
                        HStack(spacing: 18) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(day.formatted(.dateTime.weekday(.abbreviated))).font(.system(.caption, design: .rounded, weight: .bold)).tracking(1.2)
                                Text(day.formatted(.dateTime.month(.abbreviated).day())).font(.system(.title3, design: .serif, weight: .semibold))
                            }
                            .frame(width: 78, alignment: .leading)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(summary.actionCount) Actions  ·  \(summary.eventCount) Events").font(.headline)
                                Text("\(PlanningEngine.durationText(minutes: summary.estimatedWorkMinutes)) estimated").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            OperationalBadge(text: PlanningEngine.intensity(for: summary).rawValue, tone: summary.isFeasible ? .normal : .urgent)
                        }
                        .cailynSurface()
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(22).frame(maxWidth: 820).frame(maxWidth: .infinity)
        }
    }
}

private struct MonthPlanView: View {
    @Binding var date: Date
    let actions: [CailynAction]
    let events: [CailynCalendarEvent]
    let openDay: () -> Void

    private var cells: [Date?] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: date),
              let dayRange = calendar.range(of: .day, in: .month, for: date) else { return [] }
        let weekday = calendar.component(.weekday, from: interval.start)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        return Array(repeating: nil, count: leading) + dayRange.compactMap {
            calendar.date(bySetting: .day, value: $0, of: interval.start)
        }
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                DateNavigator(date: $date, unit: .month)
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(Calendar.current.veryShortWeekdaySymbols, id: \.self) {
                        Text($0).font(.caption2.weight(.bold)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    }
                    ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                        if let day = cell {
                            let summary = PlanningEngine.summary(actions: actions, events: events, on: day)
                            Button {
                                date = day
                                openDay()
                            } label: {
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(day.formatted(.dateTime.day())).font(.system(.subheadline, design: .monospaced, weight: Calendar.current.isDateInToday(day) ? .bold : .regular))
                                    Circle()
                                        .fill(intensityColor(PlanningEngine.intensity(for: summary)))
                                        .frame(width: 7, height: 7)
                                        .opacity(summary.actionCount + summary.eventCount == 0 ? 0 : 1)
                                }
                                .padding(8).frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
                                .background(CailynTheme.paperRaised.opacity(0.8), in: RoundedRectangle(cornerRadius: 9))
                                .overlay { RoundedRectangle(cornerRadius: 9).stroke(Calendar.current.isDateInToday(day) ? CailynTheme.champagne : CailynTheme.line, lineWidth: 0.8) }
                                .foregroundStyle(.primary)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Color.clear.frame(minHeight: 58)
                        }
                    }
                }
            }
            .padding(22).frame(maxWidth: 920).frame(maxWidth: .infinity)
        }
    }

    private func intensityColor(_ intensity: WorkloadIntensity) -> Color {
        switch intensity {
        case .light: CailynTheme.champagneMuted
        case .normal: CailynTheme.champagne
        case .heavy: CailynTheme.champagneGlow
        case .overloaded: CailynTheme.urgent
        }
    }
}

private struct DateNavigator: View {
    @Binding var date: Date
    let unit: Calendar.Component

    var body: some View {
        HStack {
            Button { move(-1) } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Previous")
            Spacer()
            Button { date = .now } label: {
                Text(title).font(.system(.title3, design: .serif, weight: .semibold)).foregroundStyle(.primary)
            }
            Spacer()
            Button { move(1) } label: { Image(systemName: "chevron.right") }.accessibilityLabel("Next")
        }
    }

    private var title: String {
        switch unit {
        case .month: date.formatted(.dateTime.month(.wide).year())
        case .weekOfYear: "Week of \(date.formatted(.dateTime.month(.abbreviated).day()))"
        default: date.formatted(.dateTime.weekday(.wide).month(.wide).day())
        }
    }

    private func move(_ value: Int) { date = Calendar.current.date(byAdding: unit, value: value, to: date) ?? date }
}

private struct CalendarEventRow: View {
    let event: CailynCalendarEvent
    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(event.startAt.formatted(date: .omitted, time: .shortened)).font(.system(.subheadline, design: .monospaced, weight: .semibold)).foregroundStyle(CailynTheme.champagne)
                Text(event.endAt.formatted(date: .omitted, time: .shortened)).font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
            }
            .frame(width: 70, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title).font(.headline)
                if event.preparationMinutes > 0 { Text("Preparation · \(event.preparationMinutes)m").font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            OperationalBadge(text: event.source.label, tone: .neutral)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(CailynTheme.line).frame(height: 0.5) }
    }
}

private struct EmptyPlanRow: View {
    let text: String
    var body: some View { Text(text).font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 18) }
}
