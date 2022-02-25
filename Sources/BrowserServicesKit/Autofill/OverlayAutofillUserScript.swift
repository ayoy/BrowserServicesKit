//
//  OverlayAutofillUserScript.swift
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

public class OverlayAutofillUserScript: AutofillUserScript {
    
    public var contentOverlay: TopOverlayAutofillUserScriptDelegate?
    /// Used as a message channel from parent WebView to the relevant in page AutofillUserScript.
    public var autofillInterfaceToChild: AutofillMessagingToChildDelegate?

    internal enum OverlayAutofillMessageName: String, CaseIterable {
        case setSize
        case selectedDetail
        case closeAutofillParent
    }
    
    public override var messageNames: [String] {
        return OverlayAutofillMessageName.allCases.map(\.rawValue) + super.messageNames
    }
    
    internal override func messageHandlerFor(_ messageName: String) -> MessageHandler? {
        guard let overlayAutofillMessage = OverlayAutofillMessageName(rawValue: messageName) else {
            return super.messageHandlerFor(messageName)
        }

        switch overlayAutofillMessage {
        // Top Autofill specific messages
        case .setSize: return setSize
        case .selectedDetail: return selectedDetail

        // For child and parent autofill
        case .closeAutofillParent: return closeAutofillParent
        }
    }
    
    override func hostForMessage(_ message: AutofillMessage) -> String {
        return autofillInterfaceToChild?.lastOpenHost ?? ""
    }
    func closeAutofillParent(_ message: AutofillMessage, _ replyHandler: MessageReplyHandler) {
        guard let autofillInterfaceToChild = autofillInterfaceToChild else { return }
        self.contentOverlay?.requestResizeToSize(width: 0, height: 0)
        autofillInterfaceToChild.close()
        replyHandler(nil)
    }
    
    /// Used to create a top autofill context script for injecting into a ContentOverlay
    public convenience init(scriptSourceProvider: AutofillUserScriptSourceProvider, overlay: TopOverlayAutofillUserScriptDelegate) {
        self.init(scriptSourceProvider: scriptSourceProvider, encrypter: AESGCMAutofillEncrypter(), hostProvider: SecurityOriginHostProvider())
        self.isTopAutofillContext = true
        self.contentOverlay = overlay
    }
    
    func setSize(_ message: AutofillMessage, _ replyHandler: MessageReplyHandler) {
        guard let dict = message.messageBody as? [String: Any],
              let width = dict["width"] as? CGFloat,
              let height = dict["height"] as? CGFloat else {
                  return replyHandler(nil)
              }
        self.contentOverlay?.requestResizeToSize(width: width, height: height)
        replyHandler(nil)
    }

    /// Called from top autofill messages and stores the details the user clicked on into the child autofill
    func selectedDetail(_ message: AutofillMessage, _ replyHandler: @escaping MessageReplyHandler) {
        guard let dict = message.messageBody as? [String: Any],
              let chosenCredential = dict["data"] as? [String: String],
              let configType = dict["configType"] as? String,
              let autofillInterfaceToChild = autofillInterfaceToChild else { return }
        autofillInterfaceToChild.messageSelectedCredential(chosenCredential, configType)
    }

}
