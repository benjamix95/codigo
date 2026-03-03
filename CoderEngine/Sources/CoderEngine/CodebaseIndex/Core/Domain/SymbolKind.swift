import Foundation

// MARK: - SymbolKind

/// Tipo di simbolo estratto dal codice sorgente
public enum SymbolKind: String, Sendable, Codable, CaseIterable {
    case `class`
    case `struct`
    case `enum`
    case `protocol`
    case `extension`
    case function
    case method
    case property
    case constant
    case variable
    case typeAlias
    case `import`
    case macro
    case interface
    case trait
    case module
    case test
    case unknown

    /// Icona SF Symbol per UI
    public var sfSymbol: String {
        switch self {
        case .class: return "c.square"
        case .struct: return "s.square"
        case .enum: return "e.square"
        case .protocol: return "p.square"
        case .extension: return "plus.square"
        case .function, .method: return "f.square"
        case .property, .variable: return "v.square"
        case .constant: return "k.square"
        case .typeAlias: return "t.square"
        case .import: return "arrow.down.square"
        case .macro: return "m.square"
        case .interface: return "i.square"
        case .trait: return "t.square"
        case .module: return "shippingbox"
        case .test: return "checkmark.square"
        case .unknown: return "questionmark.square"
        }
    }

    /// true se è un tipo (class, struct, enum, protocol, interface, trait)
    public var isType: Bool {
        switch self {
        case .class, .struct, .enum, .protocol, .interface, .trait, .typeAlias:
            return true
        default:
            return false
        }
    }

    /// true se è una callable (function, method)
    public var isCallable: Bool {
        self == .function || self == .method || self == .test
    }

    /// true se è una dichiarazione di dato (property, variable, constant)
    public var isDataDeclaration: Bool {
        self == .property || self == .variable || self == .constant
    }
}
