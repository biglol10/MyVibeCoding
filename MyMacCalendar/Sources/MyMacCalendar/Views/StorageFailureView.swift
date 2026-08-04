import AppKit
import SwiftUI

struct StorageFailureView: View {
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(.orange)

            VStack(spacing: 7) {
                Text("캘린더 데이터를 열 수 없습니다")
                    .font(.system(size: 20, weight: .bold))
                Text("데이터 손실을 막기 위해 편집 기능을 시작하지 않았습니다. 앱을 종료한 뒤 저장 공간과 접근 권한을 확인해 주세요.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            Button("앱 종료") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(42)
        .frame(minWidth: 560, minHeight: 320)
    }
}
