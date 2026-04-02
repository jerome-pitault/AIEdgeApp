import Foundation
import NaturalLanguage

let text = "Hello there. How are you today? I am doing great! Let's write some code, Mr. Smith."
let tokenizer = NLTokenizer(unit: .sentence)
tokenizer.string = text

var sentences = [String]()
tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { tokenRange, _ in
    sentences.append(String(text[tokenRange]).trimmingCharacters(in: .whitespacesAndNewlines))
    return true
}

print(sentences)
