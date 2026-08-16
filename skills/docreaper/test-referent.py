# /// script
# requires-python = ">=3.10"
# dependencies = []
# ///
"""Specimen test for referent.py's binding relations and failure shapes.

Usage: uv run --script test-referent.py

Writes each specimen to a temp directory, runs referent.py over all of them
in one invocation, and checks each emitted record. Runs every check and
exits 1 when any failed. Each run goes through the invocation the skill
documents, so the script's own dependency metadata is exercised too.
"""

import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "referent.py")
# The invocation Step 2 of SKILL.md documents; `--script` keeps uv from
# resolving whatever project directory the test happens to run under.
COMMAND = ["uv", "run", "--script", SCRIPT]

FAILURES = []


def invoke(args):
    return subprocess.run(
        COMMAND + args, capture_output=True, encoding="utf-8", check=False
    )


def run(paths):
    proc = invoke(paths)
    if proc.returncode != 0:
        raise RuntimeError(f"referent.py exited {proc.returncode}: {proc.stderr}")
    return [json.loads(line) for line in proc.stdout.splitlines()]


def block_at(record, line):
    for block in record["blocks"]:
        if block["span"]["start_line"] == line:
            return block
    return None


def check(name, condition, detail=""):
    status = "ok  " if condition else "FAIL"
    print(f"{status} {name}" + (f"  [{detail}]" if not condition and detail else ""))
    if not condition:
        FAILURES.append(name)


def expect(
    name,
    line,
    relation,
    contains=(),
    not_contains=(),
    end_line=None,
    referent_start=None,
):
    """Declarative checker for the common shape: one block, its relation,
    substrings the referent text must / must not carry, and optional
    block-end / referent-start line pins."""

    def checker(rec):
        b = block_at(rec, line)
        ok = (
            b is not None
            and b["relation"] == relation
            and b["unreached"] is None
            and b["referent"] is not None
        )
        if ok and (contains or not_contains):
            text = b["referent"]["text"]
            ok = all(s in text for s in contains)
            ok = ok and all(s not in text for s in not_contains)
        if ok and end_line is not None:
            ok = b["span"]["end_line"] == end_line
        if ok and referent_start is not None:
            ok = (
                b["referent"] is not None
                and b["referent"]["span"]["start_line"] == referent_start
            )
        check(name, ok, json.dumps(b))

    return checker


def expect_many(name, expectations):
    """Declarative checker over several blocks: (line, relation, contains)."""

    def checker(rec):
        ok = True
        for line, relation, contains in expectations:
            b = block_at(rec, line)
            if (
                b is None
                or b["relation"] != relation
                or b["unreached"] is not None
                or b["referent"] is None
            ):
                ok = False
                break
            if any(t not in b["referent"]["text"] for t in contains):
                ok = False
                break
        check(name, ok, json.dumps(rec["blocks"]))

    return checker


def no_docstring_block(name, absent_text=None):
    """Checker: no block took the docstring relation; optionally, no block
    carries the given text at all."""

    def checker(rec):
        ok = all(b["relation"] != "docstring" for b in rec["blocks"])
        if ok and absent_text is not None:
            ok = all(absent_text not in b["text"] for b in rec["blocks"])
        check(name, ok, json.dumps(rec["blocks"]))

    return checker


def excluded_first_line(name, line_expected, block_line, relation):
    """Checker: line 1 is in excluded_lines and the named block still binds."""

    def checker(rec):
        lines = [e["line"] for e in rec["excluded_lines"]]
        b = block_at(rec, block_line)
        check(
            name,
            lines == [line_expected] and b is not None and b["relation"] == relation,
            json.dumps(rec),
        )

    return checker


def unreached_file(name, discriminant):
    def checker(rec):
        check(name, rec["unreached"] == discriminant, json.dumps(rec))

    return checker


# --- Custom checkers for shapes the declarative forms do not carry ---


def rust_bad_attribute(rec):
    b = block_at(rec, 1)
    check(
        "rust: malformed attribute in the composite referent -> parse-error",
        b and b["unreached"] == "parse-error",
        json.dumps(b),
    )


