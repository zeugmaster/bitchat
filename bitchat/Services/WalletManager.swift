//
// WalletManager.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import Foundation
import CryptoKit
import CashuSwift

// MARK: - Data Models

struct StoredMint: Codable, Identifiable {
    let id = UUID()
    let url: String
    let name: String?
    let addedDate: Date
    var isActive: Bool
    
    init(url: String, name: String? = nil, isActive: Bool = true) {
        self.url = url
        self.name = name ?? url
        self.addedDate = Date()
        self.isActive = isActive
    }
}

struct StoredProof: Codable, Identifiable {
    let id = UUID()
    let keysetID: String
    let amount: Int
    let secret: String
    let c: String
    let mintURL: String
    let addedDate: Date
    var isSpent: Bool
    
    init(keysetID: String, amount: Int, secret: String, c: String, mintURL: String) {
        self.keysetID = keysetID
        self.amount = amount
        self.secret = secret
        self.c = c
        self.mintURL = mintURL
        self.addedDate = Date()
        self.isSpent = false
    }
    
    init(from proof: CashuSwift.Proof, mintURL: String) {
        self.keysetID = proof.keysetID
        self.amount = proof.amount
        self.secret = proof.secret
        self.c = proof.C
        self.mintURL = mintURL
        self.addedDate = Date()
        self.isSpent = false
    }
}

struct WalletBalance {
    let totalAmount: Int
    let proofsCount: Int
    let mintsCount: Int
    
    var formattedAmount: String {
        return "\(totalAmount) sats"
    }
}

// MARK: - Wallet Manager

class WalletManager: ObservableObject {
    static let shared = WalletManager()
    
    @Published var mints: [StoredMint] = []
    @Published var proofs: [StoredProof] = []
    @Published var balance: WalletBalance = WalletBalance(totalAmount: 0, proofsCount: 0, mintsCount: 0)
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    private let userDefaults = UserDefaults.standard
    private let mintsKey = "cashu_mints"
    private let proofsKey = "cashu_proofs"
    
    private init() {
        loadData()
        updateBalance()
        cleanupOldSeedData()
    }
    
    // Clean up old seed data from UserDefaults
    private func cleanupOldSeedData() {
        userDefaults.removeObject(forKey: "cashu_seed")
    }
    
    // MARK: - Data Persistence
    
    private func loadData() {
        // Load mints
        if let mintsData = userDefaults.data(forKey: mintsKey),
           let decodedMints = try? JSONDecoder().decode([StoredMint].self, from: mintsData) {
            self.mints = decodedMints
        }
        
        // Load proofs
        if let proofsData = userDefaults.data(forKey: proofsKey),
           let decodedProofs = try? JSONDecoder().decode([StoredProof].self, from: proofsData) {
            self.proofs = decodedProofs
        }
    }
    
    private func saveData() {
        // Save mints
        if let encodedMints = try? JSONEncoder().encode(mints) {
            userDefaults.set(encodedMints, forKey: mintsKey)
        }
        
        // Save proofs
        if let encodedProofs = try? JSONEncoder().encode(proofs) {
            userDefaults.set(encodedProofs, forKey: proofsKey)
        }
    }
    
    private func updateBalance() {
        let totalAmount = proofs.filter { !$0.isSpent }.reduce(0) { $0 + $1.amount }
        let proofsCount = proofs.filter { !$0.isSpent }.count
        let mintsCount = mints.filter { $0.isActive }.count
        
        DispatchQueue.main.async {
            self.balance = WalletBalance(
                totalAmount: totalAmount,
                proofsCount: proofsCount,
                mintsCount: mintsCount
            )
        }
    }
    
    // MARK: - Mint Management
    
    func addMint(url: String, name: String? = nil) async throws {
        print("[WALLET DEBUG] Adding mint: \(url)")
        
        await MainActor.run {
            self.isLoading = true
            self.errorMessage = nil
        }
        
        do {
            // Validate mint URL
            guard let mintURL = URL(string: url) else {
                throw WalletError.invalidMintURL
            }
            
            // Basic URL validation
            guard mintURL.scheme == "http" || mintURL.scheme == "https" else {
                throw WalletError.invalidMintURL
            }
            
            print("[WALLET DEBUG] Mint URL validation passed")
            
            // TODO: Once CashuSwift API is stable, add proper mint validation
            // For now, we'll just add the mint to our list
            
            await MainActor.run {
                let storedMint = StoredMint(url: url, name: name)
                self.mints.append(storedMint)
                self.saveData()
                self.updateBalance()
                self.isLoading = false
            }
            
            print("[WALLET DEBUG] Mint added successfully")
            
        } catch {
            print("[WALLET ERROR] Failed to add mint: \(error)")
            await MainActor.run {
                self.errorMessage = "Failed to add mint: \(error.localizedDescription)"
                self.isLoading = false
            }
            throw error
        }
    }
    
