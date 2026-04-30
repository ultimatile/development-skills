---
name: done-check
description: >
  Walk through the universal quality items defined in `quality-list` and
  self-assess whether the current diff satisfies each, before declaring a
  task complete or before requesting external review. Use this skill when
  the user says "done check", "ready to commit", "are we done?", "done?",
  or asks to verify whether universal quality rules are being followed
  before claiming completion. Single-pass audit — runs once per invocation.
---

# Done-Check

Post-hoc audit against the current diff. Item definitions live in
`quality-list`; this skill is the **runner**. Update `quality-list`,
not this file, when adding or modifying items.

## Procedure

1. **Identify the diff under audit.** Cover all four sources so
   recently-added implementation files are not missed:

   ```bash
   git log --oneline @{upstream}..HEAD                       # committed
   git diff @{upstream}..HEAD                                # committed content
   git diff --cached                                         # staged
   git diff                                                  # unstaged
   git ls-files --others --exclude-standard                  # untracked paths
   ```

   Read the contents of any untracked file relevant to the audit
   (paths alone do not let you check anything).

2. **Read `quality-list`** and process every item against the diff.
   Mark each as:

   - **✅ pass** — confidently satisfied; the **Evidence** cell records
     what makes you confident (a command run, a manual check, a
     `file:line` read, or `not run: <reason>`)
   - **⚠ concern** — cite the diff location and what to fix
   - **⊘ N/A** — state why the rule does not apply (using the item's
     own N/A criterion)

3. If any **⚠** remains, fix before proceeding. State concretely what
   will change. Do not proceed until concerns are resolved or the user
   explicitly waives them with reasoning.

4. Report the audit table.

## Output format

```
self-audit: <commit-range or "uncommitted">

| #  | Item                              | Result | Evidence                                | Note                                           |
|----|-----------------------------------|--------|-----------------------------------------|------------------------------------------------|
| 1  | Invariant derivation              | ⚠      | read: src/foo.rs:42                     | <what's wrong / what to fix>                   |
| 2  | Purpose verification              | ✅     | manual: ran example with input X        |                                                |
| 3  | Pattern audit                     | ✅     | re-derived f32 path; sibling f64 ok     |                                                |
| 4  | Scope discipline                  | ⊘ N/A  |                                         | no findings dismissed                          |
| 5  | Behavior coverage                 | ✅     | cargo test (incl. error_path tests)     |                                                |
| 6  | Implementation guards             | ⚠      | read: src/foo.rs:120                    | new invariant only commented, no assert        |
| 7  | Impact / caller verification      | ⊘ N/A  |                                         | no public symbol changed                       |
| 8  | Test execution                    | ✅     | cargo test: 84 passed, 0 failed         |                                                |
| 9  | Completion hygiene                | ✅     | cargo clippy clean, cargo fmt --check   |                                                |
| 10 | Architectural boundary            | ⊘ N/A  |                                         | no new imports / dep edges / pub widening      |
| 11 | Textual / paired-artifact drift   | ✅     | rg <old-name>; parent //! re-read       |                                                |
| 12 | Discovery surfacing               | ⊘ N/A  |                                         | no plan exists                                 |
```

Item numbering and titles must follow `quality-list` exactly. If the
list grows or shrinks, update the table accordingly — the table is
generated from the list, not maintained independently.

If any ⚠ remains, fix before proceeding. State concretely what will
change. Do not proceed until concerns are resolved or the user
explicitly waives them with reasoning.