def one_block(name, end_line):
    def checker(rec):
        check(
            name,
            len(rec["blocks"]) == 1
            and rec["blocks"][0]["span"]["end_line"] == end_line,
            json.dumps(rec["blocks"]),
        )

    return checker


def julia_comment_between(rec):
    b = block_at(rec, 2)
    check(
        "julia: comment between string and function -> string is no docstring, "
        "comment binds to fn",
        all(x["relation"] != "docstring" for x in rec["blocks"])
        and b
        and b["relation"] == "next-sibling",
        json.dumps(rec["blocks"]),
    )


def python_shebang_pragma(rec):
    lines = [e["line"] for e in rec["excluded_lines"]]
    texts = [e["text"] for e in rec["excluded_lines"]]
    check(
        "python: shebang and coding pragma are excluded lines, not blocks",
        lines == [1, 2]
        and texts[0].startswith("#!")
        and block_at(rec, 1) is None
        and block_at(rec, 2) is None,
        json.dumps(rec),
    )


def python_nonascii(rec):
    b = block_at(rec, 1)
    check(
        "python: non-ASCII text round-trips through the block text",
        b is not None and b["relation"] == "trailing" and b["text"] == "# コメント",
        json.dumps(b),
    )


def c_paren_trailing_split(rec):
    texts = [b["text"] for b in rec["blocks"]]
    check(
        "c: a comment trailing an open paren does not merge with the next "
        "line's comment",
        "// note on the call" in texts and "// second note" in texts,
        json.dumps(rec["blocks"]),
    )


def python_docstring_trailing_split(rec):
    texts = [b["text"] for b in rec["blocks"]]
    check(
        "python: a trailing comment after a docstring does not merge with "
        "the next line's comment",
        "# trailing note" in texts and "# next comment" in texts,
        json.dumps(rec["blocks"]),
    )


def c_error_locality(rec):
    near = block_at(rec, 5)
    far = block_at(rec, 1)
    check(
        "c: block near the missing semicolon is parse-error, distant block binds",
        near
        and near["unreached"] == "parse-error"
        and far
        and far["unreached"] is None,
        json.dumps([far, near]),
    )


def json_structural(rec):
    b = block_at(rec, 1)
    check(
        "output: comment text with quotes and backslashes survives JSON",
        b is not None and '"quoted"' in b["text"] and "\\" in b["text"],
        json.dumps(b),
    )


def comments_only(rec):
    check(
        "comments-only file: blocks bind to the file root",
        rec["unreached"] is None
        and len(rec["blocks"]) == 2
        and all(b["relation"] == "header" for b in rec["blocks"]),
        json.dumps(rec),
    )


def empty_file(rec):
    check(
        "empty file: reached, no blocks",
        rec["unreached"] is None and rec["blocks"] == [],
        json.dumps(rec),
    )


