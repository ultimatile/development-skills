---
name: stage-commit-push
description: Stage changed files, generate a conventional commit message, commit, and push in one step. Used inside automated review-fix loops.
---

# Stage, Commit, Push

One-shot skill for the review-fix loop: stage modified files, generate a commit message, commit, and push.

## Procedure

### 0. Route by working state

Check what there is to do before staging anything. Three states:

- **Changes to commit** — run steps 1 through 4.
- **Nothing to commit, but commits the remote does not have** — skip to step 4. This covers a branch ahead of its upstream and a branch that has no upstream yet; step 4 handles both. Staging nothing and committing nothing fails, and the push is what this invocation is for.
- **Nothing to commit and nothing to push** — report that and stop.

### 1. Stage

```bash
git add <specific files that were modified>
```

Stage only the files you changed. Do NOT use `git add -A` or `git add .` — be explicit about which files are staged. Never stage files that could contain secrets (.env, credentials).

### 2. Generate commit message

Inspect the staged diff and recent commits to produce a conventional commits message.

```bash
git diff --staged
git log --oneline -5
```

**Type selection** — based on what changed and why:

- Documentation only → `docs`
- Build/CI config → `ci` or `build`
- Code style/formatting → `style`
- Tests only → `test`
- Deps/cleanup → `chore`
- Restructuring without behavior change → `refactor`
- New functionality that didn't exist before → `feat`
- Existing functionality that was wrong/broken → `fix`

Size doesn't determine type. API signature changes that correct a mistake are `fix`, not `feat`.

**Title length** — keep the commit title (first line) to 72 characters or fewer. Use the body for details.

**Exclusions** — the message must NOT contain:

- Phase/step numbers ("Phase 1", "Step 2")
- Plan or task references ("As part of...", "Following the plan...")
- Internal implementation context

### 3. Commit

```bash
git commit -m "$(cat <<'EOF'
<title>
<body>
EOF
)"
```

Always use HEREDOC for the message to preserve formatting.

### 4. Push

```bash
git push
```

If the branch has no upstream, use `git push -u origin <branch>`.

### 5. Report

After pushing, show the user:

- The commit hash and message title
- The branch and remote status
