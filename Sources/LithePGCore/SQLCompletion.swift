import Foundation

/// One suggestion in the editor's completion list.
public struct SQLCompletion: Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable {
        case keyword
        case function
        case schema
        case table
        case view
        case column
    }

    public var id: String { "\(kind.rawValue):\(insertText)" }
    /// What replaces the partial word: keywords follow the case being typed, identifiers are
    /// quoted when PostgreSQL would otherwise fold or reject them.
    public let insertText: String
    public let kind: Kind
    /// Extra context shown beside the suggestion, such as a column's type and table.
    public let detail: String?

    public init(insertText: String, kind: Kind, detail: String? = nil) {
        self.insertText = insertText
        self.kind = kind
        self.detail = detail
    }
}

/// What the editor should offer at a caret position.
public struct SQLCompletionResult: Equatable, Sendable {
    /// UTF-16 range of the partial word the chosen suggestion replaces.
    public let replacementRange: NSRange
    public let partial: String
    public let completions: [SQLCompletion]
}

/// Schema-aware SQL completion: keywords, common functions, schemas, tables, views and
/// columns. Columns are scoped to the tables the current statement references, and
/// `alias.` or `table.` narrows the list to that table's columns.
///
/// Built once per loaded schema; `complete(in:at:)` is cheap enough to run on every keystroke.
public final class SQLCompletionIndex: Sendable {
    private struct RelationEntry: Sendable {
        let relation: DatabaseSchema.Relation
        let lowercasedName: String
        let lowercasedSchema: String
    }

    private let relations: [RelationEntry]
    private let schemaNames: [String]

    public init(schema: DatabaseSchema?) {
        let all = schema?.schemas.flatMap(\.relations) ?? []
        relations = all.map {
            RelationEntry(relation: $0, lowercasedName: $0.name.lowercased(), lowercasedSchema: $0.schema.lowercased())
        }
        schemaNames = schema?.schemas.map(\.name) ?? []
    }

    /// True for a single typed character that should open or refresh the list: an identifier
    /// character or the `.` before a column name.
    public static func triggersCompletion(_ typed: String) -> Bool {
        let units = Array(typed.utf16)
        guard units.count == 1 else { return false }
        return units[0] == 0x2E || SQLLexer.isIdentifierUnit(units[0])
    }

    /// Nil when the caret is inside a string, quoted identifier or comment, or when nothing
    /// matches.
    public func complete(in sql: String, at caret: Int) -> SQLCompletionResult? {
        let units = Array(sql.utf16)
        let caret = min(max(caret, 0), units.count)
        guard SQLLexer.isCode(units, at: caret) else { return nil }

        var start = caret
        while start > 0, SQLLexer.isIdentifierUnit(units[start - 1]) { start -= 1 }
        let partial = String(utf16CodeUnits: Array(units[start..<caret]), count: caret - start)
        // Never complete in the middle of a number such as `1.5`.
        if let first = partial.utf16.first, SQLLexer.isDigit(first) { return nil }

        let statement = SQLStatementSplitter.statement(at: caret, in: sql)
        let statementStart = statement?.range.lowerBound ?? 0
        let statementEnd = max(statement?.range.upperBound ?? units.count, caret)
        let tokens = SQLLexer.tokens(Array(units[statementStart..<statementEnd]))
        let references = Self.tableReferences(in: tokens)

        let qualifier = Self.qualifier(units, before: start)
        let candidates: [SQLCompletion]
        if let qualifier {
            candidates = qualifiedCandidates(qualifier: qualifier, references: references)
        } else {
            let previous = Self.previousKeyword(units, before: start, statementStart: statementStart)
            candidates = unqualifiedCandidates(partial: partial, previousKeyword: previous, references: references)
        }

        let needle = partial.lowercased()
        var seen = Set<String>()
        let matches = candidates.filter { completion in
            guard needle.isEmpty || Self.matches(completion, prefix: needle) else { return false }
            return seen.insert(completion.id).inserted
        }
        guard !matches.isEmpty else { return nil }
        // Typing a whole word already leaves nothing to offer.
        if matches.count == 1, matches[0].insertText.lowercased() == needle { return nil }

        return SQLCompletionResult(
            replacementRange: NSRange(location: start, length: caret - start),
            partial: partial,
            completions: Array(matches.prefix(200))
        )
    }