SPECIMENS = [
    (
        "rs",
        "/// Adds one.\nfn f(x: u32) -> u32 { x + 1 }\n",
        expect(
            "rust: tight /// binds to fn",
            1,
            "next-sibling",
            contains=["fn f"],
            not_contains=["x + 1"],
        ),
    ),
    (
        "rs",
        "/// dangling doc\n\nfn f() {}\n",
        expect("rust: /// + blank line is a header", 1, "header"),
    ),
    (
        "rs",
        "/// Adds one\n/// to the input.\nfn f(x: u32) -> u32 { x + 1 }\n",
        expect(
            "rust: /// run merges and binds to fn",
            1,
            "next-sibling",
            contains=["fn f"],
            end_line=2,
            referent_start=3,
        ),
    ),
    (
        "rs",
        "/// a\n\n/// b\nfn f() {}\n",
        expect_many(
            "rust: blank line splits a /// run",
            [(1, "header", []), (3, "next-sibling", [])],
        ),
    ),
    (
        "rs",
        "fn g() {}\n/// eof doc",
        expect(
            "rust: /// at EOF without newline is a header (no false trailing)",
            2,
            "header",
        ),
    ),
    (
        "rs",
        "//! module doc\n\nfn f() {}\n",
        expect(
            "rust: //! binds to the file, comments stripped from the referent",
            1,
            "inner-doc",
            contains=["fn f"],
            not_contains=["module doc"],
        ),
    ),
    (
        "rs",
        "/*! module doc */\n\nfn f() {}\n",
        expect("rust: /*! */ binds to the file", 1, "inner-doc"),
    ),
    (
        "rs",
        "//! module doc\n/// fn doc\nfn f() {}\n",
        expect_many(
            "rust: //! + /// stack splits into two blocks with distinct referents",
            [(1, "inner-doc", []), (2, "next-sibling", [])],
        ),
    ),
    (
        "rs",
        "// SPDX-License-Identifier: MIT\n// Copyright example\n/// fn doc\nfn f() {}\n",
        expect_many(
            "rust: bare license run splits from /// run; both bind to fn",
            [(1, "next-sibling", ["fn f"]), (3, "next-sibling", ["fn f"])],
        ),
    ),
    (
        "rs",
        "/// doc\n#[inline]\nfn f() {}\n",
        expect(
            "rust: /// above #[inline] reaches fn with the attribute in the referent",
            1,
            "next-sibling",
            contains=["#[inline]", "fn f"],
        ),
    ),
    (
        "rs",
        "/// doc\n#[inline]\n#[must_use]\nfn f() -> u32 { 1 }\n",
        expect(
            "rust: /// above two attributes reaches fn with both in the referent",
            1,
            "next-sibling",
            contains=["#[inline]", "#[must_use]", "fn f"],
        ),
    ),
    ("rs", "/// doc\n#[inline(]\nfn f() {}\n", rust_bad_attribute),
    (
        "rs",
        "/* Reset the device.\n\n   Caller holds the lock. */\nfn f() {}\n",
        one_block("rust: /* .. blank .. */ is one block", 3),
    ),
    (
        "rs",
        "fn f() -> u32 {\n    // picks the key\n    let key = { 1 + 2 };\n    key\n}\n",
        expect(
            "rust: a let binding's block-expression initializer stays in the referent",
            2,
            "next-sibling",
            contains=["1 + 2"],
        ),
    ),
    (
        "jl",
        '"""Sorts the rows."""\nfunction rank(rows)\n    sort(rows)\nend\n',
        expect(
            "julia: docstring above function",
            1,
            "docstring",
            contains=["function rank"],
            not_contains=["sort("],
        ),
    ),
    (
        "jl",
        '"doc"\nmodule M\nend\n',
        expect("julia: docstring above module", 1, "docstring", contains=["module M"]),
    ),
    (
        "jl",
        '"doc"\nstruct S\n    a::Int\nend\n',
        expect("julia: docstring above struct", 1, "docstring", contains=["struct S"]),
    ),
    (
        "jl",
        '"doc"\nconst N = 5\n',
        expect("julia: docstring above const", 1, "docstring", contains=["const N"]),
    ),
    (
        "jl",
        '"doc"\nf(x) = x + 1\n',
        expect(
            "julia: docstring above short-form def", 1, "docstring", contains=["f(x)"]
        ),
    ),
    (
        "jl",
        'function f()\n    "hello"\nend\n',
        no_docstring_block(
            "julia: a string as a function's return value is not a block",
            absent_text="hello",
        ),
    ),
    (
        "jl",
        '@doc "Adds one." g(x) = x + 1\n',
        expect(
            "julia: @doc two-argument form binds the string to the target",
            1,
            "docstring",
            contains=["g(x)"],
        ),
    ),
    (
        "jl",
        '@doc "Adds one."\nh(x) = x + 1\n',
        expect(
            "julia: @doc single-argument form binds to the next sibling",
            1,
            "docstring",
            contains=["h(x)"],
        ),
    ),
    (
        "jl",
        '"dangling"\n\nf(x) = x\n',
        no_docstring_block(
            "julia: docstring + blank line does not attach and is not a block",
            absent_text="dangling",
        ),
    ),
    ("jl", '"not a doc"\n# comment\nf(x) = x\n', julia_comment_between),
    (
        "jl",
        'md"text"\nf(x) = x\n',
        no_docstring_block("julia: prefixed string literal is not a docstring"),
    ),
    (
        "jl",
        "function f(x)\n    x + 1\nend  # end of f\n",
        expect(
            "julia: trailing comment after end", 3, "trailing", contains=["function f"]
        ),
    ),
    (
        "jl",
        "y = begin\n    a = 1\n    a + 1\n    # last item\nend\n",
        expect(
            "julia: comment as last item of a begin block is no false trailing",
            4,
            "header",
        ),
    ),
    (
        "jl",
        'begin\n"doc"\nf(x) = x\nend\n',
        expect("julia: docstring inside top-level begin attaches", 2, "docstring"),
    ),
    (
        "jl",
        'if true\n"not doc"\nf(x) = x\nend\n',
        no_docstring_block("julia: string inside if is not a docstring"),
    ),
    (
        "jl",
        "#= Reset.\n\nHolds the lock. =#\nf(x) = x\n",
        one_block("julia: #= .. blank .. =# is one block", 3),
    ),
    (
        "jl",
        '"""Doc."""\nfunction f(x)\n    x + 1\n    # inner note\nend\n',
        expect(
            "julia: a comment after the stripped body is stripped from the referent",
            1,
            "docstring",
            contains=["function f"],
            not_contains=["inner note"],
        ),
    ),
    (
        "py",
        '"""Module doc."""\nx = 1\n',
        expect("python: module docstring binds to the file", 1, "docstring"),
    ),
    (
        "py",
        '# leading comment\n"""Module doc."""\nx = 1\n',
        expect(
            "python: a leading comment does not stop the module docstring "
            "(comments are not statements)",
            2,
            "docstring",
        ),
    ),
    (
        "py",
        'def f(x):\n    """Doc."""\n    return x\n',
        expect(
            "python: def docstring binds to the declaration without the body",
            2,
            "docstring",
            contains=["def f"],
            not_contains=["return"],
        ),
    ),
    (
        "lua",
        "-- Doubles the input.\nfunction f(x)\n  return x * 2\nend\n",
        expect(
            "lua: a -- comment above a function binds to it",
            1,
            "next-sibling",
            contains=["function f"],
        ),
    ),
    (
        "py",
        'class C:\n    """Doc."""\n    pass\n',
        expect("python: class docstring", 2, "docstring", contains=["class C"]),
    ),
    (
        "py",
        '@deco\ndef f(x):\n    """Doc."""\n    return x\n',
        expect(
            "python: docstring inside a decorated def",
            3,
            "docstring",
            contains=["def f"],
            not_contains=["return"],
        ),
    ),
    (
        "py",
        "# doc comment\n@deco\ndef f(x):\n    return x\n",
        expect(
            "python: comment above a decorator -> decorator and def line, body stripped",
            1,
            "next-sibling",
            contains=["@deco", "def f"],
            not_contains=["return"],
        ),
    ),
    (
        "py",
        'x = 1\n"not a docstring"\ny = 2\n',
        no_docstring_block("python: a non-first string is not a docstring"),
    ),
    (
        "py",
        "MAX = 5  # attempts before giving up\nTIMEOUT = 30\n",
        expect(
            "python: trailing comment binds to its own line",
            1,
            "trailing",
            contains=["MAX"],
            not_contains=["TIMEOUT"],
        ),
    ),
    (
        "py",
        "#!/usr/bin/env python\n# -*- coding: utf-8 -*-\nx = 1\n",
        python_shebang_pragma,
    ),
    ("py", "#!/usr/bin/env python\n# coding: utf-8\nx = 1\n", python_shebang_pragma),
    ("py", "#!/usr/bin/env python\n# coding=utf-8\nx = 1\n", python_shebang_pragma),
    (
        "py",
        b"\xef\xbb\xbf#!/usr/bin/env python\n# -*- coding: utf-8 -*-\nx = 1\n",
        python_shebang_pragma,
    ),
    (
        "c",
        (
            "int g(int);\nint x = g( // note on the call\n    // second note\n"
            "    1);\nint y = 2;\n"
        ),
        c_paren_trailing_split,
    ),
    (
        "py",
        '# Handles decoding: "utf-8" and friends.\nx = 1\n',
        expect(
            "python: a prose comment mentioning decoding is not an encoding pragma",
            1,
            "next-sibling",
            contains=["x = 1"],
        ),
    ),
    (
        "py",
        "x = 1\n# coding: utf-8\ny = 2\n",
        expect(
            "python: a line-2 cookie after code on line 1 is not a pragma",
            2,
            "next-sibling",
            contains=["y = 2"],
        ),
    ),
    (
        "py",
        "x = 1  # coding: utf-8\ny = 2\n",
        expect(
            "python: a trailing cookie after code is not a pragma",
            1,
            "trailing",
            contains=["x = 1"],
        ),
    ),
    (
        "py",
        "# coding: utf-8\n# coding: latin-1\nx = 1\n",
        excluded_first_line(
            "python: only the first cookie is a pragma; the second stays a block",
            1,
            2,
            "next-sibling",
        ),
    ),
    (
        "py",
        '"""Doc."""  # trailing note\n# next comment\nx = 1\n',
        python_docstring_trailing_split,
    ),
    (
        "py",
        's = """\n# workers\n"""\nx = 1\n',
        no_docstring_block(
            "python: comment-shaped lines inside a triple-quoted string are not blocks",
            absent_text="workers",
        ),
    ),
    ("py", 'x = "日本語"  # コメント\n', python_nonascii),
    (
        "py",
        'def f(x):\n    f"not a docstring {x}"\n    return x\n',
        no_docstring_block("python: an f-string first statement is not a docstring"),
    ),
    (
        "py",
        'def f(x):\n    b"not a docstring"\n    return x\n',
        no_docstring_block("python: a bytes first statement is not a docstring"),
    ),
    (
        "py",
        'def f(x):\n    "part one " f"{x}"\n    return x\n',
        no_docstring_block(
            "python: a concatenation containing an f-string is not a docstring"
        ),
    ),
    (
        "rs",
        "#!/usr/bin/env rust\n/// doc\nfn f() {}\n",
        excluded_first_line(
            "rust: a shebang line lands in excluded_lines and the doc still binds",
            1,
            2,
            "next-sibling",
        ),
    ),
    (
        "rs",
        "/// doc\n#[cfg(all(/* nested */ unix))]\nfn f() {}\n",
        expect(
            "rust: a nested comment inside a skipped attribute is stripped",
            1,
            "next-sibling",
            contains=["#[cfg", "fn f"],
            not_contains=["nested"],
        ),
    ),
    (
        "rs",
        "/// Which flavor.\nenum Flavor { Sweet, Sour }\n",
        expect(
            "rust: an enum doc's referent strips the variant list",
            1,
            "next-sibling",
            contains=["enum Flavor"],
            not_contains=["Sweet"],
        ),
    ),
    (
        "py",
        'def f(x):\n    "part one " "part two"\n    return x\n',
        expect(
            "python: an implicitly concatenated docstring is one",
            2,
            "docstring",
            contains=["def f"],
            not_contains=["return"],
        ),
    ),
    (
        "js",
        "#!/usr/bin/env node\n// a note\nconst x = 1;\n",
        excluded_first_line(
            "js: a hash-bang line lands in excluded_lines and the comment still binds",
            1,
            2,
            "next-sibling",
        ),
    ),
    (
        "c",
        "// far comment, binds fine\nint a = 1;\n\nint b = 2\n// near comment\nint c = 3;\n",
        c_error_locality,
    ),
    (
        "c",
        "int x;\nvoid g(void) { f(host, /*port=*/443, 3); }\n",
        expect(
            "c: /*port=*/ as a middle argument binds forward to 443",
            2,
            "forward",
            contains=["443"],
            not_contains=["host"],
        ),
    ),
    (
        "c",
        "int x;\nvoid g(void) { f(/*port=*/443, 3); }\n",
        expect(
            "c: /*port=*/ as the first argument binds forward to 443",
            2,
            "forward",
            contains=["443"],
        ),
    ),
    (
        "c",
        "struct S {\n    int retries;  ///< handshake attempts\n    int timeout;\n};\n",
        expect(
            "c: ///< binds backward to its own line's declaration",
            2,
            "trailing",
            contains=["retries"],
            not_contains=["timeout"],
        ),
    ),
    (
        "cpp",
        "/// Adds one.\nint f(int x) { return x + 1; }\n",
        expect(
            "cpp: a doc comment above a function binds without the body",
            1,
            "next-sibling",
            contains=["int f"],
            not_contains=["return"],
        ),
    ),
    (
        "cpp",
        "int a = 1; // note on a\nint b = 2;\n",
        expect(
            "cpp: trailing comment",
            1,
            "trailing",
            contains=["int a"],
            not_contains=["int b"],
        ),
    ),
    (
        "c",
        "int a = 1; // note on a\nint b = 2;\n",
        expect(
            "c: same-row trailing wins over the adjacent next declaration",
            1,
            "trailing",
            contains=["int a"],
            not_contains=["int b"],
        ),
    ),
    (
        "sh",
        "cat > out.conf <<'EOF'\n# workers\nworkers = 4\nEOF\n",
        no_docstring_block(
            "bash: comment-shaped lines inside a heredoc are not blocks",
            absent_text="workers",
        ),
    ),
    (
        "sh",
        "# checks the guard\nrun_scan missing.md >/dev/null 2>&1\n",
        expect(
            "bash: a redirected command keeps its command words in the referent",
            1,
            "next-sibling",
            contains=["run_scan", "/dev/null"],
        ),
    ),
    (
        "sh",
        "x=1  # trailing note\ny=2\n",
        expect("bash: trailing comment", 1, "trailing"),
    ),
    (
        "js",
        "/** Sorts. */\nexport function sortRows(rows) { return rows.sort(); }\n",
        expect(
            "js: an exported function's doc strips the body like a local one",
            1,
            "next-sibling",
            contains=["export function sortRows"],
            not_contains=["rows.sort"],
        ),
    ),
    (
        "py",
        "@deprecated(\"use parse_config\")\ndef f(x):\n    '''Deprecated: use parse_config.'''\n    return x\n",
        expect(
            "python: a decorated def's docstring referent includes the decorator",
            3,
            "docstring",
            contains=["@deprecated", "def f"],
            not_contains=["return"],
        ),
    ),
    (
        "js",
        "/** Sorts the rows. */\nconst rank = (rows) => [...rows].sort();\n",
        expect(
            "js: an arrow-function binding carries its whole text as referent",
            1,
            "next-sibling",
            contains=["sort"],
        ),
    ),
    (
        "go",
        "package p\n\n// Rank sorts the rows.\nfunc Rank(x int) int { return x }\n",
        expect(
            "go: a bare // run adjacent to a declaration binds to it",
            3,
            "next-sibling",
            contains=["func Rank"],
        ),
    ),
    (
        "go",
        "// separated header\n\npackage p\n",
        expect("go: a blank-line-separated leading run binds to the file", 1, "header"),
    ),
    (
        "go",
        "package p\n\nvar x = 1 // trailing note\n",
        expect("go: trailing comment", 3, "trailing"),
    ),
    (
        "rb",
        "# Doubles the input.\ndef f(x)\n  x * 2\nend\n",
        expect(
            "ruby: a # run above a method binds to it without the body",
            1,
            "next-sibling",
            contains=["def f"],
            not_contains=["x * 2"],
        ),
    ),
    (
        "rb",
        "x = 1  # trailing note\ny = 2\n",
        expect("ruby: trailing comment", 1, "trailing"),
    ),
    (
        "java",
        "class C {\n    /** Adds one. */\n    int f(int x) { return x + 1; }\n}\n",
        expect(
            "java: Javadoc above a method binds to it without the body",
            2,
            "next-sibling",
            contains=["int f"],
            not_contains=["return"],
        ),
    ),
    (
        "java",
        "/** A container. */\nclass C {\n    int f(int x) { return x + 1; }\n}\n",
        expect(
            "java: a class doc's referent strips the class body",
            1,
            "next-sibling",
            contains=["class C"],
            not_contains=["return"],
        ),
    ),
    (
        "java",
        "class C {\n    int a = 1; // trailing note\n    int b = 2;\n}\n",
        expect("java: trailing comment", 2, "trailing"),
    ),
    (
        "java",
        "/** Which flavor. */\nenum Flavor { SWEET, SOUR }\n",
        expect(
            "java: an enum doc's referent strips the enum body",
            1,
            "next-sibling",
            contains=["enum Flavor"],
            not_contains=["SWEET"],
        ),
    ),
    (
        "java",
        (
            "class C {\n    /** Builds a C. */\n    C(int x) { this.x = x; }\n"
            "    int x;\n}\n"
        ),
        expect(
            "java: a constructor doc's referent strips the constructor body",
            2,
            "next-sibling",
            contains=["C(int x)"],
            not_contains=["this.x"],
        ),
    ),
    (
        "cs",
        (
            "class C {\n    /// <summary>Adds one.</summary>\n"
            "    /// <returns>x+1</returns>\n"
            "    int F(int x) { return x + 1; }\n}\n"
        ),
        expect(
            "csharp: a /// XML-doc run above a method binds to it",
            2,
            "next-sibling",
            contains=["int F"],
            end_line=3,
        ),
    ),
    (
        "cs",
        "class C {\n    int a = 1; // trailing note\n    int b = 2;\n}\n",
        expect("csharp: trailing comment", 2, "trailing"),
    ),
    (
        "xml",
        "<!-- a note about the root -->\n<a/>\n",
        expect("xml: an uppercase Comment node type is still a block", 1, "header"),
    ),
    ("py", '# a "quoted" word and a back\\slash\nx = 1\n', json_structural),
    ("py", "# first block\n\n# second block\n", comments_only),
    ("py", "", empty_file),
    (
        "zzz",
        "no grammar here\n",
        unreached_file("unknown extension -> no-grammar", "no-grammar"),
    ),
    ("c", b"\x00\x01\x02", unreached_file("NUL bytes -> binary", "binary")),
    (
        "c",
        "@@@@ $$$$ ~~~~\n",
        unreached_file("all-ERROR text file -> file-level parse-error", "parse-error"),
    ),
]


