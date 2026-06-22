import SwiftUI

struct SparklineView: View {
    let values: [Double]

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            context.stroke(Path(rect), with: .color(.primary.opacity(0.08)), lineWidth: 1)

            guard values.count > 1 else { return }
            let clamped = values.map { min(100, max(0, $0)) }
            let step = size.width / CGFloat(max(1, clamped.count - 1))
            var path = Path()

            for (index, value) in clamped.enumerated() {
                let x = CGFloat(index) * step
                let y = size.height - (CGFloat(value) / 100 * size.height)
                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }

            context.stroke(path, with: .color(.accentColor), lineWidth: 2)
        }
        .background(Color.primary.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}
