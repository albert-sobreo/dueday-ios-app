import SwiftUI
import SwiftData

struct BillsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Bill.name) private var bills: [Bill]

    @State private var showingNewBill = false
    @State private var billToEdit: Bill?

    private var active: [Bill] { bills.filter { !$0.isArchived } }
    private var archived: [Bill] { bills.filter(\.isArchived) }

    var body: some View {
        List {
            if bills.isEmpty {
                ContentUnavailableView(
                    "No bills",
                    systemImage: "doc.badge.plus",
                    description: Text("Tap + to add Meralco, Maynilad, rent or any other bill.")
                )
            }

            if !active.isEmpty {
                Section { rows(active) }
            }
            if !archived.isEmpty {
                Section("Archived") { rows(archived) }
            }
        }
        .navigationTitle("Bills")
        .toolbar {
            Button("Add Bill", systemImage: "plus") { showingNewBill = true }
        }
        .sheet(isPresented: $showingNewBill) { BillFormView(bill: nil) }
        .sheet(item: $billToEdit) { BillFormView(bill: $0) }
    }

    private func rows(_ items: [Bill]) -> some View {
        ForEach(items) { bill in
            Button { billToEdit = bill } label: {
                BillRow(bill: bill)
            }
            .buttonStyle(.plain)
            .swipeActions(edge: .trailing) {
                Button("Delete", systemImage: "trash", role: .destructive) {
                    modelContext.delete(bill)
                }
                Button(bill.isArchived ? "Restore" : "Archive", systemImage: "archivebox") {
                    setArchived(bill, !bill.isArchived)
                }
                .tint(.orange)
            }
        }
    }

    private func setArchived(_ bill: Bill, _ archived: Bool) {
        bill.isArchived = archived
        if archived {
            // Archiving stops future bills, but paid history stays.
            for instance in bill.instances ?? [] where !instance.isPaid {
                modelContext.delete(instance)
            }
        } else {
            InstanceGenerator.generate(for: bill, in: modelContext)
        }
    }
}

private struct BillRow: View {
    let bill: Bill

    var body: some View {
        let preset = PresetStore.preset(withID: bill.presetID)
        HStack(spacing: 12) {
            Image(systemName: preset?.icon ?? bill.category.symbol)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(preset?.color ?? bill.category.color, in: .rect(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text(bill.name).font(.headline)
                Text("\(bill.recurrence.title) · due on the \(bill.dueDay.formatted(.number))\(ordinalSuffix(bill.dueDay))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let amount = bill.defaultAmount, bill.amountType == .fixed {
                Text(amount.pesoString).foregroundStyle(.secondary)
            } else if bill.amountType == .variable {
                Text("Varies").foregroundStyle(.secondary)
            }
        }
        .contentShape(.rect)
    }

    private func ordinalSuffix(_ day: Int) -> String {
        if (11...13).contains(day % 100) { return "th" }
        switch day % 10 {
        case 1: return "st"
        case 2: return "nd"
        case 3: return "rd"
        default: return "th"
        }
    }
}
