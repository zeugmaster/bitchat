//
// WalletView.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import SwiftUI

struct WalletView: View {
    @ObservedObject private var walletManager = WalletManager.shared
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    @State private var showAddMint = false
    @State private var showReceiveToken = false
    @State private var newMintURL = ""
    @State private var newMintName = ""
    @State private var receiveTokenString = ""
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var alertTitle = ""
    
    private var backgroundColor: Color {
        colorScheme == .dark ? Color.black : Color.white
    }
    
    private var textColor: Color {
        colorScheme == .dark ? Color.green : Color(red: 0, green: 0.5, blue: 0)
    }
    
    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.green.opacity(0.8) : Color(red: 0, green: 0.5, blue: 0).opacity(0.8)
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                headerView
                
                // Balance section
                balanceSection
                
                // Quick actions
                quickActions
                
                Spacer()
            }
            .background(backgroundColor)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(textColor)
                }
            }
        }
        .sheet(isPresented: $showAddMint) {
            addMintSheet
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
    
    private var headerView: some View {
        VStack(spacing: 8) {
            Image(systemName: "wallet.pass")
                .font(.system(size: 32))
                .foregroundColor(textColor)
            
            Text("cashu wallet")
                .font(.system(size: 18, weight: .medium, design: .monospaced))
                .foregroundColor(textColor)
        }
        .padding(.top, 20)
        .padding(.bottom, 30)
    }
    
    private var balanceSection: some View {
        VStack(spacing: 12) {
            Text("balances by mint")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundColor(textColor)
            
            if walletManager.mints.isEmpty {
                VStack(spacing: 8) {
                    Text("0 sats")
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .foregroundColor(textColor)
                    Text("no mints added yet")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(secondaryTextColor)
                }
                .padding(.vertical, 20)
                .padding(.horizontal, 20)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(textColor.opacity(0.3), lineWidth: 1)
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(walletManager.mints) { mint in
                        mintBalanceRowView(mint: mint)
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(textColor.opacity(0.3), lineWidth: 1)
                )
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 30)
    }
    
    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("actions")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundColor(textColor)
            
            HStack(spacing: 12) {
                Button(action: { showReceiveToken = true }) {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 24))
                        Text("receive")
                            .font(.system(size: 12, design: .monospaced))
                    }
                    .foregroundColor(textColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(textColor.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                
                Button(action: { showAddMint = true }) {
                    VStack(spacing: 8) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 24))
                        Text("add mint")
                            .font(.system(size: 12, design: .monospaced))
                    }
                    .foregroundColor(textColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(textColor.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 30)
    }

    
    private func mintBalanceRowView(mint: StoredMint) -> some View {
        HStack(spacing: 12) {
            Text(mint.url)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundColor(textColor)
                .lineLimit(1)
            
            Spacer()
            
            Text("\(walletManager.getBalanceForMint(mint.url)) sats")
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(textColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    
    private var addMintSheet: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("add mint")
                    .font(.system(size: 18, weight: .medium, design: .monospaced))
                    .foregroundColor(textColor)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("mint url")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(secondaryTextColor)
                    
                    TextField("Mint URL (e.g. https://mint.example.com)", text: $newMintURL)
                        .font(.system(size: 14, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        #endif
                        .disableAutocorrection(true)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("name (optional)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(secondaryTextColor)
                    
                    TextField("My Mint", text: $newMintName)
                        .font(.system(size: 14, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                }
                
                Button(action: addMint) {
                    Text("add mint")
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(backgroundColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(textColor)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(newMintURL.isEmpty || walletManager.isLoading)
                
                if walletManager.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: textColor))
                }
                
                Spacer()
            }
            .padding()
            .background(backgroundColor)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showAddMint = false
                        resetAddMintForm()
                    }
                    .foregroundColor(textColor)
                }
            }
        }
    }
    
    private var receiveTokenSheet: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("receive cashu token")
                    .font(.system(size: 18, weight: .medium, design: .monospaced))
                    .foregroundColor(textColor)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("paste token here")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(secondaryTextColor)
                    
                    TextEditor(text: $receiveTokenString)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(height: 120)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(secondaryTextColor.opacity(0.3), lineWidth: 1)
                        )
                }
                
                Button(action: receiveToken) {
                    Text("receive token")
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(backgroundColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(textColor)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(receiveTokenString.isEmpty)
                
                Spacer()
            }
            .padding()
            .background(backgroundColor)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showReceiveToken = false
                        receiveTokenString = ""
                    }
                    .foregroundColor(textColor)
                }
            }
        }
    }
    
    private func addMint() {
        Task {
            do {
                try await walletManager.addMint(
                    url: newMintURL.trimmingCharacters(in: .whitespacesAndNewlines),
                    name: newMintName.isEmpty ? nil : newMintName.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                await MainActor.run {
                    showAddMint = false
                    resetAddMintForm()
                }
            } catch {
                await MainActor.run {
                    alertTitle = "Error"
                    alertMessage = "Failed to add mint: \(error.localizedDescription)"
                    showAlert = true
                }
            }
        }
    }
    
    private func receiveToken() {
        // Debug the token first
        walletManager.debugToken(receiveTokenString.trimmingCharacters(in: .whitespacesAndNewlines))
        
        Task {
            do {
                let amount = try await walletManager.receiveToken(receiveTokenString.trimmingCharacters(in: .whitespacesAndNewlines))
                await MainActor.run {
                    showReceiveToken = false
                    receiveTokenString = ""
                    alertTitle = "Success"
                    alertMessage = "Received \(amount) sats!"
                    showAlert = true
                }
            } catch {
                await MainActor.run {
                    alertTitle = "Token Receive Error"
                    
                    // Check for specific error types
                    if let walletError = error as? WalletError {
                        switch walletError {
                        case .invalidToken:
                            alertMessage = "This token is invalid or has already been spent."
                        case .invalidMintURL:
                            alertMessage = "The token contains an invalid mint URL."
                        default:
                            alertMessage = walletError.localizedDescription
                        }
                    } else {
                        alertMessage = error.localizedDescription
                    }
                    
                    showAlert = true
                }
            }
        }
    }
    
    private func resetAddMintForm() {
        newMintURL = ""
        newMintName = ""
    }
} 