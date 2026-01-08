//
//  WebSearcher.swift
//  AIEdgeApp
//
//  Created by Jérôme Pitault on 28.12.2025.
//

import Foundation

enum WebSearchError: Error {
    case invalidURL
    case networkError(Error)
    case noData
    case decodingError
}

struct SearchResult: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let link: String
    let snippet: String
}

class WebSearcher {
    static let shared = WebSearcher()
    
    private let session = URLSession.shared
    
    /// Performs a search using DuckDuckGo HTML endpoint
    func search(query: String) async throws -> [SearchResult] {
        print("DEBUG PRE-SEARCH: query='\(query)'")
        // Use the HTML version of DuckDuckGo which is easier to scrape and doesn't require JS
        guard let url = URL(string: "https://html.duckduckgo.com/html/") else {
            throw WebSearchError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        
        let bodyComponents = [
            "q": query,
            "kl": "us-en" // Region/Language
        ]
        
        let bodyString = bodyComponents.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
        
        request.httpBody = bodyString.data(using: .utf8)
        
        print("DEBUG PRE-SEARCH: Sending request")
        let (data, _) = try await session.data(for: request)
        print("DEBUG PRE-SEARCH: Received response, data size: \(data.count) bytes")
        
        guard let htmlString = String(data: data, encoding: .utf8) else {
            throw WebSearchError.decodingError
        }
        
        print("DEBUG PRE-SEARCH: Parsing HTML")
        return parseDuckDuckGoHTML(htmlString)
    }
    
    private func parseDuckDuckGoHTML(_ html: String) -> [SearchResult] {
        var results: [SearchResult] = []
        
        // More robust parsing strategy:
        // 1. Find all links with class="result__a" (contains href and title)
        // 2. Find all snippets with class="result__snippet"
        // 3. Zip them together (assuming sequential order)
        
        let linkPattern = "<a[^>]*class=\"[^\"]*result__a[^\"]*\"[^>]*href=\"([^\"]+)\"[^>]*>(.*?)</a>"
        let snippetPattern = "<a[^>]*class=\"[^\"]*result__snippet[^\"]*\"[^>]*>(.*?)</a>"
        
        let linkMatches = extractAll(from: html, pattern: linkPattern, groups: [1, 2]) // [ [href, title], [href, title] ... ]
        let snippetMatches = extractAll(from: html, pattern: snippetPattern, groups: [1]) // [ [snippet], [snippet] ... ]
        
        // Zip them up to the count of the smaller array
        let count = min(linkMatches.count, snippetMatches.count)
        
        for i in 0..<count {
            let linkData = linkMatches[i]
            let snippetData = snippetMatches[i]
            
            if linkData.count >= 2 && snippetData.count >= 1 {
                let rawLink = linkData[0]
                let rawTitle = linkData[1]
                let rawSnippet = snippetData[0]
                
                // Clean content
                let cleanTitle = decodeHTMLEntities(rawTitle).trimmingCharacters(in: .whitespacesAndNewlines)
                var cleanLink = rawLink
                
                // Decode DDG link redirection
                if let decodedLink = rawLink.removingPercentEncoding,
                   let range = decodedLink.range(of: "uddg=") {
                    cleanLink = String(decodedLink[range.upperBound...])
                }
                
                let cleanSnippet = decodeHTMLEntities(rawSnippet).trimmingCharacters(in: .whitespacesAndNewlines)
                
                if !cleanTitle.isEmpty {
                     results.append(SearchResult(title: cleanTitle, link: cleanLink, snippet: cleanSnippet))
                }
            }
        }
        
        return results
    }
    
    /// Helper to extract all regex matches from text
    /// Returns an array of matches, where each match is an array of captured groups
    private func extractAll(from text: String, pattern: String, groups: [Int]) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, options: [], range: range)
        
        return matches.map { match in
            return groups.map { groupIdx in
                if groupIdx < match.numberOfRanges,
                   let range = Range(match.range(at: groupIdx), in: text) {
                    return String(text[range])
                }
                return ""
            }
        }
    }
    
    private func decodeHTMLEntities(_ string: String) -> String {
        // Basic decoding
        return string
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "<b>", with: "") // Remove bold tags
            .replacingOccurrences(of: "</b>", with: "")
    }
}
