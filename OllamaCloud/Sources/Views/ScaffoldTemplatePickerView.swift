import SwiftUI

struct ScaffoldTemplatePickerView: View {
    let onSelect: (ReasoningScaffoldTemplate) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(ReasoningScaffoldTemplate.allCases) { template in
                    Button {
                        onSelect(template)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(template.rawValue)
                                .font(.app(15, weight: .medium))
                                .foregroundStyle(Color.textPrimary)
                            Text(template.summary)
                                .font(.app(12))
                                .foregroundStyle(Color.textSecondary)
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.bgPrimary)
            .navigationTitle("Templates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("CANCEL") { dismiss() }
                        .font(.appLabel(11))
                        .tracking(2)
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
    }
}
