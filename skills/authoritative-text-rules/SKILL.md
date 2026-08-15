---
name: authoritative-text-rules
description: Single source of truth for audit items covering text that an agent executes as instructions. Definitions live in items/<slug>.md; audit skills reference items by slug.
---

# Authoritative Text Rules (SSOT)

This skill is **a definition file, not a runnable procedure**. Skills that audit authoritative text apply these items by reference. When an item changes, referencing skills pick up the change automatically. A runner may carry a compressed mnemonic of an item, but never the item's full trigger, sweep, concern conditions, or N/A criterion — that copied detail is the manual-synchronization surface this rule removes — and the mnemonic is never the authority. The Items index below is the single source of truth for **which items exist**: runners derive their active item set by reading this index, never by hardcoding a parallel slug list.

## Scope

**Authoritative text** is text an agent executes as instructions. That single property decides membership, and a file it holds for qualifies in full — a body that also describes a separate artifact, a wrapped script or a co-located rule table, is still audited whole as instructions.

A claim in a qualifying file that describes a separate artifact has a referent, and checking the claim against that referent belongs to claim-vs-referent items outside this rule set, on their own triggers. The items here still read such a claim on their own terms — `case-space-totality`'s sweep checks a proposition an enumeration relies on against the domain itself.

Skill bodies — script-wrapping ones included — rule and item definition files, and repository-level agent-instruction files (`CLAUDE.md`, `AGENTS.md`, files under `.claude/rules/`, `.claude/commands/`, `.claude/agents/`, and the equivalents other tools define) are the recurring instances. The list is illustrative: the property above decides membership, and new instruction-file conventions appear faster than any enumeration tracks.

Source code is not authoritative text: a machine executes it. Prose that is read rather than executed — a README, an article, a design document, a docstring — is not authoritative text either; a docstring's claims are checked against the code they describe by claim-vs-referent items, not by anything here.

**Classify per file, not per directory.** A skill directory can hold a skill body beside a package manifest, a lockfile, and scripts; the body is authoritative text and the rest is not.

**A diff can carry both kinds.** When it does, this rule set and the code-quality rule set the runner already applies both bind it in full — the classification is the set of surfaces present, not a partition. A change whose substance is code keeps its ordinary audit unchanged and gains these items for whatever authoritative text it also touches.

## Ownership boundary

A statement left stranded by a qualification the diff introduces — a caveat that makes a previously unconditional documented behavior conditional, while the same behavior stays stated unconditionally elsewhere — belongs to `quality-list`'s `paired-artifact-drift` item and its Qualification completeness sweep. No item here takes that case.

## Items

Items carry no lane tag: every judgment below is available from the literal text of the audited files and the files they reference, so a runner splitting work between a fresh-context subagent and main context may send any item to either. A runner selects **every** item in this index whenever the rule set is active.

- [case-space-totality](items/case-space-totality.md)
- [single-reading](items/single-reading.md)
- [clause-composition](items/clause-composition.md)
- [executor-fitness](items/executor-fitness.md)
- [consumer-closure](items/consumer-closure.md)
