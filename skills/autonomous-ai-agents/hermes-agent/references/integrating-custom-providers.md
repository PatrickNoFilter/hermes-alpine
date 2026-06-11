# Integrating Custom/Local Providers with Hermes

Hermes supports custom endpoints and local LLM routers/proxies through its flexible provider configuration system.

## Quick Start

To add a custom provider like 9router, Ollama, or a local proxy:

```bash
# Add provider entry (preferred method)
hermes config set providers.myprovider.base_url http://localhost:PORT/v1
hermes config set providers.myprovider.api_key sk-you...ummy
```

## Configuration Details

When adding a custom provider, you can set:

- `base_url`: The base URL of your custom endpoint (must include /v1 for OpenAI-compatible APIs)
- `api_key`: Your API key (can be dummy for local routers that don't require auth)
- `api_mode`: Usually `chat_completions` for OpenAI-compatible endpoints
- Optional: `context_length`, `rate_limit_delay`, `models` dict, etc.

## Example: 9router Integration

For a local 9router instance running on port 20128:

```bash
hermes config set providers.9router.base_url http://127.0.0.1:20128/v1
hermes config set providers.9router.api_key sk-9router
```

## Testing Your Custom Provider

After configuration, test with:

```bash
hermes -m your-model-name --provider your-provider-name -z "Say hello"
```

## Troubleshooting

- **Connection refused**: Verify your custom service is running and accessible at the specified URL
- **Authentication errors**: Check your api_key setting - some local routers accept any key
- **Model not found**: Ensure your custom provider actually serves the model you're requesting
- **Format mismatches**: Some local proxies may require specific `api_mode` settings

## Security Note

Direct edits to `~/.hermes/config.yaml` are blocked for security reasons. Always use `hermes config set` to modify provider configurations.

## Related Configuration

You may also want to adjust:
- Fallback provider chains
- Tool-specific provider overrides (in auxiliary section)
- Delegation provider for subagents

For more information, see the [Providers guide](https://hermes-agent.nousresearch.com/docs/integrations/providers).