import SwiftUI
import SwiftData

/// All saved bills and accounts, grouped by category.
struct BillsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Bill.name) private var bills: [Bill]

    @AppStorage(selectedProfileKey) private var selectedProfileID = ""
    @State private var accountToAddBill: Bill?
    @State private var billToDelete: Bill?
    /// Starts on the current cutoff, the first chip. A profile without paydays falls back to All.
    @State private var filter: BillFilter = .currentCutoff

    @Query(sort: \BillInstance.dueDate) private var instances: [BillInstance]
    @Query(sort: \Profile.sortOrder) private var profiles: [Profile]

    /// Worked out once per refresh and shared with the filter bar and the list, because reading every
    /// bill's data is what makes this tab slow.
    private func makeEngine(activeBills: [Bill]) -> BillFilterEngine {
        let activeIDs = Set(activeBills.map(\.persistentModelID))
        return BillFilterEngine(
            instances: instances.filter { instance in
                instance.bill.map { activeIDs.contains($0.persistentModelID) } ?? false
            },
            paydays: profiles.first { $0.id.uuidString == selectedProfileID }?.paydays ?? []
        )
    }

    var body: some View {
        let inProfile = bills.filter { $0.isIn(profileID: selectedProfileID) }
        let active = inProfile.filter { !$0.isArchived }
        let archived = inProfile.filter(\.isArchived)
        // Only built when it's needed: for the filter chips and the lists of bills.
        let engine = makeEngine(activeBills: active)

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("BILLS")
                    .font(.barlow(60, weight: .medium, relativeTo: .largeTitle))
                    .foregroundStyle(Theme.ink)

                if inProfile.isEmpty {
                    ContentUnavailableView(
                        "No bills yet",
                        systemImage: "doc.badge.plus",
                        description: Text("Tap + to add Meralco, Maynilad, rent or any other bill.")
                    )
                }

                if !inProfile.isEmpty {
                    BillFilterBar(selection: $filter, selectedProfileID: selectedProfileID, engine: engine)
                }

                // What's still unpaid: the full overview, or just the list for the chosen filter.
                if !inProfile.isEmpty, filter != .accounts {
                    UnpaidByCutoffView(selectedProfileID: selectedProfileID, filter: filter, engine: engine)
                }

                // The saved accounts, by category. Shown under "All" and "Accounts".
                if filter == .all || filter == .accounts {
                    if !inProfile.isEmpty {
                        Text("ALL ACCOUNTS")
                            .font(.barlow(30, relativeTo: .title))
                            .foregroundStyle(Theme.ink)
                            .padding(.bottom, -12)
                    }

                    ForEach(BillCategory.allCases) { category in
                        let items = active.filter { $0.category == category }
                        if !items.isEmpty { section(category.title, items) }
                    }

                    if !archived.isEmpty { section("Archived", archived) }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .navigationDestination(for: Bill.self) { BillDetailView(bill: $0) }
        .ownsTopOfScreen()
        .overlay(alignment: .topTrailing) {
            // Same floating profile button as on Today.
            ProfileSwitcher(selectedID: $selectedProfileID)
                .font(.outfit(14, weight: .semibold, relativeTo: .subheadline))
                .secondaryButton(tint: Theme.ink)
                .padding(.trailing, 20)
                .padding(.top, 4)
        }
        .sheet(item: $accountToAddBill) { AddBillEntrySheet(bill: $0) }
        .confirmationDialog(
            "Delete \(billToDelete?.name ?? "bill")?",
            isPresented: Binding(get: { billToDelete != nil }, set: { if !$0 { billToDelete = nil } }),
            titleVisibility: .visible,
            presenting: billToDelete
        ) { bill in
            Button("Delete \(bill.name) and Its History", role: .destructive) {
                modelContext.delete(bill)
                billToDelete = nil
            }
        } message: { bill in
            Text("This removes all \((bill.instances ?? []).count) of its bills and payments. To keep the history, archive it instead.")
        }
    }

    private func section(_ title: String, _ items: [Bill]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(title)
            ForEach(items) { bill in
                NavigationLink(value: bill) {
                    BillCard(bill: bill)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    if bill.amountType == .variable && !bill.isArchived {
                        Button("Add a bill", systemImage: "plus") { accountToAddBill = bill }
                    }
                    Button("Delete", systemImage: "trash", role: .destructive) { billToDelete = bill }
                }
            }
        }
    }
}

/// One row on the Bills tab: the bill, its account, and what's next.
private struct BillCard: View {
    let bill: Bill

    /// The nearest unpaid bill.
    private var next: BillInstance? {
        let unpaid = (bill.instances ?? []).filter { !$0.isPaid }.sorted { $0.dueDate < $1.dueDate }
        return unpaid.first { $0.status() != .overdue } ?? unpaid.first
    }

    private var subtitle: String {
        var parts: [String] = []
        if let account = bill.maskedAccountNumber { parts.append(account) }
        if bill.amountType == .variable {
            parts.append("Variable")
        } else if bill.recurrence == .once {
            parts.append("One-time")
        } else {
            parts.append(bill.recurrence.title)
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        // Found once: it reads all of this account's bills.
        let next = next
        HStack(spacing: 12) {
            LogoBadge(logo: bill.logoData, symbol: bill.displayIcon, color: bill.displayColor, size: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(bill.name)
                    .font(.outfit(17, weight: .semibold, relativeTo: .headline))
                    .foregroundStyle(Theme.ink)
                Text(subtitle)
                    .font(.outfit(13, relativeTo: .footnote))
                    .foregroundStyle(Theme.mutedInk)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            trailing(next: next)
        }
        .padding(14)
        .glassSurface(cornerRadius: 18)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func trailing(next: BillInstance?) -> some View {
        if bill.isArchived {
            StatusChip(text: "ARCHIVED", foreground: Theme.mutedInk, background: Theme.track)
        } else if let next {
            VStack(alignment: .trailing, spacing: 2) {
                Text(next.dueDate.formatted(.dateTime.month(.abbreviated).day()).uppercased())
                    .font(.barlow(22, weight: .semibold, relativeTo: .title3))
                    .foregroundStyle(next.status() == .overdue ? Theme.danger : Theme.ink)
                Text(next.amount?.pesoString ?? "—")
                    .font(.outfit(13, relativeTo: .footnote))
                    .foregroundStyle(Theme.mutedInk)
            }
        } else if bill.isAwaitingBill() {
            StatusChip(text: "BILL DUE?", foreground: Theme.warning, background: Theme.warningFill)
        } else if bill.amountType == .variable {
            StatusChip(text: "ADD BILL", foreground: Theme.accent, background: Theme.accent.opacity(0.12))
        } else {
            Text("All paid")
                .font(.outfit(13, relativeTo: .footnote))
                .foregroundStyle(Theme.paid)
        }
    }
}
