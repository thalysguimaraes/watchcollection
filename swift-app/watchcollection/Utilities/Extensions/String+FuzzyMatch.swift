import Foundation

extension String {
    func levenshteinDistance(to other: String) -> Int {
        let m = self.count
        let n = other.count

        if m == 0 { return n }
        if n == 0 { return m }

        var matrix = [[Int]](repeating: [Int](repeating: 0, count: n + 1), count: m + 1)

        for i in 0...m { matrix[i][0] = i }
        for j in 0...n { matrix[0][j] = j }

        let selfArray = Array(self.lowercased())
        let otherArray = Array(other.lowercased())

        for i in 1...m {
            for j in 1...n {
                let cost = selfArray[i-1] == otherArray[j-1] ? 0 : 1
                matrix[i][j] = Swift.min(
                    matrix[i-1][j] + 1,
                    matrix[i][j-1] + 1,
                    matrix[i-1][j-1] + cost
                )
            }
        }

        return matrix[m][n]
    }

    func fuzzyMatch(_ query: String, threshold: Double = 0.3) -> Bool {
        let distance = self.levenshteinDistance(to: query)
        let maxLen = max(self.count, query.count)
        guard maxLen > 0 else { return false }
        let similarity = 1.0 - (Double(distance) / Double(maxLen))
        return similarity >= (1.0 - threshold)
    }

    func fuzzyScore(_ query: String) -> Double {
        let distance = self.levenshteinDistance(to: query)
        let maxLen = max(self.count, query.count)
        guard maxLen > 0 else { return 0 }
        return 1.0 - (Double(distance) / Double(maxLen))
    }
}
