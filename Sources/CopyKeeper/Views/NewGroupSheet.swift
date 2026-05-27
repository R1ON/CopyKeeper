import SwiftUI

struct NewGroupSheet: View {
    @EnvironmentObject var store: ClipboardStore
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var retention: RetentionPeriod = .never

    var body: some View {
        VStack(spacing: 20) {
            Text("Новая группа")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Название группы")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("Название", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Период хранения")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Picker("Хранение", selection: $retention) {
                    ForEach(RetentionPeriod.allCases) { period in
                        Text(period.rawValue).tag(period)
                    }
                }
                .pickerStyle(.menu)
            }

            HStack(spacing: 12) {
                Button("Отмена") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button("Создать") {
                    store.createGroup(name: name, retention: retention)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 320)
    }
}
