import FlowPilotNativeCore
import SwiftUI

struct RulesView: View {
    @EnvironmentObject private var store: FlowPilotReportStore
    @State private var ruleType: RuleType = .domain
    @State private var pattern = ""
    @State private var category: ActivityCategory = .productive
    @State private var searchText = ""
    @State private var errorMessage: String?
    @State private var rulePendingDeletion: ClassificationRule?
    @State private var isDeleteConfirmationPresented = false

    private var visibleRules: [ClassificationRule] {
        RuleListFiltering.visibleRules(from: store.rules, query: searchText)
    }

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
                searchBar
                rulesList
            }
            .padding(28)
        }
        .navigationTitle("분류 규칙")
        .confirmationDialog(
            "규칙을 삭제할까요?",
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("삭제", role: .destructive) {
                if let rule = rulePendingDeletion {
                    deleteRule(rule)
                }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("'\(rulePendingDeletion?.name ?? "선택한 규칙")' 사용자 규칙을 삭제합니다. 기본 규칙은 삭제하지 않고 비활성화할 수 있습니다.")
        }
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
            countBadge("\(store.rules.count)개 규칙")
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

    private var searchBar: some View {
        HStack(alignment: .center, spacing: 12) {
            TextField("이름 또는 패턴 검색", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)

            countBadge("\(visibleRules.count) / \(store.rules.count)개 표시")
                .accessibilityLabel("표시 중인 규칙 \(visibleRules.count)개, 전체 \(store.rules.count)개")
        }
    }

    private var rulesList: some View {
        VStack(spacing: 0) {
            if visibleRules.isEmpty {
                Text("검색 결과가 없습니다")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
            } else {
                ForEach(visibleRules) { rule in
                    ruleRow(rule)
                    if rule.id != visibleRules.last?.id {
                        Divider()
                            .padding(.leading, 16)
                    }
                }
            }
        }
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
    }

    private func ruleRow(_ rule: ClassificationRule) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 16) {
                ruleIdentity(rule)
                    .frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)
                ruleMetadata(rule)
            }

            VStack(alignment: .leading, spacing: 10) {
                ruleIdentity(rule)
                ruleMetadata(rule)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func ruleIdentity(_ rule: ClassificationRule) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(rule.name)
                .font(.headline)
                .lineLimit(1)
            Text(rule.pattern)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func ruleMetadata(_ rule: ClassificationRule) -> some View {
        HStack(spacing: 8) {
            metadataBadge(rule.ruleType.koreanLabel)
            metadataBadge(rule.category.koreanLabel, color: rule.category.color)
            if !rule.isEnabled {
                metadataBadge("비활성")
            }
            Text(rule.isBuiltin ? "기본 규칙" : "사용자 규칙")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(minWidth: 72, alignment: .trailing)

            Button(rule.isEnabled ? "비활성" : "활성") {
                setRuleEnabled(rule, isEnabled: !rule.isEnabled)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            if !rule.isBuiltin {
                Button("삭제", role: .destructive) {
                    rulePendingDeletion = rule
                    isDeleteConfirmationPresented = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private func metadataBadge(_ label: String, color: Color? = nil) -> some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color ?? .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background((color ?? Color.secondary).opacity(0.12), in: Capsule())
    }

    private func countBadge(_ label: String) -> some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.thinMaterial, in: Capsule())
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

    private func setRuleEnabled(_ rule: ClassificationRule, isEnabled: Bool) {
        do {
            try store.setRuleEnabled(id: rule.id, isEnabled: isEnabled)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteRule(_ rule: ClassificationRule) {
        do {
            try store.deleteUserRule(id: rule.id)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
