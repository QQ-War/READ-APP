import SwiftUI
import UIKit

struct RssSourceDetailView: View {
    let source: RssSource

    var body: some View {
        Form {
            Section(header: Text("基本信息")) {
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

            Section(header: Text("分组与备注")) {
                detailRow(title: "分组", value: source.sourceGroup ?? "未分组")
                if let comment = source.variableComment, !comment.isEmpty {
                    detailRow(title: "备注", value: comment)
                }
            }

            if let login = source.loginUrl, !login.isEmpty {
                Section(header: Text("登录配置")) {
                    detailRow(title: "登录地址", value: login)
                    if let loginUi = source.loginUi, !loginUi.isEmpty {
                        detailRow(title: "登录界面", value: loginUi)
                    }
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
    }
}
