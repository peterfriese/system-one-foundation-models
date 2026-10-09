import Foundation
import FoundationModels

/// Describes the expected primitive kind of a schema property.
public enum SchemaPropertyKind: Sendable, Equatable {
    case boolean
    case choice(options: [String])
    case score(minimum: Double, maximum: Double, isInteger: Bool)
    case nested([String: SchemaPropertyDescriptor])
}

/// Metadata describing a single field within a `@Generable` schema.
public struct SchemaPropertyDescriptor: Sendable, Equatable {
    public let name: String
    public let questionKey: String
    public let kind: SchemaPropertyKind
    public let instructions: String
    public let isRequired: Bool

    public init(
        name: String,
        questionKey: String,
        kind: SchemaPropertyKind,
        instructions: String,
        isRequired: Bool = true
    ) {
        self.name = name
        self.questionKey = questionKey
        self.kind = kind
        self.instructions = instructions
        self.isRequired = isRequired
    }
}

/// The decoded root structural layout of a `@Generable` schema.
public enum SchemaRootLayout: Sendable, Equatable {
    case object(properties: [String: SchemaPropertyDescriptor], propertyOrder: [String])
    case choice(options: [String], questionKey: String)
    case boolean(questionKey: String)
    case score(minimum: Double, maximum: Double, isInteger: Bool, questionKey: String)
}

/// The result of translating an Apple `GenerationSchema` into System One questions and decoding layout.
public struct SchemaTranslation: Sendable, Equatable {
    public let layout: SchemaRootLayout
    public let questions: [String: SystemOneQuestion]

    public init(layout: SchemaRootLayout, questions: [String: SystemOneQuestion]) {
        self.layout = layout
        self.questions = questions
    }
}

/// Translates Apple Foundation Models `GenerationSchema` instances into System One decision questions.
public struct SchemaTranslator: Sendable {
    public init() {}

    /// Translates a `GenerationSchema` into a `SchemaTranslation` containing System One questions and structural layout.
    public func translate(_ schema: GenerationSchema) throws -> SchemaTranslation {
        let schemaData: Data
        do {
            schemaData = try JSONEncoder().encode(schema)
        } catch {
            throw SystemOneError.invalidSchema("Failed to encode GenerationSchema to JSON: \(error.localizedDescription)")
        }

        guard let jsonObject = try? JSONSerialization.jsonObject(with: schemaData) as? [String: Any] else {
            throw SystemOneError.invalidSchema("GenerationSchema JSON representation is not a valid dictionary.")
        }

        return try translate(json: jsonObject)
    }

    /// Translates raw schema JSON dictionary for package callers, tests, and custom schema representations.
    package func translate(json: [String: Any]) throws -> SchemaTranslation {
        let defs = json["$defs"] as? [String: [String: Any]] ?? [:]
        return try parseRoot(json: json, defs: defs)
    }

    /// Translates a `GenerationSchema` directly to a System One questions dictionary.
    @available(*, deprecated, message: "Use translate(_:) to obtain the full SchemaTranslation")
    public func translateToQuestions(_ schema: GenerationSchema) throws -> [String: SystemOneQuestion] {
        try translate(schema).questions
    }

    // MARK: - Internal Parsing

