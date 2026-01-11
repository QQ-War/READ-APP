import SwiftUI
import UIKit

struct TextSelectionHelperSheet: View {
    let originalText: String
    let onConfirm: (String) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var selectedText: String = ""
    
    // 截取逻辑
    private var displayLines: String {
        if originalText.count > 500 {
            return String(originalText.prefix(500))
        }
        return originalText
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if originalText.count > 500 {
                    Text("提示：段落过长，已截取前 500 个字符")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                }
                
                NativeTextViewWrapper(text: displayLines, selectedText: $selectedText)
                    .padding()
                
                Divider()
                
                HStack {
                    Button(action: { dismiss() }) {
                        Text("取消")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(10)
                    }
                    
                    Button(action: {
                        onConfirm(selectedText.isEmpty ? displayLines : selectedText)
                        dismiss()
                    }) {
                        Text(selectedText.isEmpty ? "净化全段" : "净化选定内容")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                }
                .padding()
            }
            .navigationTitle("精确选择规则内容")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct NativeTextViewWrapper: UIViewRepresentable {
    let text: String
    @Binding var selectedText: String
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.font = .systemFont(ofSize: 18)
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = .clear
        textView.delegate = context.coordinator
        
        // 增加边距
        textView.textContainerInset = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        
        // 允许弹出菜单
        textView.becomeFirstResponder()
        
        return textView
    }
    
    func updateUIView(_ uiView: UITextView, context: Context) {
        uiView.text = text
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UITextViewDelegate {
        var parent: NativeTextViewWrapper
        
        init(_ parent: NativeTextViewWrapper) {
            self.parent = parent
        }
        
        func textViewDidChangeSelection(_ textView: UITextView) {
            if let range = textView.selectedTextRange {
                let selected = textView.text(in: range) ?? ""
                DispatchQueue.main.async {
                    self.parent.selectedText = selected
                }
            }
        }
    }
}
