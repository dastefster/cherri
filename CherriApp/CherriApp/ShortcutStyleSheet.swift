// ===================================
// Shortcut Style Sheet
// v0.0.2 BUILD 2026-11-07 14:30
// The name, color and icon editor, plus the small icon tile and header label that show the current style. The editor header and the action picker both open this sheet; changes are written back to the code's '#define' lines by ShortcutStyleEditor.
// dev by @dastefster 🍒🔨
// ===================================

import SwiftUI

// ===================================
// ICON TILE
// ===================================

// Drawn the way Shortcuts draws its own: a rounded square in the shortcut's color with a white glyph.
struct ShortcutIconTile: View {
    let colorName: String?
    let glyphName: String?
    var size: CGFloat = 28

    var body: some View {
        let glyph = ShortcutGlyphs.named(glyphName ?? ShortcutGlyphs.defaultName)

        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(ShortcutColors.named(colorName).gradient)
            .frame(width: size, height: size)
            .overlay {
                // Glyphs without a confident SF Symbol match still compile; they just get a stand-in here.
                Image(systemName: glyph?.symbol ?? "app.dashed")
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}

// ===================================
// HEADER LABEL
// ===================================

// The editor's title: icon, name and a drop-down arrow, like the Shortcuts editor.
struct ShortcutHeaderLabel: View {
    let style: ShortcutStyle

    var body: some View {
        HStack(spacing: 8) {
            ShortcutIconTile(colorName: style.color, glyphName: style.glyph, size: 26)

            Text(style.displayName)
                .font(.headline)
                .lineLimit(1)

            Image(systemName: "chevron.down.circle.fill")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 220)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Shortcut name, color and icon: \(style.displayName)")
        .accessibilityHint("Opens the editor for the name, color and icon")
    }
}

// ===================================
// STYLE SHEET
// ===================================

struct ShortcutStyleSheet: View {
    let original: ShortcutStyle
    let onApply: (ShortcutStyle) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var colorName: String
    @State private var glyphName: String
    @State private var query = ""

    init(style: ShortcutStyle, onApply: @escaping (ShortcutStyle) -> Void) {
        original = style
        self.onApply = onApply
        _name = State(initialValue: style.name ?? "")
        _colorName = State(initialValue: style.color ?? ShortcutColors.defaultName)
        _glyphName = State(initialValue: style.glyph ?? ShortcutGlyphs.defaultName)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    preview
                    nameField
                    colorSection
                    iconSection
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Name, color and icon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: apply)
                        .fontWeight(.semibold)
                }
            }
            .searchable(text: $query, prompt: "Search icons")
        }
        .presentationDetents([.large])
    }

    // ===================================
    // PREVIEW AND NAME
    // ===================================

    private var preview: some View {
        HStack {
            Spacer()
            ShortcutIconTile(colorName: colorName, glyphName: glyphName, size: 96)
                .shadow(color: ShortcutColors.named(colorName).color.opacity(0.45), radius: 30)
            Spacer()
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Name")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            TextField("Shortcut", text: $name)
                .submitLabel(.done)
                .padding(12)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text("This becomes the name of your shortcut when you export it.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // ===================================
    // COLOR
    // ===================================

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Color")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
                ForEach(ShortcutColors.all) { option in
                    let selected = option.name == colorName

                    Button {
                        colorName = option.name
                    } label: {
                        Circle()
                            .fill(option.gradient)
                            .aspectRatio(1, contentMode: .fit)
                            .overlay {
                                // A ring with a gap, drawn just outside the swatch, the way the Shortcuts picker marks the choice.
                                Circle()
                                    .strokeBorder(Color.accentColor, lineWidth: 3)
                                    .padding(-7)
                                    .opacity(selected ? 1 : 0)
                            }
                            .padding(7)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.name)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(10)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
    }

    // ===================================
    // ICON
    // ===================================

    private var matches: [ShortcutGlyph] {
        let search = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !search.isEmpty else { return ShortcutGlyphs.all }
        return ShortcutGlyphs.all.filter { $0.name.lowercased().contains(search) || ($0.symbol?.contains(search) ?? false) }
    }

    private var iconSection: some View {
        let previewable = matches.filter { $0.symbol != nil }
        let nameOnly = matches.filter { $0.symbol == nil }

        return VStack(alignment: .leading, spacing: 12) {
            Text("Icon")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            if previewable.isEmpty && nameOnly.isEmpty {
                Text("No icons match \"\(query)\".")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 54), spacing: 10)], spacing: 10) {
                ForEach(previewable) { glyph in
                    let selected = glyph.name == glyphName

                    Button {
                        glyphName = glyph.name
                    } label: {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(selected ? Color.accentColor.opacity(0.2) : Color(.secondarySystemBackground))
                            .frame(height: 54)
                            .overlay {
                                Image(systemName: glyph.symbol ?? "app.dashed")
                                    .font(.title3)
                                    .foregroundStyle(.primary)
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Color.accentColor, lineWidth: selected ? 2 : 0)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(glyph.name)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }

            if !nameOnly.isEmpty {
                Text("More icons")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)

                Text("These all work in your shortcut. We just don't have a picture for them here yet, so pick by name.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LazyVStack(spacing: 0) {
                    ForEach(nameOnly) { glyph in
                        let selected = glyph.name == glyphName

                        Button {
                            glyphName = glyph.name
                        } label: {
                            HStack {
                                Text(glyph.name)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selected {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? .isSelected : [])

                        Divider()
                    }
                }
            }
        }
    }

    // ===================================
    // APPLY
    // ===================================

    private func apply() {
        var style = original
        style.name = ShortcutStyleEditor.cleanName(name)
        // A pick that matches the compiler's own default stays out of the code unless the code already had that line.
        style.color = (colorName == ShortcutColors.defaultName && original.color == nil) ? nil : colorName
        style.glyph = (glyphName == ShortcutGlyphs.defaultName && original.glyph == nil) ? nil : glyphName

        if style != original { onApply(style) }
        dismiss()
    }
}
