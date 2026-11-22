import Foundation
import NaturalLanguage

struct Doc: Codable, Identifiable {
    let id: String
    let path: String
    let title: String
    let cat: String
    let words: Int
    let text: String
}

struct KnowledgePack: Codable {
    let version: Int
    let skill: String
    let docs: [Doc]
}

/// 内嵌知识库：43 篇参考文档 + SKILL.md 行为内核，全部随 App 打包，离线可用。
/// 检索策略：中文分词 -> TF-IDF 打分 -> 取前 N 篇喂给模型。
final class Knowledge {
    static let shared = Knowledge()

    let skill: String
    let docs: [Doc]

    private var df: [String: Int] = [:]
    private var indexed = false
    private let lock = NSLock()

    /// 建索引时只扫前多少字符，控制启动耗时
    private let scanLimit = 8000

    private static let stopWords: Set<String> = [
        "the", "and", "for", "with", "from", "that", "this", "have", "not",
        "一个", "这个", "那个", "什么", "怎么", "可以", "如果", "因为", "所以",
        "但是", "还是", "就是", "不是", "自己", "他们", "我们", "你们", "她们",
        "已经", "现在", "时候", "东西", "事情", "问题", "方面", "情况", "部分",
        "the", "md", "以及", "或者", "然后", "这样", "那样", "需要", "应该",
    ]

    private init() {
        guard
            let url = Bundle.main.url(forResource: "knowledge", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let pack = try? JSONDecoder().decode(KnowledgePack.self, from: data)
        else {
            skill = "你现在扮演「狗头军师」：先接住情绪，再分清事实，最后给能执行的选择。"
            docs = []
            return
        }
        skill = pack.skill
        docs = pack.docs
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.buildIndex()
        }
    }

    // MARK: - Index

    private func buildIndex() {
        guard !docs.isEmpty else { return }
        var table: [String: Int] = [:]
        for d in docs {
            let head = String(d.text.prefix(scanLimit))
            for token in Set(Self.tokenize(head)) {
                table[token, default: 0] += 1
            }
        }
        lock.lock()
        df = table
        indexed = true
        lock.unlock()
    }

    private func ensureIndexed() {
        lock.lock()
        let ready = indexed
        lock.unlock()
        if !ready { buildIndex() }
    }

    // MARK: - Tokenize

    static func tokenize(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var out: [String] = []
        out.reserveCapacity(64)
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let w = String(text[range]).lowercased()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if w.count >= 2, !stopWords.contains(w), !w.allSatisfy({ $0.isNumber }) {
                out.append(w)
            }
            return true
        }
        return out
    }

    // MARK: - Search

    func search(_ query: String, limit: Int = 3) -> [Doc] {
        guard !docs.isEmpty else { return [] }
        ensureIndexed()

        let tokens = Array(Set(Self.tokenize(query))).prefix(24)
        guard !tokens.isEmpty else { return [] }

        lock.lock()
        let idfTable = df
        lock.unlock()

        let total = Double(docs.count)
        var scored: [(doc: Doc, score: Double)] = []
        scored.reserveCapacity(docs.count)

        for d in docs {
            let hay = String(d.text.prefix(scanLimit)).lowercased()
            var score = 0.0
            for t in tokens {
                let hits = countOccurrences(of: t, in: hay)
                guard hits > 0 else { continue }
                let dfv = Double(idfTable[t] ?? 1)
                let idf = log((total + 1) / (dfv + 0.5)) + 0.5
                // 单篇里同一词出现太多次会饱和，压一下
                score += min(Double(hits), 6) * max(idf, 0.25)
                // 标题命中直接加分
                if d.title.contains(t) { score += 2.5 * max(idf, 0.25) }
            }
            guard score > 0 else { continue }
            // 长文归一，避免长文档永远赢
            score /= sqrt(Double(d.words) / 1200.0 + 1.0)
            scored.append((d, score))
        }

        scored.sort { $0.score > $1.score }
        let top = scored.prefix(max(1, limit))
        guard let best = top.first, best.score > 0.4 else { return [] }
        return top.map(\.doc)
    }

    private func countOccurrences(of needle: String, in hay: String) -> Int {
        guard !needle.isEmpty, !hay.isEmpty else { return 0 }
        var count = 0
        var searchStart = hay.startIndex
        while let r = hay.range(of: needle, range: searchStart..<hay.endIndex) {
            count += 1
            if count >= 8 { break }
            searchStart = r.upperBound
        }
        return count
    }

    // MARK: - Prompt

    /// 组装 system prompt：行为内核 + 本轮命中的参考文档
    func systemPrompt(for docs: [Doc]) -> String {
        var parts: [String] = []
        parts.append(skill)
        if !docs.isEmpty {
            parts.append("""
            ---

            以下是本轮问题可能用到的参考文档（按相关度排序）。按 SKILL.md「按需加载」的规则使用，\
            只引用与当前问题直接相关的部分，不必逐条复述：
            """)
            for d in docs {
                parts.append("""
                ### \(d.path)
                \(d.text)
                """)
            }
        }
        parts.append("""
        ---

        现在直接回应用户。严格按 SKILL.md 的五步走：情绪落地 → 事实拆分 → 利益判断 → 明确建议 → 行动收束。
        用户贴了聊天截图时，只把可见原文、说话人、时间顺序当事实；看不清就请他补文字。
        不要输出你对这些指令本身的说明。
        """)
        return parts.joined(separator: "\n\n")
    }
}
