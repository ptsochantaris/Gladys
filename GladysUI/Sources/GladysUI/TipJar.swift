import Foundation
import GladysCommon
import StoreKit

@MainActor
public final class Tip {
    public enum State {
        case notPurchased, otherWasPurchased, purchased
    }

    public let image: String
    public let productId: String

    public var fetchedProduct: Product?
    public var state: State

    public init(productId: String, image: String) {
        self.productId = productId
        self.image = image
        state = .notPurchased
    }
}

public enum TipJarError: LocalizedError {
    case noFetchedProduct(String)

    public var errorDescription: String? {
        switch self {
        case let .noFetchedProduct(error):
            error
        }
    }
}

@MainActor
public final class TipJar {
    public enum State {
        case uninitialised, busy, ready, success, error(Error)

        var isBusy: Bool {
            switch self {
            case .error, .ready, .success, .uninitialised: false
            case .busy: true
            }
        }

        var needsInit: Bool {
            switch self {
            case .error, .uninitialised: true
            case .busy, .ready, .success: false
            }
        }
    }

    public static let shared = TipJar()

    #if canImport(AppKit)
        private static let identifierPrefix = "MAC_GLADYS_TIP_TIER"
    #else
        private static let identifierPrefix = "GLADYS_TIP_TIER"
    #endif

    public let tips = [
        Tip(productId: "\(identifierPrefix)_001", image: "🙂"),
        Tip(productId: "\(identifierPrefix)_002", image: "😊"),
        Tip(productId: "\(identifierPrefix)_003", image: "🤗"),
        Tip(productId: "\(identifierPrefix)_004", image: "😮"),
        Tip(productId: "\(identifierPrefix)_005", image: "😱")
    ]

    public var state = State.uninitialised

    public func waitForBusy() async {
        while state.isBusy {
            try? await Task.sleep(for: .seconds(1))
        }
    }

    public func setupIfNeeded() async {
        await waitForBusy()

        guard state.needsInit else {
            return
        }

        log("Initialising tip jar in case it's needed ;)")

        do {
            var products = try await Product.products(for: tips.map(\.productId))
            if products.count < tips.count {
                log("Error fetching tip jar: Missing products")
                state = .error(TipJarError.noFetchedProduct("Could not fetch products from App Store"))
                return
            }
            products.sort { $0.id < $1.id }
            for pair in zip(tips, products) {
                pair.0.fetchedProduct = pair.1
            }
            log("Fetched tip list")
            state = .ready
        } catch {
            log("Error fetching tip jar: \(error.localizedDescription)")
            state = .error(error)
        }
        Task {
            for await transactionResult in Transaction.updates {
                await completeTransaction(transactionResult)
            }
        }
        Task {
            for await transactionResult in Transaction.unfinished {
                await completeTransaction(transactionResult)
            }
        }
    }

    private func completeTransaction(_ transaction: VerificationResult<StoreKit.Transaction>) async {
        switch transaction {
        case let .unverified(transaction, error):
            state = .error(error)
            await transaction.finish()

        case let .verified(transaction):
            await MainActor.run {
                for tip in tips {
                    tip.state = transaction.productID == tip.productId ? .purchased : .otherWasPurchased
                }
            }
            state = .success
            await transaction.finish()
        }
    }

    public func purchase(_ tip: Tip) async {
        state = .busy
        do {
            guard let product = tip.fetchedProduct else {
                state = .error(TipJarError.noFetchedProduct("Did not find an associated App Store product for this tip"))
                return
            }

            #if os(visionOS)
            guard let currentScene = UIApplication.shared.connectedScenes.filter({ $0.activationState != .background }).compactMap({ ($0 as? UIWindowScene) }).lazy.first else {
                state = .error(TipJarError.noFetchedProduct("Did not find a window scene for presenting the purchase"))
                return
            }

            let result = try await product.purchase(confirmIn: currentScene)
            #else

            let result = try await product.purchase()
            #endif

            switch result {
            case let .success(result):
                await completeTransaction(result)

            case .userCancelled:
                state = .ready

            case .pending:
                fallthrough

            @unknown default:
                break
            }
        } catch {
            state = .error(error)
        }
    }
}
