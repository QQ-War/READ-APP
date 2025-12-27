import SwiftUI

struct ContentView: View {
    @EnvironmentObject var apiService: APIService
    @StateObject private var preferences = UserPreferences.shared
    
    var body: some View {
        if !preferences.isLoggedIn {
            LoginView()
        } else {
            TabView {
                NavigationView {
                    BookListView()
                }
                .navigationViewStyle(StackNavigationViewStyle())
                .tabItem {
                    Image(systemName: "book.fill")
                    Text("书架")
                }
                
                NavigationView {
                    SourceListView()
                }
                .navigationViewStyle(StackNavigationViewStyle())
                .tabItem {
                    Image(systemName: "list.bullet")
                    Text("书源")
                }
            }
        }
    }
}