    /// Prefix match ignoring case and quotes. A schema-qualified table also matches on its
    /// own name, so `fa` finds `ventas.facturas`.
    private static func matches(_ completion: SQLCompletion, prefix: String) -> Bool {
        func unquoted(_ text: Substring) -> Substring {
            text.hasPrefix("\"") ? text.dropFirst() : text
        }
        let key = completion.insertText.lowercased()
        if unquoted(Substring(key)).hasPrefix(prefix) { return true }
        guard completion.kind == .table || completion.kind == .view,
            let dot = key.lastIndex(of: ".")
        else { return false }
        return unquoted(key[key.index(after: dot)...]).hasPrefix(prefix)
    }

    // MARK: - Candidates

    private func qualifiedCandidates(qualifier: String, references: [TableReference]) -> [SQLCompletion] {
        let lowered = qualifier.lowercased()
        var results: [SQLCompletion] = []

        // An alias or table name from this statement: that table's columns.
        let referenced = references.filter { $0.alias?.lowercased() == lowered || $0.name.lowercased() == lowered }
        for reference in referenced {
            for relation in resolve(reference) {
                results += relation.columns.map { columnCompletion($0, in: relation, showTable: false) }
            }
        }
        // Any table in the schema, even one not named in FROM yet.
        if results.isEmpty {
            for entry in relations where entry.lowercasedName == lowered {
                results += entry.relation.columns.map { columnCompletion($0, in: entry.relation, showTable: false) }
            }
        }
        // A schema name: its tables and views.
        for entry in relations where entry.lowercasedSchema == lowered {
            results.append(relationCompletion(entry.relation, qualified: false))
        }
        return results
    }

    private func unqualifiedCandidates(
        partial: String, previousKeyword: String?, references: [TableReference]
    ) -> [SQLCompletion] {
        let keywords = Self.keywordCompletions(matchingCaseOf: partial)
        let functions = Self.functionCompletions(matchingCaseOf: partial)
        let tables = relationCandidates()
        let columns = references.flatMap { reference in
            resolve(reference).flatMap { relation in
                relation.columns.map { columnCompletion($0, in: relation, showTable: references.count > 1) }
            }
        }
        let schemas = schemaNames.map {
            SQLCompletion(insertText: SQLLexer.quoteIfNeeded($0), kind: .schema, detail: "schema")
        }

        switch previousKeyword {
        case "from", "join", "into", "update", "table", "truncate":
            return tables + schemas + keywords
        case "select", "where", "and", "or", "on", "by", "set", "having", "distinct", "when",
            "then", "else", "returning", "not", "in", "like", "ilike", "is":
            return columns + functions + keywords + tables
        default:
            return keywords + columns + tables + functions + schemas
        }
    }

    private func relationCandidates() -> [SQLCompletion] {
        // Tables outside `public` are offered schema-qualified so the inserted SQL resolves.
        relations.map { relationCompletion($0.relation, qualified: $0.lowercasedSchema != "public") }
    }

    private func relationCompletion(_ relation: DatabaseSchema.Relation, qualified: Bool) -> SQLCompletion {
        let name = SQLLexer.quoteIfNeeded(relation.name)
        let text = qualified ? "\(SQLLexer.quoteIfNeeded(relation.schema)).\(name)" : name
        return SQLCompletion(
            insertText: text,
            kind: relation.kind == .view ? .view : .table,
            detail: "\(relation.kind == .view ? "view" : "table") · \(relation.schema)"
        )
    }

    private func columnCompletion(
        _ column: DatabaseSchema.Column, in relation: DatabaseSchema.Relation, showTable: Bool
    ) -> SQLCompletion {
        var detail = column.typeName
        if column.isPrimaryKey { detail += " · primary key" }
        if showTable { detail += " · \(relation.name)" }
        return SQLCompletion(insertText: SQLLexer.quoteIfNeeded(column.name), kind: .column, detail: detail)
    }

    private func resolve(_ reference: TableReference) -> [DatabaseSchema.Relation] {
        let name = reference.name.lowercased()
        let schema = reference.schema?.lowercased()
        return relations.filter { entry in
            entry.lowercasedName == name && (schema == nil || entry.lowercasedSchema == schema)
        }.map(\.relation)
    }

    // MARK: - Statement analysis

