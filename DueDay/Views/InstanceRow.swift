import SwiftUI

struct InstanceRow: View {
    let instance: BillInstance

    var body: some View {
        let status = instance.status()
        let category = instance.bill?.category ?? .other
        let preset = PresetStore.preset(withID: instance.bill?.presetID)

        HStack(spacing: 12) {
            Image(systemName: preset?.icon ?? category.symbol)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(preset?.color ?? category.color, in: .rect(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(instance.bill?.name ?? "Bill")
                    .font(.headline)
                Text(instance.dueDate.formatted(.dateTime.month(.abbreviated).day().weekday(.abbreviated)))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if let amount = instance.amount {
                    Text(amount.pesoString)
                        .font(.headline)
                } else {
                    Text("Enter amount")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(status.title)
                    .font(.caption)
                    .foregroundStyle(status.color)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
