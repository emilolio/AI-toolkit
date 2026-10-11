#!/usr/bin/env bash
# Scaffolds or extends a Claude Code plugin-marketplace repo.
#
# Usage:
#   scaffold.sh init [--name NAME] [--owner OWNER] [TARGET_DIR]
#       Create .claude-plugin/marketplace.json, plugins/, README.md and .gitignore in TARGET_DIR
#       (default: current directory). Existing files are left untouched.
#   scaffold.sh add-plugin PLUGIN_NAME [--desc TEXT] [TARGET_DIR]
#       Create plugins/PLUGIN_NAME/ with a manifest and an example skill, and register it in
#       marketplace.json. Fails if the plugin already exists.
#   scaffold.sh add-skill PLUGIN_NAME SKILL_NAME [--desc TEXT] [TARGET_DIR]
#       Create plugins/PLUGIN_NAME/skills/SKILL_NAME/SKILL.md with a frontmatter template.
#   scaffold.sh register PLUGIN_NAME [--desc TEXT] [TARGET_DIR]
#       Register an existing plugins/PLUGIN_NAME in marketplace.json (idempotent).
#   scaffold.sh status [TARGET_DIR]
#       Show marketplace name, registered plugins, and unregistered plugin dirs.
set -euo pipefail

cmd="${1:-}"; shift || true
NAME=""; OWNER=""; DESC=""; TARGET=""; POS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --name) NAME="$2"; shift 2 ;;
    --owner) OWNER="$2"; shift 2 ;;
    --desc) DESC="$2"; shift 2 ;;
    -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
    *) POS+=("$1"); shift ;;
  esac
done

need_py() { command -v python3 >/dev/null || { echo "python3 is required"; exit 1; }; }
valid_name() { [[ "$1" =~ ^[a-z0-9][a-z0-9-]*$ ]] || { echo "invalid name '$1': use lowercase letters, digits and hyphens"; exit 1; }; }

case "$cmd" in
  init)
    TARGET="${POS[0]:-$PWD}"; mkdir -p "$TARGET"; TARGET="$(cd "$TARGET" && pwd)"
    OWNER="${OWNER:-${GIT_AUTHOR_NAME:-$(git config user.name 2>/dev/null || echo "Your name")}}"
    mkdir -p "$TARGET/.claude-plugin" "$TARGET/plugins"
    M="$TARGET/.claude-plugin/marketplace.json"
    if [ -f "$M" ]; then echo "keep    .claude-plugin/marketplace.json (exists)"; NAME="${NAME:-$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["name"])' "$M")}"; else
      NAME="${NAME:-$(basename "$TARGET")}"; valid_name "$NAME"
      need_py; python3 - "$M" "$NAME" "$OWNER" <<'EOF'
import json,sys
p,name,owner=sys.argv[1:]
json.dump({"name":name,"description":"Personal Claude Code plugins: reusable skills, rules and commands.",
           "owner":{"name":owner},"plugins":[]},open(p,"w"),indent=2); open(p,"a").write("\n")
EOF
      echo "create  .claude-plugin/marketplace.json (name: $NAME, owner: $OWNER)"; fi
    if [ -f "$TARGET/README.md" ]; then echo "keep    README.md (exists)"; else
      cat > "$TARGET/README.md" <<EOF
# $NAME