def verdict_invariant(records):
    """referent is null exactly on a parse-error block; relation is null
    only there — over every block of every specimen."""
    for rec in records:
        for b in rec["blocks"]:
            if (b["referent"] is None) != (b["unreached"] == "parse-error"):
                return False
            if b["relation"] is None and b["unreached"] != "parse-error":
                return False
    return True


def locale_independence(tmp):
    path = os.path.join(tmp, "nonascii_locale.py")
    with open(path, "wb") as fh:
        fh.write("x = 1  # コメント\n".encode())
    env = dict(os.environ, LC_ALL="C", LANG="C")
    proc = subprocess.run(
        COMMAND + [path], capture_output=True, encoding="utf-8", env=env, check=False
    )
    check(
        "cli: non-ASCII output survives a non-UTF-8 locale",
        proc.returncode == 0 and "コメント" in proc.stdout,
        f"rc={proc.returncode} stderr={proc.stderr!r}",
    )


def exit_code_contract(tmp):
    no_args = invoke([])
    check(
        "cli: no arguments -> exit 2 with usage on stderr",
        no_args.returncode == 2 and "usage" in no_args.stderr,
        f"rc={no_args.returncode} stderr={no_args.stderr!r}",
    )
    missing = invoke([os.path.join(tmp, "absent.py")])
    check(
        "cli: a missing path -> exit 2 naming the path",
        missing.returncode == 2 and "absent.py" in missing.stderr,
        f"rc={missing.returncode} stderr={missing.stderr!r}",
    )


def main():
    with tempfile.TemporaryDirectory() as tmp:
        paths = []
        for i, (ext, source, _) in enumerate(SPECIMENS):
            path = os.path.join(tmp, f"specimen_{i:02d}.{ext}")
            data = source if isinstance(source, bytes) else source.encode("utf-8")
            with open(path, "wb") as fh:
                fh.write(data)
            paths.append(path)
        records = run(paths)
        check(
            "output: one JSON Lines record per input file, in order",
            len(records) == len(paths)
            and all(r["path"] == p for r, p in zip(records, paths)),
        )
        check(
            "output: referent/relation nullity tracks parse-error on every block",
            verdict_invariant(records),
        )
        for (ext, source, checker), record in zip(SPECIMENS, records):
            checker(record)
        exit_code_contract(tmp)
        locale_independence(tmp)

    if FAILURES:
        print(f"\n{len(FAILURES)} specimen check(s) failed.")
        return 1
    print("\nAll specimen checks passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
