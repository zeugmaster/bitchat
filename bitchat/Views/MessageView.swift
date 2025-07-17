//
// MessageView.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import SwiftUI
import CashuSwift

struct MessageView: View {
    let message: BitchatMessage
    let viewModel: ChatViewModel
    let colorScheme: ColorScheme
    
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var alertTitle = ""
    
    // Token receive states per token (using token string as key)
    @State private var tokenReceiveStates: [String: TokenReceiveState] = [:]
    
    enum TokenReceiveState {
        case idle
        case receiving
        case success(amount: Int)
        case error(message: String)
    }
    
    private var textColor: Color {
        colorScheme == .dark ? Color.green : Color(red: 0, green: 0.5, blue: 0)
    }
    
    private var backgroundColor: Color {
        colorScheme == .dark ? Color.black : Color.white
    }
    
    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.green.opacity(0.8) : Color(red: 0, green: 0.5, blue: 0).opacity(0.8)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Check if current user is mentioned
            let _ = message.mentions?.contains(viewModel.nickname) ?? false
            
            if message.sender == "system" {
                // System messages
                Text(viewModel.formatMessageAsText(message, colorScheme: colorScheme))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                // Regular messages with natural text wrapping
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 0) {
                        // Enhanced message content with cashu token detection
                        VStack(alignment: .leading, spacing: 8) {
                            // Show message content without token
                            messageContentView
                            
                            // Show token card if detected
                            if let token = WalletManager.detectCashuToken(in: message.content) {
                                cashuTokenView(token: token)
                            }
                        }
                        
                        Spacer()
                    }
                }
            }
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
    }
    
    private var messageContentView: some View {
        let displayContent: String
        if let token = WalletManager.detectCashuToken(in: message.content) {
            // Completely remove the token from the message content
            displayContent = message.content.replacingOccurrences(of: token, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            displayContent = message.content
        }
        
        // Only show the content if there's something left after removing the token
        if !displayContent.isEmpty {
            return AnyView(Text(viewModel.formatMessageAsText(
                BitchatMessage(
                    sender: message.sender,
                    content: displayContent,
                    timestamp: message.timestamp,
                    isRelay: message.isRelay,
                    originalSender: message.originalSender,
                    senderPeerID: message.senderPeerID,
                    mentions: message.mentions,
                    channel: message.channel,
                    deliveryStatus: message.deliveryStatus
                ),
                colorScheme: colorScheme
            ))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading))
        } else {
            return AnyView(EmptyView())
        }
    }
    
    // Token parsing function to extract amount and mint info
    private func parseTokenInfo(_ tokenString: String) -> (amount: Int, memo: String?, mintURL: String)? {
        do {
            let token = try tokenString.deserializeToken()
            let totalAmount = token.proofsByMint.values.flatMap { $0 }.reduce(0) { $0 + $1.amount }
            
            // Get the first mint URL
            guard let mintURL = token.proofsByMint.keys.first else {
                return nil
            }
            
            return (totalAmount, token.memo, mintURL)
        } catch {
            return nil
        }
    }
    
    // Extract mint display name from URL
    private func mintDisplayName(from url: String) -> String {
        if let parsedURL = URL(string: url) {
            return parsedURL.host ?? url
        }
        return url
    }
    
    private func cashuTokenView(token: String) -> some View {
        let tokenInfo = parseTokenInfo(token)
        let receiveState = tokenReceiveStates[token] ?? .idle
        
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "bitcoinsign.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.orange)
                    
                    Text("ecash token")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(textColor)
                }
                
                if let info = tokenInfo {
                    // Show token amount
                    HStack(spacing: 4) {
                        Text("\(info.amount)")
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundColor(textColor)
                        Text("sats")
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundColor(secondaryTextColor)
                    }
                    
                    // Show mint name
                    Text("from \(mintDisplayName(from: info.mintURL))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(secondaryTextColor)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    // Show memo if present
                    if let memo = info.memo, !memo.isEmpty {
                        Text("\"\(memo)\"")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(secondaryTextColor)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                } else {
                    // Fallback when parsing fails
                    Text("tap to receive")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(secondaryTextColor)
                }
                
                // Show receive state feedback
                switch receiveState {
                case .receiving:
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("receiving...")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(secondaryTextColor)
                    }
                case .success(let amount):
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.green)
                        Text("received \(amount) sats!")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.green)
                    }
                case .error(let message):
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                        Text(message)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.red)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                case .idle:
                    EmptyView()
                }
            }
            
            Spacer()
            
            // Receive button or status indicator
            switch receiveState {
            case .receiving:
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("receiving")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.6))
                .cornerRadius(6)
                
            case .success:
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                    Text("received")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.green)
                .cornerRadius(6)
                
            case .error:
                Button(action: {
                    receiveToken(token)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise.circle.fill")
                            .font(.system(size: 14))
                        Text("retry")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.red)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                
            case .idle:
                Button(action: {
                    receiveToken(token)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 14))
                        Text("receive")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.orange)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundColorForState(receiveState))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(borderColorForState(receiveState), lineWidth: 1)
                )
        )
    }
    
    private func backgroundColorForState(_ state: TokenReceiveState) -> Color {
        switch state {
        case .idle, .receiving:
            return Color.orange.opacity(0.08)
        case .success:
            return Color.green.opacity(0.08)
        case .error:
            return Color.red.opacity(0.08)
        }
    }
    
    private func borderColorForState(_ state: TokenReceiveState) -> Color {
        switch state {
        case .idle, .receiving:
            return Color.orange.opacity(0.3)
        case .success:
            return Color.green.opacity(0.3)
        case .error:
            return Color.red.opacity(0.3)
        }
    }
    
    private func receiveToken(_ tokenString: String) {
        print("[DEBUG] Attempting to receive token directly: \(String(tokenString.prefix(50)))...")
        
        // Set receiving state
        tokenReceiveStates[tokenString] = .receiving
        
        Task {
            do {
                let amount = try await WalletManager.shared.receiveToken(tokenString)
                await MainActor.run {
                    // Keep token permanently in success state - don't allow re-redemption
                    tokenReceiveStates[tokenString] = .success(amount: amount)
                }
            } catch {
                await MainActor.run {
                    let errorMessage: String
                    if error.localizedDescription.contains("blindedMessageAlreadySigned") || error.localizedDescription.contains("alreadySpent") {
                        errorMessage = "already spent"
                    } else if error.localizedDescription.contains("network") || error.localizedDescription.contains("Network") {
                        errorMessage = "network error"
                    } else {
                        errorMessage = "receive failed"
                    }
                    
                    tokenReceiveStates[tokenString] = .error(message: errorMessage)
                    
                    // Auto-hide error state after 8 seconds so users can read the message
                    DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                        tokenReceiveStates[tokenString] = .idle
                    }
                }
            }
        }
    }
} 