    func removeMint(_ mint: StoredMint) {
        // Remove all proofs from this mint
        proofs.removeAll { $0.mintURL == mint.url }
        
        // Remove mint
        mints.removeAll { $0.id == mint.id }
        
        saveData()
        updateBalance()
    }
    
    // MARK: - Token Operations
    
    func receiveToken(_ tokenString: String) async throws -> Int {
        print("[WALLET DEBUG] Starting receiveToken with string: \(tokenString)")
        
        await MainActor.run {
            self.isLoading = true
            self.errorMessage = nil
        }
        
        do {
            // Clean the token string
            let cleanedToken = tokenString.trimmingCharacters(in: .whitespacesAndNewlines)
            print("[WALLET DEBUG] Cleaned token: \(cleanedToken)")
            
            // Deserialize the token using CashuSwift
            let token = try cleanedToken.deserializeToken()
            print("[WALLET DEBUG] Token deserialized successfully")
            print("[WALLET DEBUG] Token unit: \(token.unit)")
            print("[WALLET DEBUG] Token memo: \(token.memo ?? "none")")
            
            // Calculate total amount
            let totalAmount = token.proofsByMint.values.flatMap { $0 }.reduce(0) { $0 + $1.amount }
            print("[WALLET DEBUG] Token total amount: \(totalAmount) \(token.unit)")
            
            // Get the mint URLs from the token
            guard let mintURLString = token.proofsByMint.keys.first else {
                throw WalletError.invalidToken
            }
            
            print("[WALLET DEBUG] Token mint URL: \(mintURLString)")
            
            // Load the mint using CashuSwift
            guard let mintURL = URL(string: mintURLString) else {
                throw WalletError.invalidMintURL
            }
            
            let mint = try await CashuSwift.loadMint(url: mintURL)
            print("[WALLET DEBUG] Mint loaded successfully")
            
            // Check if we already have this mint, if not add it
            if !self.mints.contains(where: { $0.url == mintURLString }) {
                print("[WALLET DEBUG] Adding new mint from token: \(mintURLString)")
                await MainActor.run {
                    let storedMint = StoredMint(url: mintURLString, name: "Auto-added from token")
                    self.mints.append(storedMint)
                }
            }
            
            // Receive the token using CashuSwift (without seed)
            let (receivedProofs, inputDLEQ, outputDLEQ) = try await CashuSwift.receive(
                token: token,
                of: mint,
                seed: nil,
                privateKey: nil // No P2PK support for now
            )
            
            print("[WALLET DEBUG] Token received successfully")
            print("[WALLET DEBUG] Received \(receivedProofs.count) proofs")
            print("[WALLET DEBUG] Input DLEQ: \(inputDLEQ)")
            print("[WALLET DEBUG] Output DLEQ: \(outputDLEQ)")
            
            // Convert CashuSwift.Proof to StoredProof and add to wallet
            let storedProofs = receivedProofs.map { proof in
                StoredProof(from: proof, mintURL: mintURLString)
            }
            
            await MainActor.run {
                self.proofs.append(contentsOf: storedProofs)
                self.saveData()
                self.updateBalance()
                self.isLoading = false
            }
            
            print("[WALLET DEBUG] Token processing completed: \(totalAmount) sats")
            return totalAmount
            
        } catch let error as CashuError {
            print("[WALLET ERROR] CashuSwift error: \(error)")
            await MainActor.run {
                self.errorMessage = "Failed to receive token: \(error.localizedDescription)"
                self.isLoading = false
            }
            throw WalletError.cashuError(error)
        } catch {
            print("[WALLET ERROR] General error in receiveToken: \(error)")
            await MainActor.run {
                self.errorMessage = "Failed to receive token: \(error.localizedDescription)"
                self.isLoading = false
            }
            throw error
        }
    }
    
    // MARK: - Utility Functions
    
