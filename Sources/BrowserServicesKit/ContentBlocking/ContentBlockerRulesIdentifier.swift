//
//  ContentBlockerRulesIdentifier.swift
//  DuckDuckGo
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

public class ContentBlockerRulesIdentifier: Equatable {
    
    private let name: String
    private let tdsEtag: String
    private let tempListEtag: String
    private let allowListEtag: String
    private let unprotectedSitesHash: String
    
    public var stringValue: String {
        return name + tdsEtag + tempListEtag + unprotectedSitesHash
    }
    
    public struct Difference: OptionSet {
        public let rawValue: Int
        
        public init(rawValue: Int) {
            self.rawValue = rawValue
        }
        
        public static let tdsEtag = Difference(rawValue: 1 << 0)
        public static let tempListEtag = Difference(rawValue: 1 << 1)
        public static let allowListEtag = Difference(rawValue: 1 << 2)
        public static let unprotectedSites = Difference(rawValue: 1 << 3)
        
        public static let all: Difference = [.tdsEtag, .tempListEtag, .allowListEtag, .unprotectedSites]
    }
    
    private class func normalize(identifier: String?) -> String {
        // Ensure identifier is in double quotes
        guard var identifier = identifier else {
            return "\"\""
        }
        
        if !identifier.hasSuffix("\"") {
            identifier += "\""
        }
        
        if !identifier.hasPrefix("\"") || identifier.count == 1 {
            identifier = "\"" + identifier
        }
        
        return identifier
    }
    
    public class func hash(domains: [String]?) -> String {
        guard let domains = domains, !domains.isEmpty else {
            return ""
        }
        
        return domains.joined().sha1
    }
    
    public init(name: String, tdsEtag: String, tempListEtag: String?, allowListEtag: String?, unprotectedSitesHash: String?) {
        
        self.name = Self.normalize(identifier: name)
        self.tdsEtag = Self.normalize(identifier: tdsEtag)
        self.tempListEtag = Self.normalize(identifier: tempListEtag)
        self.allowListEtag = Self.normalize(identifier: allowListEtag)
        self.unprotectedSitesHash = Self.normalize(identifier: unprotectedSitesHash)
    }
    
    public func compare(with id: ContentBlockerRulesIdentifier) -> Difference {
        
        var result = Difference()
        if tdsEtag != id.tdsEtag {
            result.insert(.tdsEtag)
        }
        if tempListEtag != id.tempListEtag {
            result.insert(.tempListEtag)
        }
        if allowListEtag != id.allowListEtag {
            result.insert(.allowListEtag)
        }
        if unprotectedSitesHash != id.unprotectedSitesHash {
            result.insert(.unprotectedSites)
        }
        
        return result
    }

    public static func == (lhs: ContentBlockerRulesIdentifier, rhs: ContentBlockerRulesIdentifier) -> Bool {
        return lhs.compare(with: rhs).isEmpty
    }
}
