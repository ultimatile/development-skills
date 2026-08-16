# /// script
# requires-python = ">=3.10"
# dependencies = ["tree-sitter", "tree-sitter-language-pack"]
# ///
"""Compute each comment block's referent from the tree-sitter parse tree.

Usage: uv run --script referent.py <file> [<file>...]

Output: JSON Lines, one object per file:

  {"path": str,
   "unreached": "no-grammar" | "binary" | "parse-error" | null,
   "excluded_lines": [{"line": int, "text": str}],
   "blocks": [{"span": {"start_line": int, "end_line": int},
               "text": str,
               "relation": "docstring" | "inner-doc" | "forward" | "trailing"
                           | "next-sibling" | "header" | null,
               "referent": {"span": {"start_line": int, "end_line": int},
                            "text": str} | null,
               "unreached": "parse-error" | null}]}

Line numbers are 1-based. A block's "referent" is null exactly when its
"unreached" is "parse-error", and its "relation" is null only on such a
block — a block whose own text or immediate surroundings did not parse.
A referent's "span" covers the whole bound construct, body included; its
"text" is that construct's text, string literals retained, with the body
subtree and nested comment blocks stripped. Exit 2 on a missing or
unreadable path (usage error).
"""

import json
import re
import sys

from tree_sitter_language_pack import detect_language_from_path, get_parser


# Node types that are comments across the pack's grammars. Doc-marker child
# nodes inside Rust comments also contain "comment" in their type, so the
# collector below stops at the outermost comment node and never descends.
def is_comment(node):
    return "comment" in node.type.lower()


# Grammars that give the interpreter line its own node type instead of a
# comment node (JavaScript, Rust). Collected so the line is excluded and
# stripped from referents like its comment-node counterparts.
INTERPRETER_TYPES = {"hash_bang_line", "shebang"}


def is_interpreter_node(node):
    return node.type in INTERPRETER_TYPES


def eff_end_row(node):
    """The last row on which the node has text.

    A node ending at column 0 of a later row consumed its trailing newline
    (Rust doc line comments do this), so its raw end row overstates where
    its text sits; the same shape makes a multi-line previous sibling look
    same-row to a following comment.
    """
    row, col = node.end_point
    return row - 1 if col == 0 and row > node.start_point[0] else row


def rows_adjacent(above, below):
    """Whether below starts on the row right after above's last text row."""
    return eff_end_row(above) + 1 == below.start_point[0]


def rust_marker_kind(node):
    """'inner' for //! and /*! */, 'outer' for /// and /** */, else 'bare'."""
    for i in range(node.child_count):
        field = node.field_name_for_child(i)
        if field in ("inner", "outer"):
            return field
    return "bare"


def named_siblings(node):
    parent = node.parent
    if parent is None:
        return []
    return list(parent.named_children)


def nearest_noncomment(siblings, index, step, docstring_ids):
    """The nearest non-comment, non-docstring sibling from index, walking step."""
    i = index + step
    while 0 <= i < len(siblings):
        node = siblings[i]
        if not is_comment(node) and node.id not in docstring_ids:
            return node
        i += step
    return None


def chain_adjacent(siblings, index, target, docstring_ids):
    """Whether every hop from siblings[index] to target is row-adjacent.

    Comment/docstring siblings between the two are transparent for binding
    but each consecutive pair must be adjacent for adjacency to hold.
    """
    prev = siblings[index]
    i = index + 1
    while i < len(siblings):
        node = siblings[i]
        if not rows_adjacent(prev, node):
            return False
        if node.id == target.id:
            return True
        if not (is_comment(node) or node.id in docstring_ids):
            return False
        prev = node
        i += 1
    return False


# Node types that are a construct's scope body across the tested grammars.
# A `body` field whose child is not one of these is grammar vocabulary for
# something else (bash redirected_statement names its command `body`), and
# stripping it would remove referent text, so it is left in place.
BODY_TYPES = {
    "block",
    "compound_statement",
    "statement_block",
    "body_statement",
    "declaration_list",
    "field_declaration_list",
    "class_body",
    "enum_variant_list",
    "enum_body",
    "constructor_body",
}


