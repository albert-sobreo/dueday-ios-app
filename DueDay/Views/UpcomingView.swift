import SwiftUI
import SwiftData

struct UpcomingView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BillInstance.dueDate) private var instances: [BillInstance]

    @State private var instanceToPay: BillInstance?

    private var unpaid: [BillInstance] { instances.filter { !$0.isPaid && $0.bill?.isArchived != true } }

    private var overdue: [BillInstance] { unpaid.filter { $0.status() == .overdue } }
    private var comingUp: [BillInstance] { unpaid.filter { $0.status() != .overdue } }

    /// Most recent payments first.
    private var recentlyPaid: [BillInstance] {
        Array(instances.filter(\.isPaid).sorted { $0.dueDate > $1.dueDate }.prefix(10))
    }

    var body: some View {
        List {
            if overdue.isEmpty && comingUp.isEmpty && recentlyPaid.isEmpty {
                ContentUnavailableView(
                    "No bills yet",
                    systemImage: "calendar.badge.plus",
                    description: Text("Add a bill from the Bills tab and it will show up here.")
                )
            }

            if !overdue.isEmpty {
                Section("Overdue") { rows(overdue) }
            }
            if !comingUp.isEmpty {
                Section("Coming up") { rows(comingUp) }
            }
            if !recentlyPaid.isEmpty {
                Section("Recently paid") {
                    ForEach(recentlyPaid) { instance in
                        InstanceRow(instance: instance)
                            .swipeActions {
                                Button("Undo") { instance.markUnpaid(in: modelContext) }
                                    .tint(.orange)
                            }
                    }
                }
            }
        }
        .navigationTitle("DueDay")
        .sheet(item: $instanceToPay) { MarkPaidSheet(instance: $0) }
    }

    private func rows(_ items: [BillInstance]) -> some View {
        ForEach(items) { instance in
            InstanceRow(instance: instance)
                .swipeActions(edge: .trailing) {
                    Button("Paid", systemImage: "checkmark") { pay(instance) }
                        .tint(.green)
                }
                .contextMenu {
                    Button("Mark as paid…", systemImage: "checkmark.circle") {
                        instanceToPay = instance
                    }
                }
        }
    }

    /// One tap for bills with a known amount; otherwise ask for the amount first.
    private func pay(_ instance: BillInstance) {
        if let amount = instance.amount, amount > 0 {
            instance.markPaid(
                amount: amount,
                method: instance.bill?.defaultPaymentMethod,
                in: modelContext
            )
        } else {
            instanceToPay = instance
        }
    }
}