A Claude Code plugin marketplace. Each directory under \`plugins/\` is a plugin (a \`.claude-plugin/plugin.json\` manifest plus \`skills/\`, \`agents/\`, \`hooks/\` as needed); \`.claude-plugin/marketplace.json\` registers them.

## Use

\`\`\`
/plugin marketplace add <github-user>/$NAME
/plugin install <plugin-name>@$NAME
\`\`\`

or from the shell: \`claude plugin install <plugin-name>@$NAME --scope project\`.

Try a plugin without installing: \`claude --plugin-dir ./plugins/<plugin-name>\`.

## Add a plugin

1. Create \`plugins/<name>/.claude-plugin/plugin.json\` and \`plugins/<name>/skills/<skill>/SKILL.md\`.
2. Register it in \`.claude-plugin/marketplace.json\` (name, source \`./plugins/<name>\`, description).
3. Validate: \`claude plugin validate ./plugins/<name>\`.
4. Bump the plugin's \`version\` whenever its contents change, so installed copies update.

## Plugins

(listed in \`.claude-plugin/marketplace.json\`)
EOF
      echo "create  README.md"; fi
    if [ -f "$TARGET/.gitignore" ]; then echo "keep    .gitignore (exists)"; else printf '.DS_Store\n*.bak\n__pycache__/\n' > "$TARGET/.gitignore"; echo "create  .gitignore"; fi
    [ -d "$TARGET/.git" ] || echo "note    not a git repo yet: run 'git init' in $TARGET when ready"
    ;;

  add-plugin)
    PNAME="${POS[0]:-}"; [ -n "$PNAME" ] || { echo "plugin name required"; exit 1; }; valid_name "$PNAME"
    TARGET="$(cd "${POS[1]:-$PWD}" && pwd)"
    P="$TARGET/plugins/$PNAME"
    [ -d "$P" ] && { echo "plugins/$PNAME already exists"; exit 1; }
    mkdir -p "$P/.claude-plugin" "$P/skills/example-skill"
    need_py; python3 - "$P/.claude-plugin/plugin.json" "$PNAME" "${DESC:-Describe what this plugin is for.}" <<'EOF'
import json,sys
p,name,desc=sys.argv[1:]
json.dump({"name":name,"version":"0.1.0","description":desc,"author":{"name":"Your name"}},open(p,"w"),indent=2); open(p,"a").write("\n")
EOF
    cat > "$P/skills/example-skill/SKILL.md" <<'EOF'
---
name: example-skill
description: Replace this with a third-person description naming the concrete situations and trigger words in which this skill should be used, and when it should not.
---

# Example skill

Replace with the procedure. State actions directly, explain the why for non-obvious rules, keep
this file under ~500 lines, and move deeper material into `references/` files linked from here.
Scripts under `scripts/` are run, not read; say which.
EOF
    echo "create  plugins/$PNAME/ (manifest + skills/example-skill)"
    "$0" register "$PNAME" --desc "${DESC:-Describe what this plugin is for.}" "$TARGET"
    ;;

  add-skill)
    PNAME="${POS[0]:-}"; SNAME="${POS[1]:-}"; [ -n "$PNAME" ] && [ -n "$SNAME" ] || { echo "plugin and skill names required"; exit 1; }
    valid_name "$PNAME"; valid_name "$SNAME"
    TARGET="$(cd "${POS[2]:-$PWD}" && pwd)"
    S="$TARGET/plugins/$PNAME/skills/$SNAME"
    [ -d "$TARGET/plugins/$PNAME" ] || { echo "plugins/$PNAME does not exist (use add-plugin first)"; exit 1; }
    [ -e "$S/SKILL.md" ] && { echo "$S/SKILL.md already exists"; exit 1; }
    mkdir -p "$S"
    printf -- '---\nname: %s\ndescription: %s\n---\n\n# %s\n\nReplace with the procedure.\n' "$SNAME" "${DESC:-Third-person description with concrete trigger terms and when not to use it.}" "$SNAME" > "$S/SKILL.md"
    echo "create  plugins/$PNAME/skills/$SNAME/SKILL.md"
    ;;

  register)
    PNAME="${POS[0]:-}"; [ -n "$PNAME" ] || { echo "plugin name required"; exit 1; }
    TARGET="$(cd "${POS[1]:-$PWD}" && pwd)"
    M="$TARGET/.claude-plugin/marketplace.json"; [ -f "$M" ] || { echo "no marketplace.json; run init first"; exit 1; }
    [ -d "$TARGET/plugins/$PNAME" ] || { echo "plugins/$PNAME does not exist"; exit 1; }
    need_py; python3 - "$M" "$PNAME" "$DESC" <<'EOF'
import json,sys
p,name,desc=sys.argv[1:]
m=json.load(open(p))
for e in m["plugins"]:
    if e["name"]==name:
        if desc: e["description"]=desc
        print(f"ok      {name} already registered"); break
else:
    m["plugins"].append({"name":name,"source":f"./plugins/{name}","description":desc or ""})
    print(f"update  marketplace.json: registered {name}")
json.dump(m,open(p,"w"),indent=2); open(p,"a").write("\n")
EOF
    ;;

  status)
    TARGET="$(cd "${POS[0]:-$PWD}" && pwd)"
    M="$TARGET/.claude-plugin/marketplace.json"; [ -f "$M" ] || { echo "no marketplace.json in $TARGET"; exit 1; }
    need_py; python3 - "$M" "$TARGET" <<'EOF'
import json,sys,os
m=json.load(open(sys.argv[1])); root=sys.argv[2]
print(f"marketplace: {m['name']}  (owner: {m.get('owner',{}).get('name','?')})")
reg={e['name'] for e in m['plugins']}
for e in m['plugins']:
    src=os.path.join(root,e['source']); ok=os.path.isfile(os.path.join(src,'.claude-plugin','plugin.json'))
    print(f"  {'ok ' if ok else 'MISSING'} {e['name']:24s} {e['source']}")
pd=os.path.join(root,'plugins')
if os.path.isdir(pd):
    for d in sorted(os.listdir(pd)):
        if os.path.isdir(os.path.join(pd,d)) and d not in reg: print(f"  unregistered plugin dir: plugins/{d}  (run: scaffold.sh register {d})")
EOF
    ;;
  *) sed -n '2,17p' "$0"; exit 1 ;;
esac