    private func parseRoot(json: [String: Any], defs: [String: [String: Any]]) throws -> SchemaTranslation {
        let rawType = json["type"] as? String
        let title = json["title"] as? String ?? "Decision"
        let description = json["description"] as? String

        // Case 1: Root is a discrete categorical enum (type == "string" with enum choices)
        if rawType == "string", let enumCases = json["enum"] as? [String], !enumCases.isEmpty {
            let questionKey = "choice"
            let instructions = description ?? title
            var criteria: [String: String] = [:]
            for c in enumCases {
                criteria[c] = c
            }
            let question = SystemOneQuestion.choice(instructions: instructions, criteria: criteria)
            return SchemaTranslation(
                layout: .choice(options: enumCases, questionKey: questionKey),
                questions: [questionKey: question]
            )
        }

        // Case 2: Root is a single Boolean
        if rawType == "boolean" {
            let questionKey = "root"
            let instructions = description ?? title
            let question = SystemOneQuestion.noul(instructions: instructions)
            return SchemaTranslation(
                layout: .boolean(questionKey: questionKey),
                questions: [questionKey: question]
            )
        }

        // Case 3: Root is a scored range
        if (rawType == "integer" || rawType == "number"),
           let min = (json["minimum"] as? NSNumber)?.doubleValue,
           let max = (json["maximum"] as? NSNumber)?.doubleValue {
            let questionKey = "root"
            let instructions = description ?? title
            let isInteger = (rawType == "integer")
            let criteria = generateScoreCriteria(min: min, max: max, isInteger: isInteger)
            let question = SystemOneQuestion.score(instructions: instructions, criteria: criteria)
            return SchemaTranslation(
                layout: .score(minimum: min, maximum: max, isInteger: isInteger, questionKey: questionKey),
                questions: [questionKey: question]
            )
        }

        // Case 4: Root is an Object (the standard @Generable struct)
        guard rawType == "object" || rawType == nil else {
            throw SystemOneError.invalidSchema(
                "Unsupported root schema type: '\(rawType ?? "unknown")'. System One requires an object or bounded decision primitive."
            )
        }

        guard let properties = json["properties"] as? [String: Any], !properties.isEmpty else {
            throw SystemOneError.invalidSchema(
                "Schema object contains no properties. At least one @Generable property is required."
            )
        }

        let requiredList = Set((json["required"] as? [String]) ?? [])
        let orderList = (json["x-order"] as? [String]) ?? Array(properties.keys).sorted()

        var propertyDescriptors: [String: SchemaPropertyDescriptor] = [:]
        var questions: [String: SystemOneQuestion] = [:]

        for (propName, propRawValue) in properties {
            var visitedDefs: Set<String> = []
            let resolved = try resolveProperty(raw: propRawValue, defs: defs, visitedDefs: &visitedDefs)
            let isRequired = requiredList.contains(propName)
            let (descriptor, propQuestions) = try translateProperty(
                name: propName,
                path: propName,
                propertyDict: resolved,
                isRequired: isRequired,
                defs: defs,
                visitedDefs: visitedDefs,
                depth: 0
            )
            propertyDescriptors[propName] = descriptor
            for (qKey, qVal) in propQuestions {
                questions[qKey] = qVal
            }
        }

        return SchemaTranslation(
            layout: .object(properties: propertyDescriptors, propertyOrder: orderList),
            questions: questions
        )
    }

    private func resolveProperty(
        raw: Any,
        defs: [String: [String: Any]],
        visitedDefs: inout Set<String>
    ) throws -> [String: Any] {
        guard var dict = raw as? [String: Any] else {
            throw SystemOneError.invalidSchema("Property definition must be a JSON object.")
        }

        // Iteratively resolve $ref and unwrap anyOf (e.g. nullable [null, targetType] or enum choice variants)
        var depth = 0
        let maxDepth = 10
        while depth < maxDepth {
            depth += 1
            var changed = false

            // Handle anyOf unwrapping (e.g. nullable [null, targetType] or enum choice variants)
            if let anyOf = dict["anyOf"] as? [[String: Any]] {
                dict.removeValue(forKey: "anyOf")
                let nonNullVariants = anyOf.filter { ($0["type"] as? String) != "null" }
                if let firstVariant = nonNullVariants.first {
                    for (k, v) in firstVariant where dict[k] == nil {
                        dict[k] = v
                    }
                    changed = true
                }
            }

            // Handle $ref dereferencing
            if let ref = dict["$ref"] as? String {
                dict.removeValue(forKey: "$ref")
                let refPrefix = "#/$defs/"
                guard ref.hasPrefix(refPrefix) else {
                    throw SystemOneError.invalidSchema("Unsupported $ref format: '\(ref)'. Only internal #/$defs/ references are supported.")
                }
                let defName = String(ref.dropFirst(refPrefix.count))
                guard !visitedDefs.contains(defName) else {
                    throw SystemOneError.invalidSchema("Recursive or cyclic schema reference detected for '\(defName)'")
                }
                visitedDefs.insert(defName)
                guard let referenced = defs[defName] else {
                    throw SystemOneError.invalidSchema("Referenced definition '\(defName)' was not found in $defs.")
                }
                // Merge referenced dict with property overrides (like description)
                for (k, v) in referenced where dict[k] == nil {
                    dict[k] = v
                }
                changed = true
            }

            if !changed {
                break
            }
        }

        return dict
    }

