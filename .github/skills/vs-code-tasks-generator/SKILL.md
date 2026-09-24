---
name: vs-code-tasks-generator
description: Generates .vscode/tasks.json entries from public justfile recipes, including recipe documentation and VS Code task settings. Use when creating or refreshing VS Code tasks for a just-based workspace.
---

# Generate VS Code Tasks

Generate workspace tasks from the repository's `justfile`.

## Workflow

1. Read the complete `justfile`.
2. Read recipe metadata in declaration order:

   ```sh
   just --dump --dump-format json
   ```

3. From the dump's `recipes` object, include only recipes where `private` is
   false and the name is not `default`.
4. Create or update `.vscode/tasks.json` using schema version `2.0.0`.
   Preserve unrelated tasks and replace only the generated recipe tasks so the
   operation is idempotent.
5. Generate one task per included recipe:
   - `label`: recipe name
   - `type`: `shell`
   - `command`: `just`
   - `args`: one item containing the recipe name
   - `detail`: recipe `doc`, when non-empty
   - `options.cwd`: `${workspaceFolder}`
   - `presentation`: `echo: true`, `reveal: always`, `focus: true`,
     `panel: dedicated`, `showReuseMessage: false`, `clear: true`
   - `problemMatcher`: `[]`

   Omit `detail` when the recipe has no documentation. Do not add a `group`.

6. Keep generated tasks in the same order as the dump's `recipes` object.
7. Validate `.vscode/tasks.json` as JSON or JSONC. Confirm that every generated
   task has a unique recipe label, invokes `just` with exactly one matching
   argument, and excludes private and `default` recipes.

Do not copy recipe bodies into `tasks.json`; `just` remains the source of truth
for dependencies, environment variables, shell behavior, and multi-line
commands. Use the VS Code task documentation for schema details:
https://code.visualstudio.com/docs/debugtest/tasks
