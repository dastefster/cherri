
// ===================================
// Cherri Premium
// v0.0.2 BUILD 2026-10-21 18:30
// StoreKit 2 one-time unlock: loads the product, handles purchase and restore, watches for transactions that finish outside the app (Ask to Buy, refunds), and caches the result so the editor never waits on the network. Also defines which themes and icons are free.
// dev by @dastefster 🍒🔨
// ===================================

import SwiftUI
import Combine
import StoreKit

// ===================================
// FREE VS PREMIUM
// ===================================

// The one place that decides what costs money. Dracula and Tomorrow Night Bright stay free because they're the themes a new install opens with, and locking the look the app ships with would make the first launch feel like a trial.
enum PremiumFeatures {
    static let freeThemeIDs: Set<String> = [
        EditorSettings.defaultThemeID,
        EditorSettings.defaultLightThemeID,
        EditorSettings.defaultDarkThemeID,
        "github-light",
        "github-dark",
    ]

    static let freeIconIDs: Set<String> = ["AppIcon"]

    static func themeIsFree(_ id: String) -> Bool { freeThemeIDs.contains(id) }
    static func iconIsFree(_ id: String) -> Bool { freeIconIDs.contains(id) }

    static var premiumThemeCount: Int {
        EditorTheme.all.filter { !themeIsFree($0.id) }.count
    }

    static var premiumIconCount: Int {
        AppIconOption.all.filter { !iconIsFree($0.id) }.count
    }
}

// ===================================
// PREMIUM STORE
// ===================================

final class PremiumStore: ObservableObject {
    static let shared = PremiumStore()

    // Must match the Product ID of the non-consumable in App Store Connect and in Configuration.storekit.
    static let productID = "com.dastefster.CherriApp.premium"

    // The last verified answer. Views read it with @AppStorage so they update the moment it changes.
    static let unlockedKey = "premiumUnlocked"

    @Published private(set) var product: Product?
    @Published private(set) var isPremium = UserDefaults.standard.bool(forKey: PremiumStore.unlockedKey)
    @Published private(set) var isPurchasing = false
    @Published private(set) var isLoadingProduct = false
    @Published var message: String?

    private var updatesTask: Task<Void, Never>?

    // ===================================
    // START
    // ===================================

    // Called once at launch.
    func start() {
        guard updatesTask == nil else { return }

        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                await self?.handle(result)
            }
        }

        Task {
            await refreshEntitlements()
            await loadProduct()
        }
    }

    // ===================================
    // PRODUCT
    // ===================================

    func loadProduct() async {
        guard product == nil, !isLoadingProduct else { return }

        isLoadingProduct = true
        defer { isLoadingProduct = false }

        do {
            product = try await Product.products(for: [Self.productID]).first
            if product == nil {
                message = "Premium isn't available right now. Try again in a bit."
            }
        } catch {
            print("[Premium] Product load failed: \(error)")
            message = "Couldn't reach the App Store. Check your connection and try again."
        }
    }

    // ===================================
    // PURCHASE
    // ===================================

    func purchase() async {
        guard let product else {
            await loadProduct()
            return
        }

        isPurchasing = true
        message = nil
        defer { isPurchasing = false }

        do {
            switch try await product.purchase() {
            case .success(let verification):
                await handle(verification)
            case .pending:
                message = "Your purchase is waiting for approval. Premium unlocks as soon as it goes through."
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            print("[Premium] Purchase failed: \(error)")
            message = error.localizedDescription
        }
    }

    // ===================================
    // RESTORE
    // ===================================

    // Apple requires a visible way to do this. AppStore.sync asks for the Apple ID password, so it only runs when the person taps the button.
    func restore() async {
        message = nil

        // The local entitlement check needs no sign-in; AppStore.sync() always shows Apple's password prompt, so only fall back to it when nothing is found.
        await refreshEntitlements()
        if isPremium {
            message = "You're already unlocked."
            return
        }

        do {
            try await AppStore.sync()
            await refreshEntitlements()
            message = isPremium ? "Premium restored." : "No previous purchase found for this Apple ID."
        } catch {
            print("[Premium] Restore failed: \(error)")
            message = "Couldn't restore purchases. \(error.localizedDescription)"
        }
    }

    // ===================================
    // ENTITLEMENTS
    // ===================================

    private func handle(_ result: VerificationResult<StoreKit.Transaction>) async {
        guard case .verified(let transaction) = result else {
            message = "That purchase couldn't be verified."
            return
        }

        await transaction.finish()
        await refreshEntitlements()
    }

    // currentEntitlements already leaves out refunded and revoked purchases.
    func refreshEntitlements() async {
        var entitled = false

        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.productID,
               transaction.revocationDate == nil {
                entitled = true
            }
        }

        setPremium(entitled)
    }

    private func setPremium(_ value: Bool) {
        isPremium = value
        UserDefaults.standard.set(value, forKey: Self.unlockedKey)

        // A refund shouldn't leave a premium icon on the Home Screen.
        if !value,
           let icon = UIApplication.shared.alternateIconName,
           !PremiumFeatures.iconIsFree(icon) {
            UIApplication.shared.setAlternateIconName(nil)
        }
    }
}

