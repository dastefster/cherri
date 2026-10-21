// ===================================
// Appearance Settings
// v0.0.5 BUILD 2026-10-21 16:10
// Live code preview, light and dark theme pickers (they follow the system appearance), font picker, font size stepper, and App Icon picker.
// dev by @dastefster 🍒🔨
// ===================================

import SwiftUI
import UIKit

// ===================================
// APPEARANCE VIEW
// ===================================

struct AppearanceView: View {
    @AppStorage(EditorSettings.fontKey) private var fontID = EditorSettings.systemFontID
    @AppStorage(EditorSettings.sizeKey) private var fontSize = EditorSettings.defaultSize
    @AppStorage(EditorSettings.lightKey) private var lightID = EditorSettings.defaultLightThemeID
    @AppStorage(EditorSettings.darkKey) private var darkID = EditorSettings.defaultDarkThemeID
    @AppStorage(PremiumStore.unlockedKey) private var isPremium = false
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingFontPicker = false

    private var style: EditorStyle {
        EditorSettings.style(fontID: fontID, size: fontSize, lightID: lightID, darkID: darkID, dark: colorScheme == .dark, premium: isPremium)
    }

    var body: some View {
        List {
            Section {
                CodePreview(style: style)
                    .frame(height: 210)
                    .listRowInsets(EdgeInsets())
            }

            // Light and dark each get their own theme because the editor follows the phone's appearance. Any theme can go in either slot (Dracula is a dark theme that ships as the light-mode default).
            Section {
                NavigationLink {
                    ThemeListView(title: "Light Mode Theme", selection: $lightID, fontID: fontID, fontSize: fontSize)
                } label: {
                    LabeledContent("Light Mode", value: EditorTheme.theme(id: lightID).name)
                }

                NavigationLink {
                    ThemeListView(title: "Dark Mode Theme", selection: $darkID, fontID: fontID, fontSize: fontSize)
                } label: {
                    LabeledContent("Dark Mode", value: EditorTheme.theme(id: darkID).name)
                }
            } header: {
                Text("Editor Theme")
            } footer: {
                Text("Your iPhone's light or dark appearance decides which theme the editor uses.")
            }

            Section {
                Button {
                    showingFontPicker = true
                } label: {
                    HStack {
                        Text("Font")
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(EditorSettings.fontDisplayName(id: fontID))
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }

                if fontID != EditorSettings.systemFontID {
                    Button("Use Default Font (SF Mono)") {
                        fontID = EditorSettings.systemFontID
                    }
                }

                HStack {
                    Text("Font Size")
                    Spacer()
                    Text("\(Int(fontSize))")
                        .foregroundStyle(.secondary)
                    Stepper("", value: $fontSize, in: EditorSettings.sizeRange, step: 1)
                        .labelsHidden()
                }
            }
            
            Section {
                Button("Reset to Defaults", role: .destructive) {
                    fontID = EditorSettings.systemFontID
                    fontSize = EditorSettings.defaultSize
                    lightID = EditorSettings.defaultLightThemeID
                    darkID = EditorSettings.defaultDarkThemeID
                }
            }
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingFontPicker) {
            FontPicker(
                onPick: { name in
                    fontID = name
                    showingFontPicker = false
                },
                onCancel: { showingFontPicker = false }
            )
            .ignoresSafeArea()
        }
    }
}

// ===================================
// CODE PREVIEW
// ===================================

// A read-only copy of the editor that shows a sample script in the chosen theme and font.
struct CodePreview: UIViewRepresentable {
    let style: EditorStyle

    private static let sample = """
    // Greet the user
    @name = "Stefan"
    const total = add(2, 3)

    if @name == "Stefan" {
        alert("Hello {@name}", "Total: {total}")
    }

    repeat i for 3 {
        show("Number {i}")
    }
    """

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = false
        textView.isScrollEnabled = false
        textView.textContainerInset = UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        textView.text = Self.sample

        CherriHighlighter.style(textView, with: style)
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        CherriHighlighter.style(uiView, with: style)
    }
}

// ===================================
// THEME PICKER
// ===================================

struct ThemeListView: View {
    let title: String
    @Binding var selection: String
    let fontID: String
    let fontSize: Double

    @AppStorage(PremiumStore.unlockedKey) private var isPremium = false
    @State private var showingPremium = false
    // A locked theme can be previewed without being selected, so the paywall isn't the first look at it.
    @State private var previewID: String?

    private func isLocked(_ id: String) -> Bool {
        !isPremium && !PremiumFeatures.themeIsFree(id)
    }

    // Shows the highlighted theme whatever appearance the phone is in, so the other mode's theme can be judged without flipping the system setting.
    private var previewStyle: EditorStyle {
        EditorStyle(
            font: EditorSettings.uiFont(id: fontID, size: CGFloat(fontSize)),
            theme: EditorTheme.theme(id: previewID ?? selection)
        )
    }

    var body: some View {
        List {
            Section {
                CodePreview(style: previewStyle)
                    .frame(height: 210)
                    .listRowInsets(EdgeInsets())
            }

            if let id = previewID, isLocked(id) {
                Section {
                    Button {
                        showingPremium = true
                    } label: {
                        Label("Unlock Premium to use \(EditorTheme.theme(id: id).name)", systemImage: "crown.fill")
                            .foregroundStyle(PremiumStore.gold)
                    }
                }
            }

            Section {
                ForEach(EditorTheme.all) { theme in
                    Button {
                        if isLocked(theme.id) {
                            previewID = theme.id
                        } else {
                            selection = theme.id
                            previewID = nil
                        }
                    } label: {
                        HStack(spacing: 14) {
                            swatch(theme)
                            Text(theme.name)
                                .foregroundStyle(.primary)
                            if isLocked(theme.id) {
                                PremiumBadge()
                            }
                            Spacer()
                            if theme.id == selection {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            } else if theme.id == previewID {
                                Image(systemName: "eye")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingPremium) {
            PremiumSheet()
        }
    }

    // A tiny sample of the theme: its background with a few of its colors on top.
    private func swatch(_ theme: EditorTheme) -> some View {
        HStack(spacing: 3) {
            Circle().fill(Color(uiColor: theme.keyword)).frame(width: 7, height: 7)
            Circle().fill(Color(uiColor: theme.string)).frame(width: 7, height: 7)
            Circle().fill(Color(uiColor: theme.action)).frame(width: 7, height: 7)
        }
        .frame(width: 48, height: 30)
        .background(Color(uiColor: theme.background), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(Color.secondary.opacity(0.35), lineWidth: 0.5))
    }
}

// ===================================
// FONT PICKER
// ===================================

// Apple's own font picker, limited to monospaced fonts. It has search, Recents, and a My Fonts tab for fonts installed on the phone.
struct FontPicker: UIViewControllerRepresentable {
    let onPick: (String) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIFontPickerViewController {
        let configuration = UIFontPickerViewController.Configuration()
        configuration.filteredTraits = [.traitMonoSpace]
        configuration.includeFaces = false

        let picker = UIFontPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIFontPickerViewController, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, UIFontPickerViewControllerDelegate {
        let onPick: (String) -> Void
        let onCancel: () -> Void

        init(onPick: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func fontPickerViewControllerDidPickFont(_ viewController: UIFontPickerViewController) {
            if let name = viewController.selectedFontDescriptor?.postscriptName {
                onPick(name)
            } else {
                onCancel()
            }
        }

        func fontPickerViewControllerDidCancel(_ viewController: UIFontPickerViewController) {
            onCancel()
        }
    }
}

