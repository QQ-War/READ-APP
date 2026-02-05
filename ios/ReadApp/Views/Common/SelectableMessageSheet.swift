import SwiftUI
import UIKit

struct SelectableMessage: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

struct SelectableMessageSheet: View {
    let title: String
    let message: String
    var onDismiss: (() -> Void)?

    var body: some View {
        NavigationView {
            ScrollView {
                Text(message)
                    .textSelection(.enabled)
                    .font(.system(size: 14))
                    .foregroundColor(.primary)
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("复制") { UIPasteboard.general.string = message }
                        .glassyToolbarButton()
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") { onDismiss?() }
                        .glassyToolbarButton()
                }
            }
            .glassyListStyle()
        }
    }
}
