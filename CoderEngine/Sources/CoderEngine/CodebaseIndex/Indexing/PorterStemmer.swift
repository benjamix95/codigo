import Foundation

// MARK: - Porter Stemmer (English)
// Lightweight implementation of the Porter Stemming Algorithm for English.
// Used to normalize tokens so "authenticating" → "authent", "authenticated" → "authent", etc.

enum PorterStemmer {
    /// Stem a single lowercase English word.
    static func stem(_ word: String) -> String {
        guard word.count > 2 else { return word }
        var w = word

        // Step 1a
        if w.hasSuffix("sses") {
            w = String(w.dropLast(2))
        } else if w.hasSuffix("ies") {
            w = String(w.dropLast(2))
        } else if !w.hasSuffix("ss") && w.hasSuffix("s") {
            w = String(w.dropLast())
        }

        // Step 1b
        let step1bHandled: Bool
        if w.hasSuffix("eed") {
            let stem = String(w.dropLast(3))
            if measure(stem) > 0 {
                w = String(w.dropLast())  // eed → ee
            }
            step1bHandled = false
        } else if w.hasSuffix("ed") {
            let stem = String(w.dropLast(2))
            if containsVowel(stem) {
                w = stem
                step1bHandled = true
            } else {
                step1bHandled = false
            }
        } else if w.hasSuffix("ing") {
            let stem = String(w.dropLast(3))
            if containsVowel(stem) {
                w = stem
                step1bHandled = true
            } else {
                step1bHandled = false
            }
        } else {
            step1bHandled = false
        }

        if step1bHandled {
            if w.hasSuffix("at") || w.hasSuffix("bl") || w.hasSuffix("iz") {
                w += "e"
            } else if hasDoubleConsonant(w) && !w.hasSuffix("l") && !w.hasSuffix("s") && !w.hasSuffix("z") {
                w = String(w.dropLast())
            } else if measure(w) == 1 && endsWithCVC(w) {
                w += "e"
            }
        }

        // Step 1c
        if w.hasSuffix("y") {
            let stem = String(w.dropLast())
            if containsVowel(stem) {
                w = stem + "i"
            }
        }

        // Step 2
        let step2Suffixes: [(String, String)] = [
            ("ational", "ate"), ("tional", "tion"), ("enci", "ence"), ("anci", "ance"),
            ("izer", "ize"), ("abli", "able"), ("alli", "al"), ("entli", "ent"),
            ("eli", "e"), ("ousli", "ous"), ("ization", "ize"), ("ation", "ate"),
            ("ator", "ate"), ("alism", "al"), ("iveness", "ive"), ("fulness", "ful"),
            ("ousness", "ous"), ("aliti", "al"), ("iviti", "ive"), ("biliti", "ble"),
        ]
        for (suffix, replacement) in step2Suffixes {
            if w.hasSuffix(suffix) {
                let stem = String(w.dropLast(suffix.count))
                if measure(stem) > 0 {
                    w = stem + replacement
                }
                break
            }
        }

        // Step 3
        let step3Suffixes: [(String, String)] = [
            ("icate", "ic"), ("ative", ""), ("alize", "al"),
            ("iciti", "ic"), ("ical", "ic"), ("ful", ""), ("ness", ""),
        ]
        for (suffix, replacement) in step3Suffixes {
            if w.hasSuffix(suffix) {
                let stem = String(w.dropLast(suffix.count))
                if measure(stem) > 0 {
                    w = stem + replacement
                }
                break
            }
        }

        // Step 4
        let step4Suffixes = [
            "al", "ance", "ence", "er", "ic", "able", "ible", "ant",
            "ement", "ment", "ent", "ion", "ou", "ism", "ate", "iti",
            "ous", "ive", "ize",
        ]
        for suffix in step4Suffixes {
            if w.hasSuffix(suffix) {
                let stem = String(w.dropLast(suffix.count))
                if measure(stem) > 1 {
                    if suffix == "ion" {
                        if stem.hasSuffix("s") || stem.hasSuffix("t") {
                            w = stem
                        }
                    } else {
                        w = stem
                    }
                }
                break
            }
        }

        // Step 5a
        if w.hasSuffix("e") {
            let stem = String(w.dropLast())
            if measure(stem) > 1 || (measure(stem) == 1 && !endsWithCVC(stem)) {
                w = stem
            }
        }

        // Step 5b
        if measure(w) > 1 && hasDoubleConsonant(w) && w.hasSuffix("l") {
            w = String(w.dropLast())
        }

        return w
    }

    // MARK: - Helpers

    private static func isVowel(_ c: Character, previous: Character? = nil) -> Bool {
        switch c {
        case "a", "e", "i", "o", "u": return true
        case "y": return previous != nil && !isVowel(previous!)
        default: return false
        }
    }

    private static func containsVowel(_ word: String) -> Bool {
        let chars = Array(word)
        for i in 0..<chars.count {
            let prev = i > 0 ? chars[i - 1] : nil
            if isVowel(chars[i], previous: prev) { return true }
        }
        return false
    }

    /// Measure: the number of VC sequences in the word.
    private static func measure(_ word: String) -> Int {
        let chars = Array(word)
        guard !chars.isEmpty else { return 0 }
        var m = 0
        var i = 0

        // Skip initial consonants
        while i < chars.count {
            let prev = i > 0 ? chars[i - 1] : nil
            if isVowel(chars[i], previous: prev) { break }
            i += 1
        }

        while i < chars.count {
            // Skip vowels
            while i < chars.count {
                let prev = i > 0 ? chars[i - 1] : nil
                if !isVowel(chars[i], previous: prev) { break }
                i += 1
            }
            if i >= chars.count { break }
            // Skip consonants
            while i < chars.count {
                let prev = i > 0 ? chars[i - 1] : nil
                if isVowel(chars[i], previous: prev) { break }
                i += 1
            }
            m += 1
        }
        return m
    }

    private static func hasDoubleConsonant(_ word: String) -> Bool {
        let chars = Array(word)
        guard chars.count >= 2 else { return false }
        let last = chars[chars.count - 1]
        let secondLast = chars[chars.count - 2]
        if last != secondLast { return false }
        let prev = chars.count > 2 ? chars[chars.count - 3] : nil
        return !isVowel(last, previous: prev)
    }

    /// Ends with consonant-vowel-consonant and the last consonant is not w, x, or y.
    private static func endsWithCVC(_ word: String) -> Bool {
        let chars = Array(word)
        guard chars.count >= 3 else { return false }
        let c1 = chars[chars.count - 3]
        let v = chars[chars.count - 2]
        let c2 = chars[chars.count - 1]

        let prevForC1 = chars.count > 3 ? chars[chars.count - 4] : nil
        guard !isVowel(c1, previous: prevForC1) else { return false }
        guard isVowel(v, previous: c1) else { return false }
        guard !isVowel(c2, previous: v) else { return false }
        guard c2 != "w" && c2 != "x" && c2 != "y" else { return false }
        return true
    }
}
