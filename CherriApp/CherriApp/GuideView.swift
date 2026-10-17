// ===================================
// In-App Guide
// v0.0.8 BUILD 2026-10-16 19:52
// Basic documentation sheet: getting started, Cherri syntax basics, the Actions picker, Compile vs Export, troubleshooting, beta limitations, and credits. Content lives in the guideSections array so it can be edited without touching layout code.
// dev by @dastefster 🍒🔨
// ===================================

import SwiftUI

// ===================================
// GUIDE CONTENT MODEL
// ===================================

enum GuideBlock {
    case text(String)   // Supports **bold** and `code` markdown.
    case code(String)   // Monospaced, selectable.
    case tip(String)    // Highlighted note.
}

struct GuideSection: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let blocks: [GuideBlock]
}

// ===================================
// GUIDE CONTENT
// ===================================

let guideSections: [GuideSection] = [
    GuideSection(id: "start", title: "Getting started", symbol: "play.circle", blocks: [
        .text("CherriCuts turns code into a real Apple Shortcut. Your code is saved automatically, so closing the app never loses work."),
        .text("**1. Write.** Type Cherri code in the editor, or tap **Actions** to search the actions you know from Shortcuts. Fill in the form and the action is inserted at your cursor."),
        .text("**2. Compile.** Checks your code. Success shows the size of the shortcut. Errors appear under the editor."),
        .text("**3. Export.** Signs the shortcut and opens the share sheet. Choose the **Shortcuts** icon (swipe the row if you don't see it) to add it to your library."),
        .code("alert(\"Hello from Cherri\")"),
    ]),
    GuideSection(id: "syntax", title: "Cherri basics", symbol: "chevron.left.forwardslash.chevron.right", blocks: [
        .text("**Comments** start with `//`."),
        .code("// this line is ignored"),
        .text("**Variables** start with `@`. To use one inside text, wrap it in braces."),
        .code("@name = \"Stefan\"\nalert(\"Hello {@name}\")"),
        .text("**Math** works on variables with `+=`, `-=`, `*=` and `/=`."),
        .code("@count = 0\n@count += 1"),
        .text("**Conditions** use `if` and `else`. Put a variable on the left side of the comparison."),
        .code("if @count > 2 {\n    show(\"Big\")\n} else {\n    show(\"Small\")\n}"),
        .text("**Repeating** runs a block several times, or once per item in a list."),
        .code("repeat i for 3 {\n    @count += 1\n}\n\n@items = [\"a\", \"b\", \"c\"]\nfor item in @items {\n    show(\"{item}\")\n}"),
        .text("**Constants** keep an action's result so you can use it later. They make smaller shortcuts than variables."),
        .code("const total = add(2, 3)\nshow(\"{total}\")"),
        .text("**Functions** let you reuse code."),
        .code("function add(number a, number b): number {\n    const s = @a + @b\n    output(\"{s}\")\n}"),
        .tip("The full language reference is linked at the bottom of this guide."),
    ]),
    GuideSection(id: "picker", title: "Using the Actions picker", symbol: "list.bullet.rectangle", blocks: [
        .text("Tap **Actions** to search or browse. Choose an action to open its form. Fill in what you need and leave the rest empty, because optional parameters can be skipped."),
        .text("**Swipe left** on an action and tap **Quick Insert** to skip the form and drop the action into your code right away."),
        .text("The **i** button explains what each parameter accepts. Tapping an allowed value in the help inserts it at your cursor."),
        .text("The variable menu in a form lists the variables in your code, newest first, plus Cherri's built-ins, so you can drop one in without typing it."),
        .tip("Actions are inserted where your cursor is. Tap in the editor first to choose the spot."),
    ]),
    GuideSection(id: "export", title: "Compile vs. Export", symbol: "square.and.arrow.up", blocks: [
        .text("**Compile** runs entirely on your device and sends nothing anywhere."),
        .text("**Export** needs an internet connection. iOS only imports signed shortcuts, so your shortcut is sent to RoutineHub's HubSign service to be signed, then returned to you."),
        .text("In the share sheet, choose the **Shortcuts** icon (swipe the row if you don't see it). Shortcuts opens with an Add Shortcut screen."),
    ]),
    GuideSection(id: "style", title: "Name, color and icon", symbol: "paintpalette", blocks: [
        .text("Put these lines at the very top of your code to style the shortcut you export:"),
        .code("#define name My Shortcut\n#define color blue\n#define glyph hammer"),
        .text("**name** is what your shortcut is called when you import it. Without it, the shortcut is called Shortcut."),
        .text("**color** can be `red`, `darkorange`, `orange`, `yellow`, `green`, `teal`, `lightblue`, `blue`, `darkblue`, `violet`, `purple`, `pink`, `darkgray`, `gray` or `taupe`."),
        .text("**glyph** is the icon shown on the shortcut. `apple` and `hammer` are two examples."),
        .tip("All three lines are optional. Use only the ones you want."),
    ]),
    GuideSection(id: "trouble", title: "Troubleshooting", symbol: "wrench.and.screwdriver", blocks: [
        .text("**Export spins forever after choosing Save to Files.** Force-quit CherriCuts and reopen it, then pick the **Shortcuts** icon instead."),
        .text("**Shortcuts shows an \"Unknown action\" with an Update Shortcuts button.** The action needs a newer iOS than the one you're running. Some Photos actions need iOS 27."),
        .text("**A third-party action shows an install prompt.** Install that app from the App Store, then add the shortcut again."),
        .text("**An action asks you to choose something when it runs** (a space, folder, list or album). That's expected. These choices are specific to your device, so the shortcut asks you at run time."),
        .text("**Error messages are long.** The red line under the editor is the important one. Tap **Show details** for the rest, or **Copy full message** to send it to me."),
    ]),
    GuideSection(id: "beta", title: "Known beta limitations", symbol: "exclamationmark.triangle", blocks: [
        .text("This is an early beta. Here is what to expect:"),
        .text("• No autocomplete yet. Use the Actions picker to insert actions."),
        .text("• Very large scripts may be slow. They are stored in the app's settings for now."),
        .text("• Some actions haven't been checked against the latest iOS. If an action misbehaves, tell me which one."),
        .text("• Export always goes through HubSign. If it's down, Export won't work, but Compile will."),
    ]),
    GuideSection(id: "about", title: "About", symbol: "info.circle", blocks: [
        .text("CherriCuts is made by Stefan Hottel (@dastefster) 🍒🔨"),
        .text("It's built on **Cherri**, the open source Shortcuts language created by electrikmilk. Shortcut signing is provided by RoutineHub's HubSign."),
    ]),
]

