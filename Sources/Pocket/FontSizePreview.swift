import SwiftUI

struct FontSizePreview: View {
    var fontSize: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("“The best way to spread Christmas cheer is singing loud for all to hear.”")
                .font(.system(size: fontSize))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .frame(height: 96)
                .background(.black, in: RoundedRectangle(cornerRadius: 10))
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("fontPreview")
    }
}