def strip_body(node, source):
    """The node's text minus its body subtree, as (text, body_range).

    The body is the node's `body` field; else the `body` field of the child
    a wrapper node holds in its `definition` (Python decorated_definition) or
    `declaration` (JS/TS export_statement) field; else, for a `*_definition`
    node, a `block` child (Julia) — accepted only when its type is a
    scope-body type. A node with none carries its whole text, an initializer
    included.
    """
    body = node.child_by_field_name("body")
    if body is None:
        for wrapper_field in ("definition", "declaration"):
            inner = node.child_by_field_name(wrapper_field)
            if inner is not None:
                body = inner.child_by_field_name("body")
                break
    if body is not None and body.type not in BODY_TYPES:
        body = None
    if body is None and node.type.endswith("_definition"):
        body = next((c for c in node.named_children if c.type == "block"), None)
    if body is None:
        return source[node.start_byte : node.end_byte], None
    text = (
        source[node.start_byte : body.start_byte]
        + source[body.end_byte : node.end_byte]
    )
    return text, (body.start_byte, body.end_byte)


def strip_comments(text, base_byte, node, body_range, comment_nodes):
    """Remove comment/docstring spans that fall inside the referent text."""
    spans = []
    for c in comment_nodes:
        if c.start_byte >= node.start_byte and c.end_byte <= node.end_byte:
            if (
                body_range
                and c.start_byte >= body_range[0]
                and c.end_byte <= body_range[1]
            ):
                continue
            start = c.start_byte - base_byte
            if body_range and c.start_byte >= body_range[1]:
                start -= body_range[1] - body_range[0]
            spans.append((start, start + (c.end_byte - c.start_byte)))
    for start, end in sorted(spans, reverse=True):
        text = text[:start] + text[end:]
    return text


def collect(root, docstring_ids):
    """All outermost comment nodes plus docstring nodes, in document order."""
    out = []

    def walk(node):
        if is_comment(node) or is_interpreter_node(node):
            out.append(node)
            return
        if node.id in docstring_ids:
            out.append(node)
        for child in node.children:
            walk(child)

    walk(root)
    out.sort(key=lambda n: n.start_byte)
    return out


def python_docstrings(root):
    """String nodes that are the first statement of a module/def/class body."""
    ids = {}

    def is_docstring_node(node):
        # An f-string or bytes literal is a string node too, but CPython
        # assigns neither to __doc__; implicitly concatenated string
        # literals do become the docstring.
        if node.type == "concatenated_string":
            return all(is_docstring_node(c) for c in node.named_children)
        if node.type != "string":
            return False
        start = node.children[0] if node.child_count else None
        prefix = start.text.lower() if start is not None else b""
        return b"f" not in prefix and b"b" not in prefix

    def first_statement_string(body):
        if body is None or body.named_child_count == 0:
            return None
        first = next((c for c in body.named_children if not is_comment(c)), None)
        if first is None:
            return None
        if is_docstring_node(first):
            return first
        if first.type == "expression_statement" and first.named_child_count == 1:
            child = first.named_children[0]
            if is_docstring_node(child):
                return child
        return None

    candidate = first_statement_string(root)
    if candidate is not None:
        ids[candidate.id] = root

    def walk(node):
        if node.type in ("function_definition", "class_definition"):
            target = node
            if node.parent is not None and node.parent.type == "decorated_definition":
                target = node.parent
            child = first_statement_string(node.child_by_field_name("body"))
            if child is not None:
                ids[child.id] = target
        for c in node.named_children:
            walk(c)

    walk(root)
    return ids


def julia_doc_eligible(node):
    """Whether node sits where a bare string can document what follows."""
    parent = node.parent
    if parent is None:
        return False
    if parent.type == "source_file":
        return True
    if parent.type == "block":
        outer = parent.parent
        if outer is None:
            return False
        if outer.type == "module_definition":
            return True
        if outer.type == "compound_statement":
            return julia_doc_eligible(outer)
    return False


def julia_docstrings(root):
    """string_literal nodes Julia's doc system attaches, mapped to their target."""
    ids = {}

    def walk(node):
        for child in node.named_children:
            walk(child)
        if node.type == "string_literal" and julia_doc_eligible(node):
            siblings = named_siblings(node)
            index = siblings.index(node)
            if index + 1 < len(siblings):
                target = siblings[index + 1]
                if not is_comment(target) and rows_adjacent(node, target):
                    ids[node.id] = target
        if node.type == "macrocall_expression":
            macro = node.named_children[0] if node.named_child_count else None
            if macro is not None and macro.text == b"@doc":
                args = node.child_by_field_name("arguments") or next(
                    (c for c in node.named_children if c.type == "macro_argument_list"),
                    None,
                )
                if args is not None:
                    arg_nodes = args.named_children
                    if arg_nodes and arg_nodes[0].type == "string_literal":
                        if len(arg_nodes) >= 2:
                            ids[arg_nodes[0].id] = arg_nodes[1]
                        else:
                            siblings = named_siblings(node)
                            index = siblings.index(node)
                            if index + 1 < len(siblings):
                                target = siblings[index + 1]
                                if not is_comment(target) and rows_adjacent(
                                    node, target
                                ):
                                    ids[arg_nodes[0].id] = target

    walk(root)
    return ids


