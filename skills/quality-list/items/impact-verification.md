# Impact / caller verification [mechanical]

If the change has a planned impact list (from research or design notes), verify it against the actual diff:

- Every caller listed as affected has been updated (gap = missed impact)
- No caller has been modified that wasn't in the impact list (gap = scope creep)

When no formal impact list exists, manually trace the public symbol's callers and confirm each remains consistent with the change.

**Concern conditions:**

- A listed caller was not updated
- A caller was updated but is not in the impact list (or the deviation is not justified)
- Public symbol changed but no caller trace was performed

**N/A:** the change touches no symbol with cross-module callers (internal helper with single use site, isolated test, etc.).
