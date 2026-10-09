import StoreKit

@MainActor
class StoreService: ObservableObject {
    static let shared = StoreService()

    static let proProductId = "com.subcam.app.pro"

    @Published var proProduct: Product?
    @Published var isPurchasing = false
    @Published var errorMessage: String?

    private var transactionListener: Task<Void, Never>?

    private init() {
        transactionListener = listenForTransactions()
        Task {
            await loadProducts()
            await refreshEntitlements()
        }
    }

    /// Verified current entitlements are the only source of truth for Pro. Runs at
    /// launch, after purchases/restores, and whenever StoreKit reports a change, so
    /// refunds and revocations turn Pro off and reinstalls turn it back on.
    func refreshEntitlements() async {
        var isPro = false
        for await result in Transaction.currentEntitlements {
            if let transaction = try? checkVerified(result),
               transaction.productID == StoreService.proProductId,
               transaction.revocationDate == nil {
                isPro = true
            }
        }
        SettingsService.shared.isProUnlocked = isPro
    }

    deinit {
        transactionListener?.cancel()
    }

    func loadProducts() async {
        do {
            let products = try await Product.products(for: [StoreService.proProductId])
            proProduct = products.first
        } catch {
            print("Failed to load products: \(error)")
        }
    }

    func purchasePro() async {
        guard let product = proProduct else {
            errorMessage = "商品が見つかりません"
            return
        }

        isPurchasing = true
        errorMessage = nil

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                SettingsService.shared.isProUnlocked = true
                await refreshEntitlements()

            case .userCancelled:
                break

            case .pending:
                errorMessage = "購入が保留中です"

            @unknown default:
                break
            }
        } catch {
            errorMessage = "購入に失敗しました: \(error.localizedDescription)"
        }

        isPurchasing = false
    }

    func restorePurchases() async {
        isPurchasing = true
        errorMessage = nil

        // Ask the App Store for the account's transactions first; currentEntitlements
        // alone only reflects what this device already knows about
        try? await AppStore.sync()
        await refreshEntitlements()

        if !SettingsService.shared.isProUnlocked {
            errorMessage = "復元できる購入がありません"
        }

        isPurchasing = false
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached {
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    if transaction.productID == StoreService.proProductId {
                        await StoreService.shared.refreshEntitlements()
                    }
                }
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let value):
            return value
        }
    }
}
