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
    
    @State private var showReceiveToken = false
    @State private var detectedToken: String?
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var alertTitle = ""
    
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
                        messageContentView
                        
                        // Delivery status indicator for private messages
                        if message.isPrivate && message.sender == viewModel.nickname,
                           let status = message.deliveryStatus {
                            DeliveryStatusView(status: status, colorScheme: colorScheme)
                                .padding(.leading, 4)
                        }
                    }
                    
                    // Cashu token detection and receive button
                    if let token = WalletManager.detectCashuToken(in: message.content) {
                        cashuTokenView(token: token)
                    }
                    
                    // Link previews would be handled here in the future
                    // For now, basic link detection is disabled
                }
            }
        }
        .sheet(isPresented: $showReceiveToken) {
            receiveTokenSheet
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK") { }
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
        
        // Always return a Text view, but with different content
        return Text(displayContent.isEmpty ? "" : viewModel.formatMessageAsText(
            BitchatMessage(
                sender: message.sender,
                content: displayContent,
                timestamp: message.timestamp,
                isRelay: message.isRelay,
                originalSender: message.originalSender,
                isPrivate: message.isPrivate,
                recipientNickname: message.recipientNickname,
                senderPeerID: message.senderPeerID,
                mentions: message.mentions,
                channel: message.channel,
                deliveryStatus: message.deliveryStatus
            ),
            colorScheme: colorScheme
        ))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: displayContent.isEmpty ? 0 : nil)
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
                    Text("tap to view and receive")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(secondaryTextColor)
                }
            }
            
            Spacer()
            
            Button(action: {
                print("[DEBUG] Token button tapped, setting detectedToken")
                detectedToken = token
                showReceiveToken = true
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
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    private var receiveTokenSheet: some View {
        NavigationView {
            VStack(spacing: 20) {
                Image(systemName: "bitcoinsign.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.orange)
                
                Text("ecash token")
                    .font(.system(size: 20, weight: .semibold, design: .monospaced))
                    .foregroundColor(textColor)
                
                if let token = detectedToken {
                    // Show the raw token in a scrollable view
                    ScrollView {
                        Text(token)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(textColor)
                            .textSelection(.enabled)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.orange.opacity(0.1))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                                    )
                            )
                    }
                    .frame(maxHeight: 200)
                    
                    Button(action: receiveToken) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 16))
                            Text("receive token")
                        }
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.orange)
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("No token detected")
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundColor(secondaryTextColor)
                        .padding()
                }
                
                Spacer()
            }
            .padding()
            .background(backgroundColor)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showReceiveToken = false
                        detectedToken = nil
                    }
                    .foregroundColor(textColor)
                }
            }
        }
        .onAppear {
            print("[DEBUG] Receive token sheet appeared")
            print("[DEBUG] detectedToken: \(detectedToken ?? "nil")")
        }
    }
    
    private func receiveToken() {
        guard let tokenString = detectedToken else { 
            print("[DEBUG] No detectedToken available")
            return 
        }
        
        print("[DEBUG] Attempting to receive token: \(String(tokenString.prefix(50)))...")
        
        Task {
            do {
                let amount = try await WalletManager.shared.receiveToken(tokenString)
                await MainActor.run {
                    showReceiveToken = false
                    detectedToken = nil
                    alertTitle = "Success!"
                    alertMessage = "Received \(amount) sats to your wallet!"
                    showAlert = true
                }
            } catch {
                await MainActor.run {
                    // Simplified error handling
                    alertTitle = "Token Receive Error"
                    
                    if error.localizedDescription.contains("blindedMessageAlreadySigned") {
                        alertMessage = "This token has already been spent or received."
                    } else {
                        alertMessage = "Failed to receive token: \(error.localizedDescription)"
                    }
                    
                    showAlert = true
                }
            }
        }
    }
} 