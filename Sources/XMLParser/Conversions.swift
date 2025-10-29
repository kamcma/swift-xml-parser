import Parsing
import Collections

extension Conversions {
    struct OptionalEmptyDictionary<Key: Hashable, Value>: Conversion {
        @inlinable
         init() {}

        @inlinable
        func apply(_ input: OrderedDictionary<Key, Value>?) -> OrderedDictionary<Key, Value> {
            input ?? [:]
        }

        @inlinable
        func unapply(_ output: OrderedDictionary<Key, Value>) -> OrderedDictionary<Key, Value>? {
            output.isEmpty ? nil : output
        }
    }
}

extension Conversions {
    struct UnpackXMLElement: Conversion {
        @inlinable
        init() { }

        @inlinable
        func apply(_ input: (String, OrderedDictionary<String, String>, [XML.Node], String)) -> (String, OrderedDictionary<String, String>, [XML.Node]) {
            (input.0, input.1, input.2)
        }

        @inlinable
        func unapply(_ output: (String, OrderedDictionary<String, String>, [XML.Node])) -> (String, OrderedDictionary<String, String>, [XML.Node], String) {
            (output.0, output.1, output.2, output.0)
        }
    }
}
