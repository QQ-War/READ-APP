import SwiftUI

struct SourceEditView: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var jsonContent: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showSuccessMessage = false
    
    // If provided, we are editing an existing source
    var sourceId: String?
    
    var body: some View {
        VStack {
            if isLoading {
                ProgressView("正在处理...")
            } else {
                TextEditor(text: $jsonContent)
                    .font(.system(.body, design: .monospaced)) // Monospaced font for code
                    .padding()
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                    )
                    .padding()
            }
            
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }
        }
        .navigationTitle(sourceId == nil ? "新建书源" : "编辑书源")
        .navigationBarTitleDisplayMode(.inline)
        .ifAvailableHideTabBar()
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("保存") {
                    saveSource()
                }
                .disabled(jsonContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
            }
        }
        .onAppear {
            if let id = sourceId, jsonContent.isEmpty {
                loadSourceDetail(id: id)
            }
        }
        .alert("保存成功", isPresented: $showSuccessMessage) {
            Button("确定") {
                presentationMode.wrappedValue.dismiss()
            }
        }
    }
    
    private func loadSourceDetail(id: String) {
        isLoading = true
        Task {
            do {
                let json = try await APIService.shared.getBookSourceDetail(id: id)
                await MainActor.run {
                    self.jsonContent = json
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "加载失败: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
    
    private func saveSource() {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                try await APIService.shared.saveBookSource(jsonContent: jsonContent)
                await MainActor.run {
                    self.isLoading = false
                    self.showSuccessMessage = true
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "保存失败: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
}

struct SourceEditView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            SourceEditView()
        }
    }
}