// ===================================
// PREMIUM VIEW
// ===================================

// The pitch, the buy button and Restore Purchases. Pushed from Settings and wrapped in PremiumSheet when a locked item is tapped.
struct PremiumView: View {
    @EnvironmentObject private var store: PremiumStore

    private var buyTitle: String {
        if let product = store.product { return "Unlock Premium — \(product.displayPrice)" }
        return store.isLoadingProduct ? "Loading price…" : "Try Again"
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    SettingsIcon(symbol: "crown.fill", color: PremiumStore.gold)
                        .scaleEffect(2)
                        .padding(.vertical, 14)
                    Text("Cherri Premium")
                        .font(.title2.bold())
                    Text("One purchase, yours forever. No subscription.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .listRowBackground(Color.clear)
            }

            Section("What You Get") {
                Label("\(PremiumFeatures.premiumThemeCount) more editor themes", systemImage: "paintpalette.fill")
                Label("\(PremiumFeatures.premiumIconCount) alternate app icons", systemImage: "app.dashed")
                Label("Supports a one-person indie app", systemImage: "heart.fill")
            }

            Section {
                if store.isPremium {
                    Label("Premium unlocked — thank you!", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                } else {
                    Button {
                        Task {
                            if store.product == nil {
                                await store.loadProduct()
                            } else {
                                await store.purchase()
                            }
                        }
                    } label: {
                        HStack {
                            Text(buyTitle)
                                .fontWeight(.semibold)
                            Spacer()
                            if store.isPurchasing || store.isLoadingProduct { ProgressView() }
                        }
                    }
                    .disabled(store.isPurchasing || store.isLoadingProduct)
                }

                Button("Restore Purchases") {
                    Task { await store.restore() }
                }
                .disabled(store.isPurchasing)
            } footer: {
                if let message = store.message {
                    Text(message)
                }
            }
        }
        .navigationTitle("Premium")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.loadProduct() }
    }
}

// ===================================
// PREMIUM SHEET
// ===================================

struct PremiumSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: PremiumStore

    var body: some View {
        NavigationStack {
            PremiumView()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        // Close itself right after a successful purchase or restore.
        .onChange(of: store.isPremium) { _, unlocked in
            if unlocked { dismiss() }
        }
    }
}

// ===================================
// LOCK BADGE
// ===================================

// The small crown shown on locked themes and icons.
struct PremiumBadge: View {
    var body: some View {
        Image(systemName: "crown.fill")
            .font(.caption.weight(.bold))
            .foregroundStyle(PremiumStore.gold)
            .accessibilityLabel("Premium")
    }
}

extension PremiumStore {
    static let gold = Color(red: 0.95, green: 0.66, blue: 0.05)
}