// ===================================
// GUIDE VIEW
// ===================================

struct GuideView: View {
    let onShowWelcome: () -> Void
    // Own expand/collapse state: DisclosureGroup rows did not respond to taps inside this List.
    @State private var expanded: Set<String> = ["start"]

    var body: some View {
        Group {
            List {
                ForEach(guideSections) { section in
                    sectionRow(section)
                }

                Section {
                    Link(destination: URL(string: "https://cherrilang.org/language/")!) {
                        Label("Cherri language reference", systemImage: "book")
                    }
                    Link(destination: URL(string: "https://github.com/electrikmilk/cherri")!) {
                        Label("Cherri on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    Button(action: onShowWelcome) {
                        Label("Show welcome screen", systemImage: "hand.wave")
                    }
                }
            }
            .navigationTitle("Guide")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // ===================================
    // SECTION ROW
    // ===================================

    private func sectionRow(_ section: GuideSection) -> some View {
        let isOpen = expanded.contains(section.id)
        return VStack(alignment: .leading, spacing: 12) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isOpen { expanded.remove(section.id) } else { expanded.insert(section.id) }
                }
            }) {
                HStack {
                    Label(section.title, systemImage: section.symbol)
                        .font(.headline)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(section.blocks.enumerated()), id: \.offset) { _, block in
                        GuideBlockView(block: block)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// ===================================
// BLOCK RENDERING
// ===================================

// Shared by the Guide and the Documentation pages.
struct GuideBlockView: View {
    let block: GuideBlock

    var body: some View {
        switch block {
        case .text(let string):
            Text(LocalizedStringKey(string))
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        case .code(let string):
            Text(string)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
        case .tip(let string):
            Label(string, systemImage: "lightbulb")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