    struct TableReference: Equatable {
        let schema: String?
        let name: String
        let alias: String?
    }

    /// Tables named after FROM, JOIN, UPDATE and INTO, with their aliases. FROM lists may be
    /// comma separated.
    static func tableReferences(in tokens: [SQLLexer.Token]) -> [TableReference] {
        var references: [TableReference] = []
        var index = 0
        while index < tokens.count {
            guard case .word(let word) = tokens[index],
                ["from", "join", "update", "into"].contains(word.lowercased())
            else {
                index += 1
                continue
            }
            let allowsList = word.lowercased() == "from"
            index += 1
            while index < tokens.count {
                guard let (reference, next) = parseTableReference(tokens, at: index) else { break }
                references.append(reference)
                index = next
                guard allowsList, index < tokens.count, tokens[index] == .comma else { break }
                index += 1
            }
        }
        return references
    }

    private static func parseTableReference(_ tokens: [SQLLexer.Token], at start: Int) -> (TableReference, Int)? {
        var index = start
        guard index < tokens.count, let first = tokens[index].identifier,
            !SQLLexer.reservedAfterTable.contains(first.lowercased()) || tokens[index].isQuoted
        else { return nil }
        index += 1
        var schema: String?
        var name = first
        if index + 1 < tokens.count, tokens[index] == .dot, let second = tokens[index + 1].identifier {
            schema = first
            name = second
            index += 2
        }
        var alias: String?
        if index < tokens.count, case .word(let word) = tokens[index], word.lowercased() == "as" {
            index += 1
        }
        if index < tokens.count, let candidate = tokens[index].identifier,
            tokens[index].isQuoted || !SQLLexer.reservedAfterTable.contains(candidate.lowercased())
        {
            alias = candidate
            index += 1
        }
        return (TableReference(schema: schema, name: name, alias: alias), index)
    }

    /// `p` for a caret after `p.` or `p.na`.
    private static func qualifier(_ units: [UInt16], before start: Int) -> String? {
        guard start > 0, units[start - 1] == 0x2E else { return nil }
        let end = start - 1
        if end > 0, units[end - 1] == 0x22 {
            // A quoted qualifier: "Order".
            var open = end - 1
            while open > 0, units[open - 1] != 0x22 { open -= 1 }
            guard open > 0 else { return nil }
            return String(utf16CodeUnits: Array(units[open..<(end - 1)]), count: end - 1 - open)
        }
        var begin = end
        while begin > 0, SQLLexer.isIdentifierUnit(units[begin - 1]) { begin -= 1 }
        guard begin < end else { return nil }
        return String(utf16CodeUnits: Array(units[begin..<end]), count: end - begin)
    }

    /// The nearest keyword before the partial word that decides what kind of name fits,
    /// skipping commas, identifiers and punctuation in between.
    private static func previousKeyword(_ units: [UInt16], before start: Int, statementStart: Int) -> String? {
        let lower = min(statementStart, start)
        let tokens = SQLLexer.tokens(Array(units[lower..<start]))
        for token in tokens.reversed() {
            guard case .word(let word) = token else { continue }
            let lowered = word.lowercased()
            if contextKeywords.contains(lowered) { return lowered }
        }
        return nil
    }

    private static let contextKeywords: Set<String> = [
        "select", "from", "join", "into", "update", "table", "truncate", "where", "and", "or",
        "on", "by", "set", "having", "distinct", "when", "then", "else", "returning", "not",
        "in", "like", "ilike", "is", "values", "limit", "offset",
    ]

    // MARK: - Vocabulary