def subtree_has_error(node):
    if node.type == "ERROR" or node.is_missing:
        return True
    if not node.has_error:
        return False
    return any(subtree_has_error(c) for c in node.children)


def retained_region_has_error(node, body_range):
    """ERROR/missing intersecting the node minus its stripped body."""

    def walk(n):
        if body_range and n.start_byte >= body_range[0] and n.end_byte <= body_range[1]:
            return False
        if n.type == "ERROR" or n.is_missing:
            return True
        if not n.has_error and not any(c.is_missing for c in n.children):
            return False
        return any(walk(c) for c in n.children)

    return walk(node)


def line_span(start_node, end_node):
    return {
        "start_line": start_node.start_point[0] + 1,
        "end_line": eff_end_row(end_node) + 1,
    }


def utf8(data):
    return data.decode("utf-8", errors="replace")


def finish_block(record, relation, referent, unreached):
    """The one writer of a block's verdict fields, holding their invariant."""
    if (referent is None) != (unreached == "parse-error"):
        raise ValueError("referent must be null exactly on a parse-error block")
    if relation is None and unreached != "parse-error":
        raise ValueError("relation may be null only on a parse-error block")
    record.update({"relation": relation, "referent": referent, "unreached": unreached})
    return record


# The encoding-cookie pattern of CPython's tokenizer (Lib/tokenize.py,
# cookie_re; Copyright (c) Python Software Foundation, PSF-2.0-licensed).
# With the own-line and first-line checks below, only a line the interpreter
# itself would read as an encoding declaration is machine-directed.
CODING_COOKIE = re.compile(rb"^[ \t\f]*#.*?coding[:=][ \t]*([-\w.]+)")


def excluded_line(node, source, lang):
    """Shebang on row 0; Python coding pragma on row 0 or 1, as CPython reads it."""
    if is_interpreter_node(node):
        return True
    line_start = source.rfind(b"\n", 0, node.start_byte) + 1
    before = source[line_start : node.start_byte]
    if line_start == 0 and before.startswith(b"\xef\xbb\xbf"):
        before = before[3:]
    if before.strip():
        return False
    text = source[node.start_byte : node.end_byte]
    if node.start_point[0] == 0 and text.startswith(b"#!"):
        return True
    if lang == "python" and CODING_COOKIE.match(text):
        row = node.start_point[0]
        if row == 0:
            return True
        if row == 1:
            newline = source.find(b"\n")
            first = source[: newline if newline != -1 else len(source)]
            if first.startswith(b"\xef\xbb\xbf"):
                first = first[3:]
            first = first.strip()
            if CODING_COOKIE.match(first):
                return False
            return first == b"" or first.startswith(b"#")
    return False


def bind(block_nodes, docstring_map, source, comment_nodes, lang):
    """Referent for a block (a list of member nodes), per the precedence order."""
    head, tail = block_nodes[0], block_nodes[-1]
    docstring_ids = set(docstring_map)

    if head.id in docstring_ids:
        return "docstring", docstring_map[head.id]

    if lang == "rust" and rust_marker_kind(head) == "inner":
        return "inner-doc", head.parent

    siblings = named_siblings(tail)
    if not siblings:
        return "header", tail.parent
    tail_index = siblings.index(tail)
    head_index = siblings.index(head)

    forward = nearest_noncomment(siblings, tail_index, +1, docstring_ids)
    if forward is not None and forward.start_point[0] == eff_end_row(tail):
        return "forward", forward

    backward = nearest_noncomment(siblings, head_index, -1, docstring_ids)
    if backward is not None and head.start_point[0] == eff_end_row(backward):
        return "trailing", backward

    if forward is not None and chain_adjacent(
        siblings, tail_index, forward, docstring_ids
    ):
        target = forward
        attributes = []
        while target is not None and target.type == "attribute_item":
            attributes.append(target)
            target = nearest_noncomment(
                siblings, siblings.index(target), +1, docstring_ids
            )
        if target is None:
            target = attributes.pop() if attributes else forward
        return "next-sibling", (target, attributes)

    return "header", head.parent


