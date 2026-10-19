// ===================================
// App Icon Picker
// v0.0.3 BUILD 2026-10-19 19:40
// Grid of the available app icons with a preview of each; tapping one switches the Home Screen icon.
// dev by @dastefster 🍒🔨
// ===================================

import SwiftUI

// ===================================
// ICON OPTIONS
// ===================================

// One selectable icon. To add an icon: add its appiconset and a small preview imageset, list the set name in
// ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES, then add a row to `all`.
struct AppIconOption: Identifiable {
    let id: String       // asset catalog set name; "AppIcon" is the primary set
    let title: String
    let preview: String  // name of the small preview image set shown in the grid

    // iOS wants nil to go back to the primary icon.
    var alternateName: String? { id == "AppIcon" ? nil : id }

    static let all: [AppIconOption] = [
        AppIconOption(id: "AppIcon", title: "Default", preview: "IconPreviewDefault"),
        AppIconOption(id: "AppIcon-Purple", title: "Purple", preview: "IconPreviewPurple"),
        AppIconOption(id: "AppIcon-Glass", title: "Glass", preview: "IconPreviewGlass"),
    ]

    static func title(for iconID: String) -> String {
        all.first { $0.id == iconID }?.title ?? "Default"
    }
}

// ===================================
// APP ICON VIEW
// ===================================

struct AppIconView: View {
    @State private var activeIcon: String = UIApplication.shared.alternateIconName ?? "AppIcon"
    // Blocks stacked requests: a second call while iOS is still showing its change alert can fail.
    @State private var changing = false

    private let columns = [GridItem(.adaptive(minimum: 100, maximum: 130), spacing: 20)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 24) {
                ForEach(AppIconOption.all) { option in
                    iconCell(option)
                }
            }
            .padding()

            Text("Default and Glass follow your iPhone's light and dark appearance. If they don't switch, check your Home Screen icon style under Edit → Customize. Purple stays as chosen.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.bottom)
        }
        .navigationTitle("App Icon")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { activeIcon = UIApplication.shared.alternateIconName ?? "AppIcon" }
    }

    // ===================================
    // ICON CELL
    // ===================================

    private func iconCell(_ option: AppIconOption) -> some View {
        let selected = activeIcon == option.id
        return Button {
            select(option)
        } label: {
            VStack(spacing: 8) {
                Image(option.preview)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: selected ? 3 : 1)
                    )
                Text(option.title)
                    .font(.footnote)
                    .foregroundStyle(selected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // ===================================
    // APP ICON SWITCH
    // ===================================

    @MainActor
    private func select(_ option: AppIconOption) {
        let app = UIApplication.shared
        let nameToSet = option.alternateName

        guard !changing, app.alternateIconName != nameToSet else {
            activeIcon = app.alternateIconName ?? "AppIcon"
            return
        }

        changing = true
        activeIcon = option.id
        app.setAlternateIconName(nameToSet) { error in
            DispatchQueue.main.async {
                // iOS sometimes reports a bogus invalidation error (POSIX 54) even though the swap worked, so the icon name iOS actually holds decides the result.
                let current = app.alternateIconName
                if let error = error, current != nameToSet {
                    print("[AppIcon] Switch to \(nameToSet ?? "primary") failed: \(error as NSError)")
                }
                activeIcon = current ?? "AppIcon"
                changing = false
            }
        }
    }
}
