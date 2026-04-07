# Brownie `.med` syntax highlighting

VS Code extension providing TextMate highlighting for Brownie meditation scripts (`.med`).

## Install (from source)

```
cd tools/vscode-med
code --install-extension .
```

Or press **F5** in VS Code with this folder open to launch an Extension Development Host.

## Highlighted tokens

- **Title line** (first `#` line): `# Morning Reset #calm #focus` — title as heading, trailing `#tag`s as tags
- **Tag lines** (pure `#tag #tag` lines): each word as a tag
- **Comments** (later `#` lines): standard comment
- **Pool definitions**: `~person` at line start
- **Pool references**: inline `~person`, `~why`
- **Gender markers**: `♀` `♂`
- **Gender-neutral pronouns** rewritten at runtime: `they`/`them`/`their`/`theirs`/`themselves`
- **Repeats**: `×5`, `x5`
- **Fermata**: `𝄐`, `|`
- **Dot pauses**: `···`
- **Durations**: `28″`, `28"`, `3′`, `3'`
- **Countdowns**: `⏳12″`

## Verifying scopes

Open a `.med` file and run `Developer: Inspect Editor Tokens and Scopes` from the command palette to see the TextMate scope under the cursor.