def referent_record(relation, bound, source, comment_nodes):
    if relation == "next-sibling" and isinstance(bound, tuple):
        target, attributes = bound
        text, body_range = strip_body(target, source)
        text = strip_comments(
            text, target.start_byte, target, body_range, comment_nodes
        )
        prefix = b"".join(
            strip_comments(
                source[a.start_byte : a.end_byte], a.start_byte, a, None, comment_nodes
            )
            + b"\n"
            for a in attributes
        )
        error = retained_region_has_error(target, body_range) or any(
            subtree_has_error(a) for a in attributes
        )
        first = attributes[0] if attributes else target
        return {"span": line_span(first, target), "text": utf8(prefix + text)}, error
    node = bound
    text, body_range = strip_body(node, source)
    text = strip_comments(text, node.start_byte, node, body_range, comment_nodes)
    error = retained_region_has_error(node, body_range)
    return {"span": line_span(node, node), "text": utf8(text)}, error


def starts_own_line(node):
    """False for a trailing comment — anything, punctuation included, sits
    before it on its row."""
    back = node.prev_sibling
    return back is None or node.start_point[0] != eff_end_row(back)


def merge_runs(nodes, docstring_ids, lang):
    """Group whole-line comment nodes into runs; docstrings stand alone."""
    blocks = []
    for node in nodes:
        if blocks:
            prev = blocks[-1][-1]
            joins = (
                node.id not in docstring_ids
                and prev.id not in docstring_ids
                and is_comment(node)
                and is_comment(prev)
                and prev.parent == node.parent
                and (lang != "rust" or rust_marker_kind(prev) == rust_marker_kind(node))
                and rows_adjacent(prev, node)
                and starts_own_line(node)
                and starts_own_line(prev)
            )
            if joins:
                blocks[-1].append(node)
                continue
        blocks.append([node])
    return blocks


def unreached_record(path, kind):
    return {"path": path, "unreached": kind, "excluded_lines": [], "blocks": []}


def process(path):
    lang = detect_language_from_path(path)
    if lang is None:
        return unreached_record(path, "no-grammar")
    with open(path, "rb") as fh:
        raw = fh.read()
    if b"\x00" in raw:
        return unreached_record(path, "binary")
    try:
        raw.decode("utf-8")
    except UnicodeDecodeError:
        return unreached_record(path, "binary")

    parser = get_parser(lang)
    tree = parser.parse(raw)
    root = tree.root_node
    if (
        root.has_error
        and all(c.type == "ERROR" for c in root.children)
        and root.child_count > 0
    ):
        return unreached_record(path, "parse-error")

    docstring_map = {}
    if lang == "python":
        docstring_map = python_docstrings(root)
    elif lang == "julia":
        docstring_map = julia_docstrings(root)
    docstring_ids = set(docstring_map)

    nodes = collect(root, docstring_ids)
    excluded = []
    kept = []
    for node in nodes:
        if (is_comment(node) or is_interpreter_node(node)) and excluded_line(
            node, raw, lang
        ):
            excluded.append(
                {
                    "line": node.start_point[0] + 1,
                    "text": utf8(raw[node.start_byte : node.end_byte]),
                }
            )
        else:
            kept.append(node)

    comment_nodes = nodes

    blocks = []
    for block_nodes in merge_runs(kept, docstring_ids, lang):
        head, tail = block_nodes[0], block_nodes[-1]
        text = utf8(raw[head.start_byte : tail.end_byte])
        record = {"span": line_span(head, tail), "text": text}
        if (
            any(subtree_has_error(n) for n in block_nodes)
            or head.parent.type == "ERROR"
        ):
            blocks.append(finish_block(record, None, None, "parse-error"))
            continue
        relation, bound = bind(block_nodes, docstring_map, raw, comment_nodes, lang)
        if bound is None:
            blocks.append(finish_block(record, relation, None, "parse-error"))
            continue
        target = bound[0] if isinstance(bound, tuple) else bound
        if target.type == "ERROR" or target.is_missing:
            blocks.append(finish_block(record, relation, None, "parse-error"))
            continue
        ref, error = referent_record(relation, bound, raw, comment_nodes)
        if error:
            blocks.append(finish_block(record, relation, None, "parse-error"))
        else:
            blocks.append(finish_block(record, relation, ref, None))

    return {
        "path": path,
        "unreached": None,
        "excluded_lines": excluded,
        "blocks": blocks,
    }


def main(argv):
    # The contract emits non-ASCII text verbatim, so the output encoding must
    # not depend on the locale.
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    if len(argv) < 2:
        print("usage: referent.py <file> [<file>...]", file=sys.stderr)
        return 2
    for path in argv[1:]:
        try:
            open(path, "rb").close()
        except OSError as exc:
            print(f"referent.py: cannot read {path}: {exc}", file=sys.stderr)
            return 2
    for path in argv[1:]:
        print(json.dumps(process(path), ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
