import CasePaths
import OrderedCollections
import Parsing

struct QuotedStringParser: ParserPrinter {
    var body: some ParserPrinter<Substring.UTF8View, String> {
        "\"".utf8
        PrefixUpTo("\"".utf8).map(.string)
        "\"".utf8
    }
}

struct AttributeParser: ParserPrinter {
    var body: some ParserPrinter<Substring.UTF8View, (String, String)> {
        PrefixUpTo("=".utf8).map(.string)
        "=".utf8
        QuotedStringParser()
    }
}

struct AttributesParser: ParserPrinter {
    var body: some ParserPrinter<Substring.UTF8View, OrderedDictionary<String, String>> {
        Many(into: OrderedDictionary<String, String>()) { attrs, attr in
            attrs.updateValue(attr.1, forKey: attr.0)
        } decumulator: { attrs in
            attrs.reversed().map({ ($0.key, $0.value) }).makeIterator()
        } element: {
            AttributeParser()
        } separator: {
            Whitespace(1..., .horizontal)
        }
    }
}

struct TagNameParser: ParserPrinter {
    var body: some ParserPrinter<Substring.UTF8View, String> {
        From(.substring) {
            Prefix { $0.isLetter }
        }
        .map(.string)
    }
}

struct TagHeadParser: ParserPrinter {
    var body: some ParserPrinter<Substring.UTF8View, (String, OrderedDictionary<String, String>)> {
        TagNameParser()
        ParsePrint {
            Whitespace(1..., .horizontal)
            AttributesParser()
        }
        .replaceError(with: OrderedDictionary<String, String>())
        .printing { attrs, input in
            try AttributesParser().print(attrs, into: &input)
            if !attrs.isEmpty {
                try Whitespace(1, .horizontal).print(into: &input)
            }
        }
        Whitespace(.horizontal)
    }
}

struct XMLParsingError: Error {}

let emptyTagParser = ParsePrint {
    "<".utf8
    Not { "/".utf8 }
    Prefix(1...) { $0 != .init(ascii: ">") }.pipe {
        TagHeadParser()
        "/".utf8
    }
    ">".utf8
    Always([XML.Node]())
    Always("")
}
.filter { $0.2.isEmpty }
.map(Conversions.UnpackXMLElement())
.map(.memberwise(XML.Element.init))

struct CommentParser: ParserPrinter {
    var body: some ParserPrinter<Substring.UTF8View, XML.Node> {
        ParsePrint(.case(XML.Node.comment)) {
            "<!--".utf8
            PrefixUpTo("-->".utf8).map(.string)
            "-->".utf8
        }
    }
}

struct TextParser: ParserPrinter {
    var body: some ParserPrinter<Substring.UTF8View, XML.Node> {
        ParsePrint {
            Whitespace(.horizontal)
            Prefix(1...) {
                $0 != .init(ascii: "<") && $0 != .init(ascii: "\n")
            }
        }
        .map(.string)
        .map(.case(XML.Node.text))
    }
}

struct XMLPrologParser: ParserPrinter {
    var body: some ParserPrinter<Substring.UTF8View, OrderedDictionary<String, String>> {
        "<?xml".utf8
        ParsePrint {
            Whitespace(1..., .horizontal)
            AttributesParser()
        }
        .replaceError(with: OrderedDictionary<String, String>())
        .printing { attrs, input in
            try AttributesParser().print(attrs, into: &input)
            if !attrs.isEmpty {
                try Whitespace(1, .horizontal).print(into: &input)
            }
        }
        Whitespace(.horizontal)
        "?>".utf8
    }
}

let openingTagParser = ParsePrint {
    "<".utf8
    Not { "/".utf8 }
    Prefix(1...) { $0 != .init(ascii: ">") }.pipe {
        TagHeadParser()
        Whitespace(.horizontal)
        Not { "/".utf8 }
    }
    ">".utf8
}

let containerTagParser = { (indentation: Int?) in
    ParsePrint {
        openingTagParser
        Whitespace(.vertical).printing(indentation != nil ? "\n".utf8 : "".utf8)
        Many {
            Lazy {
                contentParser(indentation.map { $0 + 4 })
                Whitespace(.vertical).printing(
                    indentation != nil ? "\n".utf8 : "".utf8
                )
            }
        } terminator: {
            Whitespace(.horizontal).printing(
                String(repeating: " ", count: indentation ?? 0).utf8
            )
            "</".utf8
        }
        Prefix { $0 != .init(ascii: ">") }.map(.string)
        ">".utf8
    }
    .filter { tagHead, _, _, closingTag in tagHead == closingTag }
    .map(Conversions.UnpackXMLElement())
    .map(.memberwise(XML.Element.init))
}

let contentParser: (Int?) -> AnyParserPrinter<Substring.UTF8View, XML.Node> = {
    indentation in
    ParsePrint {
        Whitespace(.horizontal).printing(
            String(repeating: " ", count: indentation ?? 0).utf8
        )
        OneOf {
            containerTagParser(indentation).map(/XML.Node.element)
            emptyTagParser.map(/XML.Node.element)
            CommentParser()
            TextParser()
        }
    }.eraseToAnyParserPrinter()
}

/// A reversible parser that takes in a string of XML and parses it into a structured ``XML`` type, or prints structured ``XML`` into an XML string.
///
/// You can create an ``XMLParser/XMLParser`` using ``init(indenting:)``
///
/// ```swift
/// let xmlParser = XMLParser(indenting: true)
/// let xmlString = "<root><value/></root>"
/// let xml: XML = try xmlParser.parse(xmlString)
/// ```
public struct XMLParser: ParserPrinter {
    let parser: AnyParserPrinter<Substring.UTF8View, XML>
    /// Creates an XMLParser with indented or `minified` printing.
    /// - Parameters:
    ///   - indenting: wether to print using indentation and newlines or not.
    public init(indenting: Bool = true) {
        self.parser = ParsePrint {
            Optionally {
                XMLPrologParser()
                Whitespace(.vertical).printing(indenting ? "\n".utf8 : "".utf8)
            }.map(Conversions.OptionalEmptyDictionary())
            containerTagParser(indenting ? 0 : nil)
            End()
        }
        .map(.memberwise(XML.init(prolog:root:)))
        .eraseToAnyParserPrinter()
    }

    /// Prints an string representation of xml into the provided input.
    /// - Parameters:
    ///   - output: the structured XML to turn into a string
    ///   - input: the input to write the string representation to
    public func print(_ output: XML, into input: inout Substring.UTF8View)
        throws
    {
        try parser.print(output, into: &input)
    }

    /// Parses an xml string into a structured ``XML`` type
    /// - Parameters:
    ///   - input: the input string to parse
    /// - Returns: A structured ``XML``  type
    public func parse(_ input: inout Substring.UTF8View) throws -> XML {
        try parser.parse(&input)
    }
}