    static let keywords: [String] = [
        "SELECT", "FROM", "WHERE", "AND", "OR", "NOT", "NULL", "IS", "IN", "LIKE", "ILIKE",
        "BETWEEN", "EXISTS", "AS", "DISTINCT", "ORDER BY", "GROUP BY", "HAVING", "LIMIT",
        "OFFSET", "JOIN", "INNER JOIN", "LEFT JOIN", "RIGHT JOIN", "FULL JOIN", "CROSS JOIN",
        "ON", "USING", "UNION", "UNION ALL", "INTERSECT", "EXCEPT", "WITH", "RECURSIVE",
        "CASE", "WHEN", "THEN", "ELSE", "END", "ASC", "DESC", "NULLS FIRST", "NULLS LAST",
        "INSERT INTO", "VALUES", "UPDATE", "SET", "DELETE FROM", "RETURNING", "ON CONFLICT",
        "DO NOTHING", "DO UPDATE", "CREATE TABLE", "CREATE INDEX", "CREATE VIEW", "ALTER TABLE",
        "DROP TABLE", "TRUNCATE", "ADD COLUMN", "PRIMARY KEY", "FOREIGN KEY", "REFERENCES",
        "DEFAULT", "UNIQUE", "CHECK", "CONSTRAINT", "BEGIN", "COMMIT", "ROLLBACK", "EXPLAIN",
        "ANALYZE", "TRUE", "FALSE", "OVER", "PARTITION BY", "WINDOW", "FILTER", "LATERAL",
        "CAST", "INTERVAL", "CURRENT_DATE", "CURRENT_TIMESTAMP",
    ]

    static let functions: [String] = [
        "count", "sum", "avg", "min", "max", "coalesce", "nullif", "now", "date_trunc",
        "extract", "lower", "upper", "length", "trim", "substring", "concat", "string_agg",
        "array_agg", "json_agg", "jsonb_agg", "jsonb_build_object", "to_char", "round",
        "abs", "greatest", "least", "row_number", "rank", "dense_rank", "lag", "lead",
        "generate_series", "gen_random_uuid",
    ]

    /// Keywords follow what is being typed: `sel` offers `select`, `Sel` and `SEL` offer `SELECT`.
    static func keywordCompletions(matchingCaseOf partial: String) -> [SQLCompletion] {
        let lower = partial.first.map { $0.isLowercase } ?? false
        return keywords.map {
            SQLCompletion(insertText: lower ? $0.lowercased() : $0, kind: .keyword)
        }
    }

    static func functionCompletions(matchingCaseOf partial: String) -> [SQLCompletion] {
        let upper = partial.count > 1 && partial == partial.uppercased() && partial != partial.lowercased()
        return functions.map {
            SQLCompletion(insertText: upper ? $0.uppercased() : $0, kind: .function, detail: "function")
        }
    }
}

/// A small SQL scanner shared by completion: where code is, and a token stream for one
/// statement. It mirrors the quoting rules in `SQLStatementSplitter`.
enum SQLLexer {
    enum Token: Equatable {
        case word(String)
        case quoted(String)
        case dot
        case comma
        case other

        var identifier: String? {
            switch self {
            case .word(let value), .quoted(let value): value
            default: nil
            }
        }

        var isQuoted: Bool {
            if case .quoted = self { return true }
            return false
        }
    }

    /// Words that end a table reference instead of naming an alias.
    static let reservedAfterTable: Set<String> = [
        "where", "join", "inner", "left", "right", "full", "cross", "outer", "on", "using",
        "group", "order", "limit", "offset", "having", "union", "intersect", "except", "set",
        "values", "returning", "natural", "lateral", "window", "for", "select", "default",
        "as", "fetch", "tablesample", "do",
    ]

    static func tokens(_ units: [UInt16]) -> [Token] {
        var tokens: [Token] = []
        var index = 0
        while index < units.count {
            let unit = units[index]
            let next = index + 1 < units.count ? units[index + 1] : nil
            if unit == 0x2D, next == 0x2D {  // --
                while index < units.count, units[index] != 0x0A { index += 1 }
            } else if unit == 0x2F, next == 0x2A {  // /*
                index = skipBlockComment(units, from: index)
            } else if unit == 0x27 {  // '
                index = skipQuoted(units, from: index, quote: 0x27)
                tokens.append(.other)
            } else if unit == 0x22 {  // "
                let end = skipQuoted(units, from: index, quote: 0x22)
                let inner = Array(units[(index + 1)..<max(index + 1, end - 1)])
                let text = String(utf16CodeUnits: inner, count: inner.count)
                    .replacingOccurrences(of: "\"\"", with: "\"")
                tokens.append(.quoted(text))
                index = end
            } else if isIdentifierStart(unit) {
                var end = index
                while end < units.count, isIdentifierUnit(units[end]) { end += 1 }
                tokens.append(.word(String(utf16CodeUnits: Array(units[index..<end]), count: end - index)))
                index = end
            } else if unit == 0x2E {
                tokens.append(.dot)
                index += 1
            } else if unit == 0x2C {
                tokens.append(.comma)
                index += 1
            } else if isWhitespace(unit) {
                index += 1
            } else {
                tokens.append(.other)
                index += 1
            }
        }
        return tokens
    }

