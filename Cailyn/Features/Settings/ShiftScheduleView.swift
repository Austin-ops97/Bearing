import SwiftUI

struct ShiftScheduleView: View {
    @AppStorage(ShiftSchedule.dayStartKey) private var dayStart = ShiftSchedule.standard.dayStartMinute
    @AppStorage(ShiftSchedule.dayEndKey) private var dayEnd = ShiftSchedule.standard.dayEndMinute
    @AppStorage(ShiftSchedule.nightStartKey) private var nightStart = ShiftSchedule.standard.nightStartMinute
    @AppStorage(ShiftSchedule.nightEndKey) private var nightEnd = ShiftSchedule.standard.nightEndMinute

    var body: some View {
        Form {
            Section {
                LabeledContent("Active Now", value: activeShiftLabel)
            } footer: {
                Text("Events and log entries automatically inherit the shift active at their selected time. You can override the shift on each item.")
            }
            Section("Day Shift") {
                timePicker("Starts", value: $dayStart)
                timePicker("Ends", value: $dayEnd)
            }
            Section("Night Shift") {
                timePicker("Starts", value: $nightStart)
                timePicker("Ends", value: $nightEnd)
            }
            Section("Shift Routines") {
                NavigationLink { RoutinesView() } label: {
                    Label("Manage Shift Checklists", systemImage: "checklist")
                }
                Text("Routines can be assigned to every shift, day shift, or night shift. Add the starter checklists from Routines.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Button("Restore 05:00–17:00 / 17:00–05:00 Defaults") {
                    dayStart = ShiftSchedule.standard.dayStartMinute
                    dayEnd = ShiftSchedule.standard.dayEndMinute
                    nightStart = ShiftSchedule.standard.nightStartMinute
                    nightEnd = ShiftSchedule.standard.nightEndMinute
                }
            }
        }
        .navigationTitle("WORK SHIFTS")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var activeShiftLabel: String {
        ShiftSchedule.stored.shift(containing: .now).map(ShiftSchedule.stored.label(for:)) ?? "Outside configured shifts"
    }

    private func timePicker(_ title: String, value: Binding<Int>) -> some View {
        DatePicker(
            title,
            selection: Binding(
                get: { Self.date(for: value.wrappedValue) },
                set: { value.wrappedValue = Self.minutes(from: $0) }
            ),
            displayedComponents: .hourAndMinute
        )
    }

    private static func date(for minute: Int) -> Date {
        Calendar.current.date(from: DateComponents(hour: minute / 60, minute: minute % 60)) ?? .now
    }

    private static func minutes(from date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
}
