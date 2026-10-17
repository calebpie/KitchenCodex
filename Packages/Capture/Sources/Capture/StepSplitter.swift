import Foundation

/// Splits a block of method text into steps for manual entry.
///
/// When the text has blank lines, each paragraph is a step and single line breaks inside it are
/// joined (so a hard-wrapped paste stays one step). Without blank lines, each line is a step.
/// Leading "1.", "2)" or "Step 3:" numbering is dropped; the app numbers steps itself.
public enum StepSplitter {
    public static func steps(from text: String) -> [String] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let hasParagraphs = normalized.range(of: #"\n[ \t]*\n"#, options: .regularExpression) != nil

        let chunks: [String]
        if hasParagraphs {
            chunks = normalized
                .components(separatedBy: "\n")
                .reduce(into: [[String]]([[]])) { paragraphs, line in
                    if line.trimmingCharacters(in: .whitespaces).isEmpty {
                        if paragraphs.last?.isEmpty == false { paragraphs.append([]) }
                    } else {
                        paragraphs[paragraphs.count - 1].append(line.trimmingCharacters(in: .whitespaces))
                    }
                }
                .map { $0.joined(separator: " ") }
        } else {
            chunks = normalized.components(separatedBy: "\n")
        }

        return chunks
            .map { stripNumber($0.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.isEmpty }
    }

    private static func stripNumber(_ step: String) -> String {
        guard let range = step.range(of: #"^(step\s*)?\d+\s*([.)]\s+|:\s*)"#, options: [.regularExpression, .caseInsensitive]) else {
            return step
        }
        return String(step[range.upperBound...])
    }
}