    func getProofsForMint(_ mintURL: String) -> [StoredProof] {
        return proofs.filter { $0.mintURL == mintURL && !$0.isSpent }
    }
    
    func getBalanceForMint(_ mintURL: String) -> Int {
        return getProofsForMint(mintURL).reduce(0) { $0 + $1.amount }
    }
    
    // MARK: - Token Detection
    
    static func detectCashuToken(in text: String) -> String? {
        // Cashu tokens typically start with "cashuA" for V3 or "cashuB" for V4
        // Base64URL encoding uses A-Z, a-z, 0-9, plus (+), slash (/), underscore (_), and hyphen (-)
        // The = is used for padding
        let patterns = [
            "cashuA[A-Za-z0-9+/=_-]+",  // V3 tokens (Base64URL)
            "cashuB[A-Za-z0-9+/=_-]+"   // V4 tokens (Base64URL)
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
                return String(text[Range(match.range, in: text)!])
            }
        }
        
        return nil
    }
    
    func clearAllData() {
        mints.removeAll()
        proofs.removeAll()
        saveData()
        updateBalance()
    }
    
    // MARK: - Debug Functions
    
    func debugToken(_ tokenString: String) {
        print("\n[WALLET DEBUG] ===== TOKEN DEBUG INFO =====")
        
        do {
            let token = try tokenString.deserializeToken()
            print("[WALLET DEBUG] ✅ Token deserialized successfully")
            print("[WALLET DEBUG] Token unit: \(token.unit)")
            print("[WALLET DEBUG] Token memo: \(token.memo ?? "none")")
            print("[WALLET DEBUG] Mints in token: \(token.proofsByMint.keys.count)")
            
            for (mintURL, proofs) in token.proofsByMint {
                print("[WALLET DEBUG] Mint: \(mintURL)")
                print("[WALLET DEBUG] Proofs: \(proofs.count)")
                let totalAmount = proofs.reduce(0) { $0 + $1.amount }
                print("[WALLET DEBUG] Total amount: \(totalAmount) \(token.unit)")
            }
            
        } catch {
            print("[WALLET DEBUG] ❌ Token deserialization failed: \(error)")
        }
        
        print("[WALLET DEBUG] ===========================\n")
    }
}

// MARK: - Errors

enum WalletError: LocalizedError {
    case invalidMintURL
    case insufficientFunds
    case mintNotFound
    case invalidToken
    case notImplemented
    case cashuError(CashuError)
    
    var errorDescription: String? {
        switch self {
        case .invalidMintURL:
            return "Invalid mint URL"
        case .insufficientFunds:
            return "Insufficient funds"
        case .mintNotFound:
            return "Mint not found"
        case .invalidToken:
            return "Received token is invalid or contains no proofs"
        case .notImplemented:
            return "Feature not implemented"
        case .cashuError(let error):
            return "CashuSwift error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Extensions

extension Data {
    var hexString: String {
        return map { String(format: "%02x", $0) }.joined()
    }
    
    init?(hex: String) {
        let cleanHex = hex.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "0x", with: "")
            .lowercased()
        
        guard cleanHex.count % 2 == 0 else { return nil }
        
        var data = Data()
        var index = cleanHex.startIndex
        
        while index < cleanHex.endIndex {
            let nextIndex = cleanHex.index(index, offsetBy: 2)
            let byteString = cleanHex[index..<nextIndex]
            
            guard let byte = UInt8(byteString, radix: 16) else { return nil }
            
            data.append(byte)
            index = nextIndex
        }
        
        self = data
    }
    
    var bytes: [UInt8] {
        return [UInt8](self)
    }
}

extension CashuError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .networkError:
            return "Network error"
        case .cryptoError(let message):
            return "Crypto error: \(message)"
        case .quoteNotPaid:
            return "Quote not paid"
        case .invalidToken:
            return "Invalid token"
        case .tokenDecoding(let message):
            return "Token decoding error: \(message)"
        case .tokenEncoding(let message):
            return "Token encoding error: \(message)"
        case .insufficientInputs(let message):
            return "Insufficient inputs: \(message)"
        case .unitError(let message):
            return "Unit error: \(message)"
        case .spendingConditionError(let message):
            return "Spending condition error: \(message)"
        case .alreadySpent:
            return "Token has already been spent"
        default:
            return "Unknown Cashu error"
        }
    }
} 
