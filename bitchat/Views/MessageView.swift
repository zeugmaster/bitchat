//
// MessageView.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import SwiftUI

struct MessageView: View {
    let message: BitchatMessage
    let viewModel: ChatViewModel
    let colorScheme: ColorScheme
    

    
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
                        // Enhanced message content
                        messageContentView
                        
                        // Delivery status indicator for private messages
                        if message.isPrivate && message.sender == viewModel.nickname,
                           let status = message.deliveryStatus {
                            DeliveryStatusView(status: status, colorScheme: colorScheme)
                                .padding(.leading, 4)
                        }
                    }
                    

                    
                    // Link previews would be handled here in the future
                    // For now, basic link detection is disabled
                }
            }
        }
    }
    
    private var messageContentView: some View {
        return Text(viewModel.formatMessageAsText(message, colorScheme: colorScheme))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

} 