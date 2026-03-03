import Foundation

// MARK: - SemanticIndex Lexicon

extension SemanticIndex {
    static let stopWords: Set<String> = [
        // English noise words
        "the", "is", "at", "in", "of", "to", "for", "and", "or", "not",
        "this", "that", "it", "a", "an", "be", "has", "was", "are",
        "been", "do", "did", "does", "will", "with", "from", "by", "on",

        // Very frequent code tokens that are rarely useful intent signals
        "var", "let", "val", "const", "public", "private", "internal",
        "static", "void", "int", "bool", "import", "return",
        "async", "await",
    ]

    static let synonymMap: [String: [String]] = [
        // Authentication & Security
        "auth": ["authentication", "login", "signin", "credential"],
        "authentication": ["auth", "login", "signin"],
        "authorize": ["auth", "authentication", "permission"],
        "authorization": ["auth", "authorize", "permission"],
        "login": ["auth", "signin", "authenticate"],
        "signin": ["login", "auth", "authenticate"],
        "signup": ["register", "createaccount", "onboard"],
        "register": ["signup", "enroll", "createaccount"],
        "logout": ["signout", "deauthenticate", "session"],
        "password": ["credential", "secret", "passphrase"],
        "token": ["jwt", "session", "credential", "bearer"],
        "session": ["token", "cookie", "auth"],
        "permission": ["role", "access", "authorize", "acl"],
        "encrypt": ["cipher", "hash", "secure", "protect"],
        "decrypt": ["decipher", "decode", "unlock"],

        // Data Persistence
        "save": ["persist", "store", "write", "serialize"],
        "persist": ["save", "store", "write"],
        "load": ["fetch", "read", "deserialize", "parse"],
        "fetch": ["load", "get", "retrieve", "request"],
        "read": ["load", "get", "fetch", "parse"],
        "write": ["save", "persist", "store", "output"],
        "serialize": ["encode", "marshal", "stringify"],
        "deserialize": ["decode", "unmarshal", "parse"],
        "database": ["db", "storage", "persistence", "repository"],
        "db": ["database", "storage", "datastore"],
        "query": ["search", "find", "filter", "select"],
        "migration": ["schema", "upgrade", "evolve"],
        "transaction": ["commit", "rollback", "atomic"],

        // CRUD Operations
        "create": ["insert", "add", "new", "make"],
        "update": ["modify", "edit", "patch", "change"],
        "delete": ["remove", "destroy", "cleanup", "purge"],
        "remove": ["delete", "destroy", "cleanup"],
        "insert": ["add", "create", "append", "push"],
        "find": ["search", "query", "lookup", "locate"],
        "search": ["find", "query", "filter", "grep"],
        "filter": ["where", "predicate", "search", "select"],
        "sort": ["order", "rank", "arrange", "compare"],

        // Error Handling
        "error": ["exception", "failure", "fault", "crash"],
        "exception": ["error", "failure", "throw"],
        "crash": ["abort", "fatal", "panic", "terminate"],
        "retry": ["attempt", "recover", "backoff"],
        "fallback": ["default", "recover", "alternative"],
        "throw": ["raise", "emit", "error"],
        "catch": ["handle", "recover", "rescue"],
        "log": ["print", "debug", "trace", "output"],
        "debug": ["log", "trace", "inspect", "diagnose"],

        // Architecture & Patterns
        "handle": ["manage", "process", "dispatch"],
        "handler": ["controller", "manager", "processor"],
        "controller": ["handler", "presenter", "coordinator"],
        "service": ["provider", "manager", "helper"],
        "repository": ["store", "dao", "gateway", "datasource"],
        "factory": ["builder", "creator", "constructor"],
        "observer": ["listener", "subscriber", "watcher"],
        "delegate": ["callback", "handler", "protocol"],
        "middleware": ["interceptor", "filter", "plugin"],
        "singleton": ["shared", "instance", "global"],
        "protocol": ["interface", "contract", "trait"],
        "extension": ["category", "mixin", "augment"],

        // Configuration
        "config": ["configuration", "settings", "preferences"],
        "configuration": ["config", "settings", "options"],
        "environment": ["env", "config", "context"],
        "env": ["environment", "config", "variable"],

        // Testing
        "test": ["spec", "assert", "expect", "verify"],
        "mock": ["stub", "fake", "double", "spy"],
        "fixture": ["testdata", "sample", "seed"],
        "assert": ["expect", "verify", "check"],

        // Networking
        "network": ["http", "api", "request", "response"],
        "api": ["endpoint", "route", "network", "rest"],
        "request": ["call", "invoke", "fetch", "http"],
        "response": ["reply", "result", "output"],
        "websocket": ["socket", "realtime", "stream"],
        "upload": ["send", "transmit", "push"],
        "download": ["fetch", "pull", "receive"],
        "url": ["link", "endpoint", "uri", "path"],

        // UI & Presentation
        "view": ["screen", "page", "component", "layout"],
        "render": ["display", "draw", "show", "present"],
        "layout": ["arrange", "position", "frame", "stack"],
        "animate": ["transition", "motion", "effect"],
        "modal": ["dialog", "sheet", "popup", "alert"],
        "button": ["action", "tap", "control", "trigger"],
        "click": ["tap", "press", "trigger", "activate"],
        "input": ["field", "textfield", "form", "entry"],
        "list": ["table", "collection", "grid", "array"],
        "image": ["photo", "icon", "asset", "picture"],
        "color": ["theme", "palette", "tint", "style"],
        "font": ["typography", "text", "typeface"],

        // Data Modeling
        "data": ["model", "entity", "schema", "record"],
        "model": ["data", "entity", "schema", "struct"],
        "entity": ["model", "object", "record", "row"],
        "schema": ["model", "structure", "definition"],
        "enum": ["type", "case", "variant", "option"],

        // Navigation
        "navigate": ["route", "redirect", "go", "push"],
        "route": ["navigate", "path", "endpoint", "url"],
        "push": ["navigate", "present", "show"],
        "pop": ["dismiss", "back", "close"],
        "tab": ["segment", "page", "section"],

        // Caching & Performance
        "cache": ["memo", "memoize", "buffer", "store"],
        "validate": ["check", "verify", "assert", "ensure"],
        "optimize": ["performance", "speed", "improve"],
        "lazy": ["deferred", "ondemand", "delayed"],
        "async": ["concurrent", "parallel", "await"],
        "sync": ["synchronous", "blocking", "serial"],
        "queue": ["dispatch", "channel", "buffer"],
        "thread": ["concurrent", "parallel", "worker"],

        // User & Account
        "user": ["account", "profile", "member"],
        "submit": ["send", "post", "confirm", "complete"],
        "notification": ["alert", "push", "message", "toast"],
        "email": ["mail", "message", "send"],
        "file": ["document", "resource", "asset"],
        "settings": ["preferences", "config", "options"],
        "onboard": ["welcome", "setup", "tutorial"],
    ]
}
