import SwiftUI

// MARK: - Navigation Tab
enum NavigationTab: String, CaseIterable {
    case home = "nav_home"
    case themeStore = "nav_theme_store"
    case settings = "nav_settings"
    case about = "nav_about"
    case apply = "nav_apply"

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .themeStore: return "square.grid.2x2.fill"
        case .settings: return "gearshape.fill"
        case .apply: return "checkmark.circle.fill"
        case .about: return "info.circle.fill"
        }
    }

    var localizedTitle: String {
        return L(self.rawValue)
    }
}

// MARK: - Dynamic Island Navigation Bar
struct DynamicIslandNavigationBar: View {
    @Binding var selectedTab: NavigationTab
    var showApplyButton: Bool
    var isApplyEnabled: Bool = true
    var onApplyTapped: () -> Void

    var body: some View {
        EmptyView()
    }
}