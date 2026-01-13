import SwiftUI

struct LogView: View {
    @State private var logText: String = ""
    @State private var showingCopyAlert = false
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if logText.isEmpty {
                    VStack {
                        Spacer()
                        ProgressView("正在加载日志...")
                        Spacer()
                    }
                } else {
                    NativeLogTextView(text: logText)
                        .edgesIgnoringSafeArea(.bottom)
                }
                
                Divider()
                
                HStack(spacing: 20) {
                    Button(action: {
                        UIPasteboard.general.string = logText
                        showingCopyAlert = true
                    }) {
                        Label("全部复制", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    
                    Button(action: {
                        LogManager.shared.clearLogs()
                        refreshLogs()
                    }) {
                        Label("清空日志", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red.opacity(0.1))
                            .foregroundColor(.red)
                            .cornerRadius(10)
                    }
                }
                .padding()
            }
            .navigationTitle("系统日志")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: refreshLogs) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .onAppear(perform: refreshLogs)
            .alert("已复制", isPresented: $showingCopyAlert) {
                Button("确定", role: .cancel) { }
            } message: {
                Text("日志已复制到剪贴板")
            }
        }
    }
    
    private func refreshLogs() {
        logText = LogManager.shared.getAllLogs()
    }
}

struct LogView_Previews: PreviewProvider {
    static var previews: some View {
        LogView()
    }
}

// MARK: - Native UITextView Wrapper
struct NativeLogTextView: UIViewRepresentable {
    let text: String
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        
        // 确保支持长按选取
        textView.dataDetectorTypes = []
        
        // 自动滚动到最后一行（可选，但通常日志查看需要）
        return textView
    }
    
    func updateUIView(_ uiView: UITextView, context: Context) {
        uiView.text = text
        // 自动滚动到底部以便查看最新日志
        if !text.isEmpty {
            let range = NSRange(location: text.count - 1, length: 1)
            uiView.scrollRangeToVisible(range)
        }
    }
}
