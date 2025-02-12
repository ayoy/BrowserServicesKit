//
//  SurrogatesUserScript.swift
//  Core
//
//  Copyright © 2020 DuckDuckGo. All rights reserved.
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

import WebKit
import os
import TrackerRadarKit

public protocol SurrogatesUserScriptDelegate: NSObjectProtocol {
    
    func surrogatesUserScriptShouldProcessTrackers(_ script: SurrogatesUserScript) -> Bool
    func surrogatesUserScript(_ script: SurrogatesUserScript,
                              detectedTracker tracker: DetectedTracker,
                              withSurrogate host: String)

}

public protocol SurrogatesUserScriptConfig: UserScriptSourceProviding {

    var privacyConfig: PrivacyConfiguration { get }
    var surrogates: String { get }
    var trackerData: TrackerData? { get }
    var encodedSurrogateTrackerData: String? { get }

}

public class DefaultSurrogatesUserScriptConfig: SurrogatesUserScriptConfig {

    public let privacyConfig: PrivacyConfiguration
    public let surrogates: String
    public let trackerData: TrackerData?
    public let encodedSurrogateTrackerData: String?

    public let source: String
    
    public init(privacyConfig: PrivacyConfiguration,
                surrogates: String,
                trackerData: TrackerData?,
                encodedSurrogateTrackerData: String?,
                trackerDataManager: TrackerDataManager,
                isDebugBuild: Bool) {

        if trackerData == nil {
            // Fallback to embedded
            self.trackerData = trackerDataManager.trackerData

            let surrogateTDS = ContentBlockerRulesManager.extractSurrogates(from: trackerDataManager.trackerData)
            let encodedData = try? JSONEncoder().encode(surrogateTDS)
            let encodedTrackerData = String(data: encodedData!, encoding: .utf8)!
            self.encodedSurrogateTrackerData = encodedTrackerData
        } else {
            self.trackerData = trackerData
            self.encodedSurrogateTrackerData = encodedSurrogateTrackerData
        }

        self.privacyConfig = privacyConfig
        self.surrogates = surrogates

        source = SurrogatesUserScript.generateSource(privacyConfiguration: self.privacyConfig,
                                                     surrogates: self.surrogates,
                                                     encodedSurrogateTrackerData: self.encodedSurrogateTrackerData,
                                                     isDebugBuild: isDebugBuild)
    }
}

open class SurrogatesUserScript: NSObject, UserScript {
    struct TrackerDetectedKey {
        static let protectionId = "protectionId"
        static let blocked = "blocked"
        static let networkName = "networkName"
        static let url = "url"
        static let isSurrogate = "isSurrogate"
        static let pageUrl = "pageUrl"
    }

    private let configuration: SurrogatesUserScriptConfig

    public init(configuration: SurrogatesUserScriptConfig) {
        self.configuration = configuration

        super.init()
    }

    open var source: String {
        return configuration.source
    }

    public var injectionTime: WKUserScriptInjectionTime = .atDocumentStart

    public var forMainFrameOnly: Bool = false

    public var messageNames: [String] = [ "trackerDetectedMessage" ]

    public weak var delegate: SurrogatesUserScriptDelegate?

    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let delegate = delegate else { return }
        guard delegate.surrogatesUserScriptShouldProcessTrackers(self) else { return }

        guard let dict = message.body as? [String: Any] else { return }
        guard let blocked = dict[TrackerDetectedKey.blocked] as? Bool else { return }
        guard let urlString = dict[TrackerDetectedKey.url] as? String else { return }
        guard let pageUrlStr = dict[TrackerDetectedKey.pageUrl] as? String else { return }

        let tracker = trackerFromUrl(urlString.trimWhitespace(), pageUrlString: pageUrlStr, blocked)

        if let isSurrogate = dict[TrackerDetectedKey.isSurrogate] as? Bool, isSurrogate, let host = URL(string: urlString)?.host {
            delegate.surrogatesUserScript(self, detectedTracker: tracker, withSurrogate: host)
        }
    }
    private func trackerFromUrl(_ urlString: String, pageUrlString: String, _ blocked: Bool) -> DetectedTracker {
        let currentTrackerData = configuration.trackerData
        let knownTracker = currentTrackerData?.findTracker(forUrl: urlString)
        let entity = currentTrackerData?.findEntity(byName: knownTracker?.owner?.name ?? "")
        return DetectedTracker(url: urlString, knownTracker: knownTracker, entity: entity, blocked: blocked, pageUrl: pageUrlString)
    }

    public static func generateSource(privacyConfiguration: PrivacyConfiguration,
                                      surrogates: String,
                                      encodedSurrogateTrackerData: String?,
                                      isDebugBuild: Bool) -> String {
        let remoteUnprotectedDomains = (privacyConfiguration.tempUnprotectedDomains.joined(separator: "\n"))
            + "\n"
            + (privacyConfiguration.exceptionsList(forFeature: .contentBlocking).joined(separator: "\n"))

        // Encode whatever the tracker data manager is using to ensure it's in sync and because we know it will work
        let trackerData: String
        if let data = encodedSurrogateTrackerData {
            trackerData = data
        } else {
            let encodedData = try? JSONEncoder().encode(TrackerData(trackers: [:], entities: [:], domains: [:], cnames: [:]))
            trackerData = String(data: encodedData!, encoding: .utf8)!
        }

        return SurrogatesUserScript.loadJS("surrogates", from: Bundle.module, withReplacements: [
            "$IS_DEBUG$": isDebugBuild ? "true" : "false",
            "$TEMP_UNPROTECTED_DOMAINS$": remoteUnprotectedDomains,
            "$USER_UNPROTECTED_DOMAINS$": privacyConfiguration.userUnprotectedDomains.joined(separator: "\n"),
            "$TRACKER_ALLOWLIST_ENTRIES$": TrackerAllowlistInjection.prepareForInjection(allowlist: privacyConfiguration.trackerAllowlist),
            "$TRACKER_DATA$": trackerData,
            "$SURROGATES$": surrogates,
            "$BLOCKING_ENABLED$": privacyConfiguration.isEnabled(featureKey: .contentBlocking) ? "true" : "false"
        ])
    }
}
