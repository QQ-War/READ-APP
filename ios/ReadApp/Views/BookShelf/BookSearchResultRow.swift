import SwiftUI

struct BookSearchResultRow: View {
    let book: Book
    let onAddToBookshelf: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AsyncImage(url: book.displayCoverUrl.flatMap(URL.init)) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Color.gray.opacity(0.3)
            }
            .frame(width: 60, height: 80)
            .cornerRadius(4)

            VStack(alignment: .leading, spacing: 4) {
                Text(book.name ?? "未知书籍")
                    .font(.headline)
                    .lineLimit(2)
                Text(book.author ?? "未知作者")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(book.intro ?? "")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                if let sourceName = book.sourceDisplayName {
                    Text("来源: \(sourceName)")
                        .font(.caption2)
                        .foregroundColor(.accentColor)
                        .padding(.top, 2)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
    }
}
