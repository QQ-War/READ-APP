import SwiftUI
import UIKit

struct RssSourceDetailView: View {
    let source: RssSource
    let canEdit: Bool
    let isEditingBusy: Bool
    let onEdit: (() -> Void)?
    let onDelete: (() -> Void)?

    var body: some View {
        Form {
            if let iconUrl = source.sourceIcon, let url = URL(string: iconUrl) {
                Section {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                                .frame(height: 120)
                                .frame(maxWidth: .infinity)
                        default:
                            Image(systemName: "photo")
                                .font(.title)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }

            Section(header: GlassySectionHeader(title: "基本信息")) {
                detailRow(title: "名称", value: source.sourceName ?? "未命名")
                detailRow(title: "链接", value: source.sourceUrl)
                HStack {
                    Text("状态")
                    Spacer()
                    Text(source.enabled ? "已启用" : "已禁用")
                        .foregroundColor(source.enabled ? .green : .secondary)
                }
                Button("复制链接") {
                    UIPasteboard.general.string = source.sourceUrl
                }
            }

            Section(header: GlassySectionHeader(title: "分组与备注")) {
                detailRow(title: "分组", value: source.sourceGroup ?? "未分组")
                if let comment = source.variableComment, !comment.isEmpty {
                    detailRow(title: "备注", value: comment)
                }
            }

            if let login = source.loginUrl, !login.isEmpty || (source.loginUi?.isEmpty == false) {
                Section(header: GlassySectionHeader(title: "登录配置")) {
                    if let login = source.loginUrl, !login.isEmpty {
                        detailRow(title: "登录地址", value: login)
                    }
                    if let loginUi = source.loginUi, !loginUi.isEmpty {
                        detailRow(title: "登录界面", value: loginUi)
                    }
                }
            }

            if canEdit {
                Section(header: GlassySectionHeader(title: "管理")) {
                    Button("编辑订阅源") {
                        onEdit?()
                    }
                    .disabled(isEditingBusy)

                    Button("删除订阅源", role: .destructive) {
                        onDelete?()
                    }
                    .disabled(isEditingBusy)
                }
            }
        }
        .navigationTitle(source.sourceName ?? "订阅详情")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func detailRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .glassyListStyle()
    }
}
