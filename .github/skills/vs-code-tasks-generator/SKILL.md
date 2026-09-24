# VS Code Tasks Generator

Generate workspace VS Code tasks for every public recipe in the repository's
`justfile`.

## Workflow

1. Read the complete `justfile` before editing anything.
2. Discover recipes and their metadata in source order with:

	```sh
	just --dump --dump-format json
	```

3. Read the `recipes` object from the JSON output and create tasks only for
	recipes whose `private` property is false. Never generate tasks for private
	recipes; they are implementation helpers, not VS Code commands.
4. Create or update `.vscode/tasks.json` using VS Code's `2.0.0` task schema.
	Preserve unrelated existing tasks in that file, but replace the generated
	`just:` tasks so rerunning the generator is idempotent.
5. Generate one task per recipe with this shape:

	```json
	{
	  "label": "just: <recipe>",
	  "type": "shell",
	  "command": "just",
	  "args": ["<recipe>"],
	  "detail": "<recipe doc, when present>",
	  "options": {
		 "cwd": "${workspaceFolder}"
	  },
    "presentation": {
      "echo": true,
      "reveal": "always",
      "focus": true,
      "panel": "dedicated",
      "showReuseMessage": false,
      "clear": true
    },    
	  "problemMatcher": []
	}
	```

	Populate `detail` from the recipe's `doc` property in the `just` dump. If a
	recipe has no documentation, omit `detail` rather than inventing a
	description.

6. Set the `group` to `"build"` only for the `default` recipe. Do not mark
	cluster, authentication, port-forward, or delete recipes as default build
	tasks.
7. Keep the generated tasks in the same order as the `recipes` object in the
	dump output.
8. Validate the result by parsing `.vscode/tasks.json` as JSONC or JSON and by
	checking that every generated task invokes `just` with exactly one recipe
	argument.

Use the VS Code task documentation for the supported schema and task properties:
https://code.visualstudio.com/docs/debugtest/tasks

Do not copy recipe bodies into `tasks.json`; `just` remains the source of truth
for dependencies, environment variables, shell behavior, and multi-line
commands. Do not use `just --summary` as the sole source because it omits
private recipes.
