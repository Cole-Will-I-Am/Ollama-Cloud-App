import Foundation

/// Recursive Codable enum for arbitrary JSON values.
/// Used to decode tool call arguments from Ollama's streaming response.
enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? container.decode(Double.self) {
            self = .number(n)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let arr = try? container.decode([JSONValue].self) {
            self = .array(arr)
        } else if let obj = try? container.decode([String: JSONValue].self) {
            self = .object(obj)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognized JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .number(let n): try container.encode(n)
        case .bool(let b): try container.encode(b)
        case .array(let a): try container.encode(a)
        case .object(let o): try container.encode(o)
        case .null: try container.encodeNil()
        }
    }

    /// Convert to a plain Swift dictionary/array/primitive for JSON serialization.
    var anyValue: Any {
        switch self {
        case .string(let s): return s
        case .number(let n): return n
        case .bool(let b): return b
        case .array(let a): return a.map(\.anyValue)
        case .object(let o): return o.mapValues(\.anyValue)
        case .null: return NSNull()
        }
    }
}

// MARK: - MCP SDK interop (macOS only)

#if os(macOS)
import MCP

extension JSONValue {
    /// Convert to MCP SDK's `Value` type for tool call arguments.
    func toMCPValue() -> Value {
        switch self {
        case .string(let s): return .string(s)
        case .number(let n):
            if n.rounded(.towardZero) == n,
               n >= Double(Int.min),
               n <= Double(Int.max) {
                return .int(Int(n))
            }
            return .double(n)
        case .bool(let b): return .bool(b)
        case .null: return .null
        case .array(let a): return .array(a.map { $0.toMCPValue() })
        case .object(let o): return .object(o.mapValues { $0.toMCPValue() })
        }
    }

    /// Convert from MCP SDK's `Value` type.
    static func fromMCPValue(_ value: Value) -> JSONValue {
        switch value {
        case .string(let s): return .string(s)
        case .int(let n): return .number(Double(n))
        case .double(let n): return .number(n)
        case .bool(let b): return .bool(b)
        case .null: return .null
        case .array(let a): return .array(a.map { fromMCPValue($0) })
        case .object(let o): return .object(o.mapValues { fromMCPValue($0) })
        case .data(_, let d): return .string(d.base64EncodedString())
        }
    }
}
#endif