    /// False inside a string, quoted identifier or comment.
    static func isCode(_ units: [UInt16], at caret: Int) -> Bool {
        var index = 0
        while index < caret {
            let unit = units[index]
            let next = index + 1 < units.count ? units[index + 1] : nil
            let end: Int
            if unit == 0x2D, next == 0x2D {
                var lineEnd = index
                while lineEnd < units.count, units[lineEnd] != 0x0A { lineEnd += 1 }
                end = lineEnd
            } else if unit == 0x2F, next == 0x2A {
                end = skipBlockComment(units, from: index)
            } else if unit == 0x27 || unit == 0x22 {
                end = skipQuoted(units, from: index, quote: unit)
            } else {
                index += 1
                continue
            }
            // The caret sits inside this construct unless it closed before the caret.
            if end > caret || (end == caret && !closes(units, end: end, opener: unit)) { return false }
            index = end
        }
        return true
    }

    private static func closes(_ units: [UInt16], end: Int, opener: UInt16) -> Bool {
        guard end > 0 else { return false }
        switch opener {
        case 0x27, 0x22: return units[end - 1] == opener
        case 0x2D: return false  // a line comment runs to the caret
        default: return end >= 2 && units[end - 2] == 0x2A && units[end - 1] == 0x2F
        }
    }

    private static func skipBlockComment(_ units: [UInt16], from start: Int) -> Int {
        var depth = 1
        var index = start + 2
        while index < units.count, depth > 0 {
            let next = index + 1 < units.count ? units[index + 1] : nil
            if units[index] == 0x2F, next == 0x2A {
                depth += 1
                index += 2
            } else if units[index] == 0x2A, next == 0x2F {
                depth -= 1
                index += 2
            } else {
                index += 1
            }
        }
        return index
    }

    private static func skipQuoted(_ units: [UInt16], from start: Int, quote: UInt16) -> Int {
        var index = start + 1
        while index < units.count {
            if units[index] == quote {
                if index + 1 < units.count, units[index + 1] == quote {
                    index += 2
                    continue
                }
                return index + 1
            }
            index += 1
        }
        return units.count
    }

    /// Wraps an identifier in double quotes when PostgreSQL would fold its case, reject its
    /// characters or read it as a keyword.
    static func quoteIfNeeded(_ identifier: String) -> String {
        let units = Array(identifier.utf16)
        let plain = !units.isEmpty
            && isIdentifierStart(units[0])
            && units.allSatisfy { isIdentifierUnit($0) && !(0x41...0x5A).contains($0) }
            && !quotedKeywords.contains(identifier)
        if plain { return identifier }
        return "\"\(identifier.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    /// Reserved words that cannot be used as bare column or table names.
    private static let quotedKeywords: Set<String> = [
        "all", "analyse", "analyze", "and", "any", "array", "as", "asc", "asymmetric", "both",
        "case", "cast", "check", "collate", "column", "constraint", "create", "current_date",
        "current_role", "current_time", "current_timestamp", "current_user", "default",
        "deferrable", "desc", "distinct", "do", "else", "end", "except", "false", "fetch",
        "for", "foreign", "from", "grant", "group", "having", "in", "initially", "intersect",
        "into", "lateral", "leading", "limit", "localtime", "localtimestamp", "not", "null",
        "offset", "on", "only", "or", "order", "placing", "primary", "references", "returning",
        "select", "session_user", "some", "symmetric", "table", "then", "to", "trailing",
        "true", "union", "unique", "user", "using", "variadic", "when", "where", "window", "with",
    ]

    static func isIdentifierStart(_ unit: UInt16) -> Bool {
        (unit >= 0x41 && unit <= 0x5A) || (unit >= 0x61 && unit <= 0x7A) || unit == 0x5F || unit >= 0x80
    }

    static func isIdentifierUnit(_ unit: UInt16) -> Bool {
        isIdentifierStart(unit) || isDigit(unit) || unit == 0x24
    }

    static func isDigit(_ unit: UInt16) -> Bool {
        unit >= 0x30 && unit <= 0x39
    }

    private static func isWhitespace(_ unit: UInt16) -> Bool {
        unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D || unit == 0x0C
    }
}
