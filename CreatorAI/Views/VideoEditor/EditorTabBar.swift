import SwiftUI

struct EditorTab: Identifiable {
    let id: String
    let label: String
    let icon: String
}

private let tabs: [EditorTab] = [
    EditorTab(id: "edit", label: "Edit", icon: "scissors"),
    EditorTab(id: "compress", label: "Quality", icon: "arrow.down.right.and.arrow.up.left"),
    EditorTab(id: "music", label: "Music", icon: "music.note"),
]

struct EditorTabBar: View {
    @Binding var activeTab: String
    @Environment(\.theme) var theme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tabs) { tab in
                    Button {
                        activeTab = tab.id
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 14))
                            Text(tab.label)
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(activeTab == tab.id ? theme.primary : theme.surfaceElevated)
                        )
                        .foregroundColor(activeTab == tab.id ? .white : theme.textSecondary)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 12)
    }
}
