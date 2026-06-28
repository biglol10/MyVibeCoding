import FlowPilotNativeCore
import SwiftUI

struct RulesView: View {
    @EnvironmentObject private var store: FlowPilotReportStore
    @State private var ruleType: RuleType = .domain
    @State private var pattern = ""
    @State private var category: ActivityCategory = .productive
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                editor
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                rulesList
            }
            .padding(28)
        }
        .navigationTitle("분류 규칙")
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("규칙 관리")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("분류 규칙")
                    .font(.largeTitle.bold())
            }
            Spacer()
            Text("\(store.rules.count)개 규칙")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.thinMaterial, in: Capsule())
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Picker("규칙 종류", selection: $ruleType) {
                    ForEach(RuleType.allCases) { type in
                        Text(type.koreanLabel).tag(type)
                    }
                }
                .frame(width: 170)

                TextField("example.com", text: $pattern)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
            }

            HStack(spacing: 12) {
                Picker("분류", selection: $category) {
                    ForEach(ActivityCategory.ruleAssignableCases) { category in
                        Text(category.koreanLabel).tag(category)
                    }
                }
                .frame(width: 170)

                Spacer()

                Button("규칙 추가") {
                    addRule()
                }
                .disabled(pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
    }

    private var rulesList: some View {
        VStack(spacing: 0) {
            ForEach(store.rules) { rule in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(rule.name).font(.headline)
                        Text(rule.pattern)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(rule.ruleType.koreanLabel)
                        .frame(width: 90, alignment: .leading)
                    Text(rule.category.koreanLabel)
                        .foregroundStyle(rule.category.color)
                        .frame(width: 90, alignment: .leading)
                    Text(rule.isBuiltin ? "기본 규칙" : "사용자 규칙")
                        .foregroundStyle(.secondary)
                        .frame(width: 90, alignment: .leading)
                }
                .padding()
                Divider()
            }
        }
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
    }

    private func addRule() {
        do {
            try store.saveRule(ruleType: ruleType, pattern: pattern, category: category)
            pattern = ""
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
