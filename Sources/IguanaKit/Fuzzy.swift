import Foundation

/// Tiny forgiving matcher. A contiguous match beats a scattered one; word starts and prefixes win ties.
public enum Fuzzy {
    public struct Match: Equatable, Sendable {
        public let score: Int
        /// Character offsets in the haystack that matched, for highlighting.
        public let indices: [Int]
    }

    public static func match(_ query: String, in text: String) -> Match? {
        let q = Array(query.lowercased()), t = Array(text.lowercased())
        guard !q.isEmpty else { return Match(score: 0, indices: []) }
        guard q.count <= t.count else { return nil }

        // 1. Contiguous substring.
        if let start = firstRange(of: q, in: t) {
            var score = 100 + q.count * 4
            if start == 0 { score += 40 } else if !t[start - 1].isLetter && !t[start - 1].isNumber { score += 20 }
            score -= min(start, 20)
            return Match(score: score, indices: Array(start..<start + q.count))
        }
        // 2. Subsequence ("btth" -> Bluetooth).
        var idx: [Int] = [], j = 0, run = 0, score = 0
        for (i, c) in t.enumerated() where j < q.count && c == q[j] {
            run = (idx.last == i - 1) ? run + 1 : 0
            score += 2 + run * 3 + ((i == 0 || !t[i - 1].isLetter) ? 6 : 0)
            idx.append(i); j += 1
        }
        return j == q.count ? Match(score: score, indices: idx) : nil
    }

    private static func firstRange(of q: [Character], in t: [Character]) -> Int? {
        guard t.count >= q.count else { return nil }
        for s in 0...(t.count - q.count) where Array(t[s..<s + q.count]) == q { return s }
        return nil
    }
}
