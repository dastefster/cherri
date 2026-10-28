// ===================================
// Documentation
// v0.0.8 BUILD 2026-10-25 07:25
// In-app reference for everything Cherri Shortcuts does in beta 1: the editor, the Actions picker, Compile, Export, third-party app actions, Settings, and what stays on your device. Content lives in the docTopics array so it can be edited without touching layout code.
// dev by @dastefster 🍒🔨
// ===================================

import SwiftUI

// ===================================
// DOCUMENTATION CONTENT
// ===================================

let docTopics: [GuideSection] = [
    GuideSection(id: "overview", title: "What Cherri Shortcuts does", symbol: "sparkles", blocks: [
        .text("Cherri Shortcuts lets you build Apple Shortcuts by writing code instead of dragging blocks. You write in **Cherri**, a language made for Shortcuts, and the app turns it into a real shortcut you can add to your library and run like any other."),
        .text("Everything runs from one screen: an editor, an **Actions** button, **Compile**, **Export** and **Import**."),
        .tip("New to Cherri? The Guide has a short tour of the language. This documentation covers what the app itself can do."),
    ]),
    GuideSection(id: "editor", title: "The editor", symbol: "square.and.pencil", blocks: [
        .text("Type Cherri code directly into the editor. It saves automatically on your device, so closing or force-quitting the app never loses your work."),
        .text("**Syntax highlighting** colors your code as you type: comments, strings, numbers, keywords (shown in bold), variables, actions and type names each get their own color. It also colors names you declare, like constants and loop variables, and anything in braces inside a string."),
        .text("Actions and values you insert from the Actions picker land **at your cursor**, so tap in the editor first to choose the spot."),
        .tip("Colors and font are set in Settings, under Appearance."),
    ]),
    GuideSection(id: "picker", title: "The Actions picker", symbol: "list.bullet.rectangle", blocks: [
        .text("Tap **Actions** to open every action Cherri Shortcuts knows, grouped into categories the way Shortcuts groups them. Use the search field to find one by name or description."),
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
        .text("In the share sheet, choose the **Shortcuts** icon (swipe the row if you don't see it). Shortcuts opens with an Add Shortcut screen. Tap the blue **Add Shortcut** button at the bottom and the shortcut joins your library."),
        .text("By default Cherri Shortcuts asks before exporting, because your shortcut is sent to HubSign. You can turn that question off in Settings, under **Ask Before Exporting**. Once your shortcut is signed, a short tip reminds you to tap **Shortcuts** in the share sheet; you can turn it off under **Show Export Tip**."),
        .tip("If Export seems stuck after choosing Save to Files, force-quit Cherri Shortcuts, reopen it, and pick the Shortcuts icon instead."),
    ]),
    GuideSection(id: "import", title: "Import", symbol: "square.and.arrow.down", blocks: [
        .text("**Import** is Export in reverse. It takes a shortcut you already have in the Shortcuts app and turns it into Cherri code in the editor, so you can read it, change it, and export it again."),
        .text("**Method 1: from the app.** In the Shortcuts app, open a shortcut's share menu and tap **Copy iCloud Link**. In Cherri Shortcuts tap **Import**, tap **Paste** (Apple's Paste button, so there's no permission prompt), then tap **Import**. You can also type or paste the link into the field yourself."),
        .text("**Method 2: from the share sheet.** In the Shortcuts app, tap **Share** on a shortcut and choose **Cherri Shortcuts** in the share sheet. If you don't see it, swipe the row of apps or tap More. Cherri Shortcuts opens and imports the shortcut automatically. If the app can't open by itself, it tells you to open Cherri Shortcuts by hand, and the link is kept for 15 minutes."),
        .text("**Replacing your code.** Import puts the shortcut in the editor. If the editor already has your code, the app asks before replacing it, and there is no undo. An empty editor, or the untouched starter code, is replaced without asking."),
        .text("**Actions that aren't supported yet.** The shortcut still imports. Any action Cherri Shortcuts doesn't know is kept in your code as a `rawAction` line, and the app lists them. Those lines may lose their settings or not work once compiled. **Tell Support** opens the feedback form with the action names and your link filled in."),
        .text("**When iCloud can't find the shortcut.** The link may be old, or sharing may be off. Copy a fresh link and try again. A link from the share sheet can take a few seconds to be published, so the app waits and retries before showing an error. Tap **Copy full message** on the error to send me the details."),
        .text("After an import, tap **Compile** to check the code, then **Export** if you want it back in your library."),
        .tip("Shortcuts may ask you to Create iCloud Link before it shares. Anyone who has that link can view the shortcut, so only share links you're happy for others to see."),
    ]),
    GuideSection(id: "style", title: "Name, color and icon", symbol: "paintpalette", blocks: [
        .text("Three optional lines at the top of your code control how the exported shortcut looks:"),
        .code("#define name My Shortcut\n#define color blue\n#define glyph hammer"),
        .text("**name** sets the shortcut's name, which is also used for the exported file. Without it, the name is Shortcut."),
        .text("**color** sets the shortcut's color. Choose from `red`, `darkorange`, `orange`, `yellow`, `green`, `teal`, `lightblue`, `blue`, `darkblue`, `violet`, `purple`, `pink`, `darkgray`, `gray` or `taupe`."),
        .text("**glyph** sets the icon on the shortcut. `apple` and `hammer` are two examples."),
        .tip("Your shortcut's name is sent to HubSign along with the shortcut when you Export."),
    ]),
    GuideSection(id: "thirdparty", title: "Third-party app actions", symbol: "square.grid.2x2", blocks: [
        .text("The **Third-Party Apps** category holds actions for other apps, such as **Scriptable**, **Pythonista** and **Menu Box**. Other categories include actions for apps like Craft, Photos and Reminders."),
        .text("These shortcuts need the app installed. If you don't have it, Shortcuts shows an install prompt when you add the shortcut."),
        .text("Some actions ask you to choose something when the shortcut runs, like a script, folder, space or list. That's normal: those choices are specific to your device."),
        .text("Newer actions can need a newer version of iOS. If Shortcuts shows an Unknown Action with an Update Shortcuts button, your iOS is older than the action requires. The action's help screen lists any requirement."),
    ]),
    GuideSection(id: "settings", title: "Settings", symbol: "gearshape", blocks: [
        .text("Open Settings with the gear at the top left of the editor."),
        .text("**Appearance** controls how the editor looks. Your iPhone's light or dark appearance decides which of two themes the editor uses. Choose them under **Light Mode** and **Dark Mode**, with a live preview of each. They start as **Dracula** in light mode and **Tomorrow Night Bright** in dark mode. Pick a font with Apple's font picker, which shows monospaced fonts only. To add more, tap **Manage Fonts** in the picker and install one. Font size goes from 10 to 28. **Reset to Defaults** puts everything back."),
        .text("**Ask Before Exporting** turns the confirmation before Export on or off. **Show Export Tip** turns the reminder about the Shortcuts icon in the share sheet on or off."),
        .text("**Reset Editor to Starter Code** replaces everything in the editor with the starter code. It asks first, and it can't be undone."),
        .text("**Help** has the Guide, this documentation, and a way to see the welcome screen again."),
        .text("**About** shows the app version, the Cherri compiler version and the licenses."),
    ]),
    GuideSection(id: "privacy", title: "Your code and your privacy", symbol: "lock.shield", blocks: [
        .text("Your code is stored only on your device."),
        .text("**Compile** never leaves your device."),
        .text("**Export** sends the compiled shortcut to RoutineHub's HubSign service so it can be signed, and nothing else. Cherri Shortcuts has no accounts, no ads and no analytics."),
        .text("**Import** looks up the iCloud link you give it on Apple's iCloud servers to download that shortcut, and nothing else. The shortcut is turned into code on your device. The Share sheet option only reads the link and hands it to the app. It doesn't use the internet itself."),
        .text("If you install the app through TestFlight, Apple collects its own crash and usage data for testing."),
        .tip("The full privacy policy is in Settings, under About."),
    ]),
    GuideSection(id: "limits", title: "Beta limits", symbol: "exclamationmark.triangle", blocks: [
        .text("This is the first beta, so some things are still on the way:"),
        .text("• No autocomplete while typing yet. Use the Actions picker for now."),
        .text("• Very large scripts may feel slow, since your code is kept in the app's settings."),
        .text("• Some actions haven't been checked against every iOS version."),
        .text("• Export needs HubSign to be online. Compile always works."),
        .text("• Import can't read every action yet. Unsupported ones are kept as `rawAction` lines, and a few of those may not survive a round trip."),
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
                Text("What Cherri Shortcuts can do in beta 1. More will be added as the app grows.")
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