    private func translateProperty(
        name: String,
        path: String,
        propertyDict: [String: Any],
        isRequired: Bool,
        defs: [String: [String: Any]],
        visitedDefs: Set<String>,
        depth: Int
    ) throws -> (SchemaPropertyDescriptor, [String: SystemOneQuestion]) {
        guard depth <= 32 else {
            throw SystemOneError.invalidSchema("Maximum schema nesting depth (32) exceeded.")
        }

        let type = propertyDict["type"] as? String
        let description = propertyDict["description"] as? String
        let instructions = description ?? formatInstructions(from: name)

        // 1. Boolean -> noul
        if type == "boolean" {
            let descriptor = SchemaPropertyDescriptor(
                name: name,
                questionKey: path,
                kind: .boolean,
                instructions: instructions,
                isRequired: isRequired
            )
            let question = SystemOneQuestion.noul(instructions: instructions)
            return (descriptor, [path: question])
        }

        // 2. String with enum -> choice
        if type == "string", let enumCases = propertyDict["enum"] as? [String], !enumCases.isEmpty {
            var criteria: [String: String] = [:]
            for c in enumCases {
                criteria[c] = c
            }
            let descriptor = SchemaPropertyDescriptor(
                name: name,
                questionKey: path,
                kind: .choice(options: enumCases),
                instructions: instructions,
                isRequired: isRequired
            )
            let question = SystemOneQuestion.choice(instructions: instructions, criteria: criteria)
            return (descriptor, [path: question])
        }

        // 3. Integer or Number with range -> score
        if (type == "integer" || type == "number"),
           let min = (propertyDict["minimum"] as? NSNumber)?.doubleValue,
           let max = (propertyDict["maximum"] as? NSNumber)?.doubleValue {
            let isInteger = (type == "integer")
            let criteria = generateScoreCriteria(min: min, max: max, isInteger: isInteger)
            let descriptor = SchemaPropertyDescriptor(
                name: name,
                questionKey: path,
                kind: .score(minimum: min, maximum: max, isInteger: isInteger),
                instructions: instructions,
                isRequired: isRequired
            )
            let question = SystemOneQuestion.score(instructions: instructions, criteria: criteria)
            return (descriptor, [path: question])
        }

        // 4. Nested Object -> recursively translate
        if type == "object", let nestedProperties = propertyDict["properties"] as? [String: Any] {
            var nestedDescriptors: [String: SchemaPropertyDescriptor] = [:]
            var nestedQuestions: [String: SystemOneQuestion] = [:]
            let nestedRequired = Set((propertyDict["required"] as? [String]) ?? [])

            for (childName, childRaw) in nestedProperties {
                var childVisited = visitedDefs
                let resolvedChild = try resolveProperty(raw: childRaw, defs: defs, visitedDefs: &childVisited)
                let childPath = "\(path).\(childName)"
                let childRequired = nestedRequired.contains(childName)
                let (childDesc, childQs) = try translateProperty(
                    name: childName,
                    path: childPath,
                    propertyDict: resolvedChild,
                    isRequired: childRequired,
                    defs: defs,
                    visitedDefs: childVisited,
                    depth: depth + 1
                )
                nestedDescriptors[childName] = childDesc
                for (qK, qV) in childQs {
                    nestedQuestions[qK] = qV
                }
            }

            let descriptor = SchemaPropertyDescriptor(
                name: name,
                questionKey: path,
                kind: .nested(nestedDescriptors),
                instructions: instructions,
                isRequired: isRequired
            )
            return (descriptor, nestedQuestions)
        }

        // 5. Unconstrained String without enum -> reject early
        if type == "string" {
            throw SystemOneError.invalidSchema(
                "Property '\(name)' is an unconstrained String. System One is a decision model and does not generate free-form text. Use an enum, Bool, or @Guide(.range(...)) score."
            )
        }

        throw SystemOneError.invalidSchema(
            "Unsupported type '\(type ?? "unknown")' for property '\(name)'. System One supports Bool, String enums, and numerical ranges."
        )
    }

    private func generateScoreCriteria(min: Double, max: Double, isInteger: Bool) -> [String] {
        if isInteger {
            let start = Int(min)
            let end = Int(max)
            guard end >= start else { return ["Level \(start)"] }
            return (start...end).map { "Level \($0)" }
        } else {
            return ["Minimum (\(min))", "Midpoint (\((min + max) / 2))", "Maximum (\(max))"]
        }
    }

    private func formatInstructions(from propertyName: String) -> String {
        var result = ""
        for (i, char) in propertyName.enumerated() {
            if i == 0 {
                result.append(char.uppercased())
            } else if char.isUppercase {
                result.append(" ")
                result.append(char.lowercased())
            } else {
                result.append(char)
            }
        }
        return result
    }
}
