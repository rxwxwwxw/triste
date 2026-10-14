// Converted from Pegged examples; Boost Software License 1.0.
/**
 * Ultra-simple XML grammar
 */
module npegged.examples.xml;

import npegged.grammar;

ParseTree validate(ParseTree tree) @nogc nothrow {
    if (tree.successful && tree.children.length >= 2 && tree.children[0].matches[0] != tree.children[$ - 1]
            .matches[0])
        tree.successful = false;
    return tree;
}

@nogc nothrow unittest {
    ParseTree empty;
    assert(!validate(empty).successful);
    empty.successful = true;
    assert(validate(empty).successful);
}

mixin(grammar(`
XML:
    Node        <- (OpeningTag (Node / Text)* ClosingTag){validate}
    OpeningTag  <- :"<" identifier :">"
    ClosingTag  <- :"</" identifier :">"
    Text        <~ (!OpeningTag !ClosingTag .)+
`));

@nogc nothrow unittest {
    ParseContext context;
    auto p1 = XML(context, "<a></a>");
    assert(p1.successful);
    assert(p1.matches == ["a", "a"]);
    assert(p1.children[0].children.length == 2);

    assert(p1.children[0].name == "XML.Node");
    assert(p1.children[0].children[0].name == "XML.OpeningTag");
    assert(p1.children[0].children[1].name == "XML.ClosingTag");

    assert(!XML(context, "<b></>").successful); // incomplete closing tag
    assert(!XML(context, "<c></d>").successful); // unmatched tag
    assert(XML(context, "<e><f></f></e>").successful); // OK
    assert(!XML(context, "<g><h></g></h>").successful); // badly enclosed tags

    auto p2 = XML(context, "<text>Hello World! This is an <emph>important</emph> announcement!</text>");
    assert(p2.successful);

    assert(p2.matches == [
        "text", "Hello World! This is an ", "emph", "important", "emph", " announcement!", "text"
    ]);
    assert(p2.children[0].children[0].matches == ["text"]);
    assert(p2.children[0].children[1].matches == ["Hello World! This is an "]);
    assert(p2.children[0].children[$ - 1].matches == ["text"]);
}
