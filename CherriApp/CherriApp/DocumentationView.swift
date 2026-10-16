// ===================================
// Documentation
// v0.0.2 BUILD 2026-10-16 04:45
// In-app reference for everything CherriCuts does in beta 1: the editor, the Actions picker, Compile, Export, third-party app actions, Settings, and what stays on your device. Content lives in the docTopics array so it can be edited without touching layout code.
// dev by @dastefster 🍒🔨
// ===================================

import SwiftUI

// ===================================
// DOCUMENTATION CONTENT
// ===================================

let docTopics: [GuideSection] = [
    GuideSection(id: "overview", title: "What CherriCuts does", symbol: "sparkles", blocks: [
        .text("CherriCuts lets you build Apple Shortcuts by writing code instead of dragging blocks. You write in **Cherri**, a language made for Shortcuts, and the app turns it into a real shortcut you can add to your library and run like any other."),
        .text("Everything runs from one screen: an editor, an **Actions** button, **Compile** and **Export**."),
        .tip("New to Cherri? The Guide has a short tour of the language. This documentation covers what the app itself can do."),
    ]),
    GuideSection(id: "editor", title: "The editor", symbol: "square.and.pencil", blocks: [
        .text("Type Cherri code directly into the editor. It saves automatically on your device, so closing or force-quitting the app never loses your work."),
        .text("**Syntax highlighting** colors your code as you type: comments, strings, numbers, keywords (shown in bold), variables, actions and type names each get their own color. It also colors names you declare, like constants and loop variables, and anything in braces inside a string."),
        .text("Actions and values you insert from the Actions picker land **at your cursor**, so tap in the editor first to choose the spot."),
        .tip("Colors and font are set in Settings, under Appearance."),
    ]),
    GuideSection(id: "picker", title: "The Actions picker", symbol: "list.bullet.rectangle", blocks: [
        .text("Tap **Actions** to open every action CherriCuts knows, grouped into categories the way Shortcuts groups them. Use the search field to find one by name or description."),
        .text("**Tap an action** to open its form. Each parameter is a field in plain words, marked **required** or **optional**. Options become menus, yes/no values become an On/Off menu, and anything that takes a variable gets a small menu button next to the field."),
        .text("**The variable menu** lists the variables and constants in your code, newest first, plus Cherri's built-ins: `ShortcutInput`, `Clipboard`, `CurrentDate` and `Device`."),
        .text("**Your code** at the bottom of the form is a live preview of what will be inserted. Leave an optional field empty and it's skipped for you. If a required field is empty, a placeholder is inserted that you can edit afterwards."),
        .text("Tap **Insert** to add it at your cursor. Actions with no parameters are inserted as soon as you tap them."),
        .text("**Quick Insert:** swipe left on an action and tap **Quick Insert** to drop in starter code without opening the form."),
        .text("**The i button** opens the action's help: its signature, what it does, any iOS or app requirements, and every parameter with its type and default. Tap an allowed value to insert it at your cursor."),
        .text("**Show cancel button:** the Alert action has a switch that adds a Cancel button. It's written as `confirm` in your code instead of `alert`."),
    ]),
    GuideSection(id: "compile", title: "Compile", symbol: "hammer", blocks: [
        .text("**Compile** checks your code and builds the shortcut. It runs entirely on your device and sends nothing anywhere, so it works offline."),
        .text("If it works, you'll see how big the finished shortcut is. If not, the important error appears in red under the editor."),
        .text("Tap **Show details** for the full compiler output, or **Copy full message** to copy everything, which is handy for asking for help."),
        .tip("Compile as you go. Small steps make errors easy to spot."),
    ]),
    GuideSection(id: "export", title: "Export", symbol: "square.and.arrow.up", blocks: [
        .text("**Export** compiles your code, gets the shortcut signed, and opens the share sheet. iOS only accepts signed shortcuts, and signing is done by RoutineHub's **HubSign** service, so Export needs an internet connection."),
        .text("In the share sheet, choose the **Shortcuts** icon. Shortcuts opens with an Add Shortcut screen, and the shortcut joins your library."),
        .text("By default CherriCuts asks before exporting, because your shortcut is sent to HubSign. You can turn that question off in Settings, under **Ask Before Exporting**."),
        .tip("If Export seems stuck after choosing Save to Files, force-quit CherriCuts, reopen it, and pick the Shortcuts icon instead."),
    ]),
    GuideSection(id: "thirdparty", title: "Third-party app actions", symbol: "square.grid.2x2", blocks: [
        .text("The **Third-Party Apps** category holds actions for other apps, such as **Scriptable**, **Pythonista** and **Menu Box**. Other categories include actions for apps like Craft, Photos and Reminders."),
        .text("These shortcuts need the app installed. If you don't have it, Shortcuts shows an install prompt when you add the shortcut."),
        .text("Some actions ask you to choose something when the shortcut runs, like a script, folder, space or list. That's normal: those choices are specific to your device."),
        .text("Newer actions can need a newer version of iOS. If Shortcuts shows an Unknown Action with an Update Shortcuts button, your iOS is older than the action requires. The action's help screen lists any requirement."),
    ]),
    GuideSection(id: "settings", title: "Settings", symbol: "gearshape", blocks: [
        .text("Open Settings with the gear at the top left of the editor."),
        .text("**Appearance** controls how the editor looks. Colors follow your device: **Dracula** in light mode and **Tomorrow Night Bright** in dark mode. Pick a font with Apple's font picker, which shows monospaced fonts only. To add more, tap **Manage Fonts** in the picker and install one. Font size goes from 10 to 28. **Reset to Defaults** puts everything back."),
        .text("**Ask Before Exporting** turns the confirmation before Export on or off."),
        .text("**Reset Editor to Starter Code** replaces everything in the editor with the starter code. It asks first, and it can't be undone."),
        .text("**Help** has the Guide, this documentation, and a way to see the welcome screen again."),
        .text("**About** shows the app version, the Cherri compiler version and the licenses."),
    ]),
    GuideSection(id: "privacy", title: "Your code and your privacy", symbol: "lock.shield", blocks: [
        .text("Your code is stored only on your device."),
        .text("**Compile** never leaves your device."),
        .text("**Export** sends the compiled shortcut to RoutineHub's HubSign service so it can be signed, and nothing else. CherriCuts has no accounts, no ads and no analytics."),
        .text("If you install the app through TestFlight, Apple collects its own crash and usage data for testing."),
        .tip("The full privacy policy is in Settings, under About."),
    ]),
    GuideSection(id: "limits", title: "Beta limits", symbol: "exclamationmark.triangle", blocks: [
        .text("This is the first beta, so some things are still on the way:"),
        .text("• No autocomplete while typing yet. Use the Actions picker for now."),
        .text("• Very large scripts may feel slow, since your code is kept in the app's settings."),
        .text("• Some actions haven't been checked against every iOS version."),
        .text("• Export needs HubSign to be online. Compile always works."),
        .tip("If something misbehaves, tell me which action and what happened, and copy the full error message if there is one."),
    ]),
]

// ===================================
// DOCUMENTATION VIEW
// ===================================

struct DocumentationView: View {
    private let palette: [Color] = [.gray]

    var body: some View {
        List {
            Section {
                ForEach(Array(docTopics.enumerated()), id: \.element.id) { index, topic in
                    NavigationLink {
                        DocPageView(topic: topic)
                    } label: {
                        SettingsLabel(title: topic.title, symbol: topic.symbol, color: palette[index % palette.count])
                    }
                }
            } footer: {
                Text("What CherriCuts can do in beta 1. More will be added as the app grows.")
            }

            Section("Cherri language") {
                Link(destination: URL(string: "https://cherrilang.org/language/")!) {
                    Label("Language reference", systemImage: "book")
                }
            }
        }
        .navigationTitle("Documentation")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// ===================================
// DOCUMENTATION PAGE
// ===================================

struct DocPageView: View {
    let topic: GuideSection

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(topic.blocks.enumerated()), id: \.offset) { _, block in
                    GuideBlockView(block: block)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(topic.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
