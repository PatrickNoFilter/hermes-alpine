# Dead Plugin Entries in Hermes Config

Sometimes Hermes config accumulates `plugins.enabled` entries that reference non-existent plugins. This causes no errors (Hermes silently ignores them), but it's dead config that makes inventory audits misleading.

## Detection

```bash
# List all enabled plugin names from config
grep -A10 '^plugins:' ~/.hermes/config.yaml | grep -E '^\s+- ' | sed 's/^\s*-\s*//'

# Check if each has an actual plugin directory
for plugin in $(grep -A10 '^plugins:' ~/.hermes/config.yaml | grep -E '^\s+- ' | sed 's/^\s*-\s*//'); do
  path="/usr/local/lib/hermes-agent/plugins/$plugin"
  if [ -d "$path" ]; then
    echo "  ✅ $plugin → $path"
  else
    echo "  ❌ $plugin → NOT FOUND (zombie entry)"
  fi
done
```

## Cleanup

Remove the zombie line(s) from `~/.hermes/config.yaml`:

```bash
sed -i '/- <dead-plugin-name>/d' ~/.hermes/config.yaml
```

Then verify the YAML is still valid and restart Hermes.

## Example

This session found `rtk-rewrite` in `plugins.enabled` but no corresponding directory at `/usr/local/lib/hermes-agent/plugins/rtk-rewrite/`. RTK is actually a standalone Rust CLI at `/root/.local/bin/rtk` — not a Hermes plugin. The entry was removed.
