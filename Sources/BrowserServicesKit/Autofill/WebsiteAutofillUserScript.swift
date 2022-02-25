//
//  WebsiteAutofillUserScript.swift
//  DuckDuckGo
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation

public class WebsiteAutofillUserScript: AutofillUserScript {
    public var lastOpenHost: String?
    /// Holds a reference to the tab that is displaying the content overlay.
    public weak var currentOverlayTab: ChildOverlayAutofillUserScriptDelegate?
    /// Last user click position, used to position the overlay
    public var clickPoint: CGPoint?
    /// Last user selected details in the top autofill overlay stored in the child.
    var selectedDetailsData: SelectedDetailsData?
    
    public override var messageNames: [String] {
        return WebsiteAutofillMessageName.allCases.map(\.rawValue) + super.messageNames
    }
    
    public convenience init(scriptSourceProvider: AutofillUserScriptSourceProvider) {
        self.init(scriptSourceProvider: scriptSourceProvider,
                  encrypter: AESGCMAutofillEncrypter(),
                  hostProvider: SecurityOriginHostProvider())
    }

    private enum WebsiteAutofillMessageName: String, CaseIterable {
        case closeAutofillParent

        case getSelectedCredentials
        case showAutofillParent
    }

    
    internal override func messageHandlerFor(_ messageName: String) -> MessageHandler? {
        guard let websiteAutofillMessageName = WebsiteAutofillMessageName(rawValue: messageName) else {
            return super.messageHandlerFor(messageName)
        }
        
        switch websiteAutofillMessageName {
        // Child Autofill specific messages
        case .getSelectedCredentials: return getSelectedCredentials
        case .showAutofillParent: return showAutofillParent

        // For child and parent autofill
        case .closeAutofillParent: return closeAutofillParent
        }
    }
    
    override func hostForMessage(_ message: AutofillMessage) -> String {
        return hostProvider.hostForMessage(message)
    }
    func showAutofillParent(_ message: AutofillMessage, _ replyHandler: MessageReplyHandler) {
        guard let dict = message.messageBody as? [String: Any],
              let left = dict["inputLeft"] as? CGFloat,
              let top = dict["inputTop"] as? CGFloat,
              let height = dict["inputHeight"] as? CGFloat,
              let width = dict["inputWidth"] as? CGFloat,
              let serializedInputContext = dict["serializedInputContext"] as? String,
              let currentOverlayTab = currentOverlayTab,
              let clickPoint = clickPoint else {
                  return
              }
        // Sets the last message host, so we can check when it messages back
        lastOpenHost = hostProvider.hostForMessage(message)

        currentOverlayTab.autofillDisplayOverlay(self,
                                                 of: currentOverlayTab.view,
                                                 serializedInputContext: serializedInputContext,
                                                 click: clickPoint,
                                                 inputPosition: CGRect(x: left, y: top, width: width, height: height))
        replyHandler(nil)
    }
    public func close() {
        guard let currentOverlayTab = currentOverlayTab else { return }
        currentOverlayTab.autofillCloseOverlay(self)
        selectedDetailsData = nil
        lastOpenHost = nil
    }
    func closeAutofillParent(_ message: AutofillMessage, _ replyHandler: MessageReplyHandler) {
        close()
        replyHandler(nil)
    }
    /// Called from the child autofill to return referenced credentials
    func getSelectedCredentials(_ message: AutofillMessage, _ replyHandler: MessageReplyHandler) {
        var response = GetSelectedCredentialsResponse(type: "none")
        if lastOpenHost == nil || message.messageHost != lastOpenHost {
            response = GetSelectedCredentialsResponse(type: "stop")
        } else if let selectedDetailsData = selectedDetailsData {
            response = GetSelectedCredentialsResponse(type: "ok", data: selectedDetailsData.data, configType: selectedDetailsData.configType)
            self.selectedDetailsData = nil
        }
        if let json = try? JSONEncoder().encode(response),
           let jsonString = String(data: json, encoding: .utf8) {
            replyHandler(jsonString)
        }
    }
}
extension WebsiteAutofillUserScript: AutofillMessagingToChildDelegate {
    public func messageSelectedCredential(_ data: [String: String], _ configType: String) {
        guard let currentOverlayTab = currentOverlayTab else { return }
        currentOverlayTab.autofillCloseOverlay(self)
        selectedDetailsData = SelectedDetailsData(data: data, configType: configType)
    }
}
