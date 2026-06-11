# Notion MCP Server — Tool Reference

All 22 tools exposed by `@notionhq/notion-mcp-server` v2.2.1. Tools are prefixed `mcp_notion_*` in Hermes.

## Search

### API-post-search
Search Notion by page title.
```json
{"query": "search term"}
```
Returns matching pages, data sources, and other objects.

## Page Operations

### API-retrieve-a-page
Read page metadata (not content).
```json
{"page_id": "uuid"}
```

### API-patch-page
Update page properties (not content blocks).
```json
{"page_id": "uuid", "properties": {"Status": {"select": {"name": "Done"}}}}
```

### API-post-page
Create a new page.
```json
{
  "parent": {"page_id": "uuid"},
  "properties": {"title": [{"text": {"content": "Title"}}]}
}
```

### API-retrieve-a-page-property
Read a single property item (e.g. a relation or rollup).
```json
{"page_id": "uuid", "property_id": "abc"}
```

### API-move-page
Move a page to a different parent.
```json
{"page_id": "uuid", "parent": {"page_id": "new_parent_uuid"}}
```

## Block Operations

### API-get-block-children
Read children of a block (or page root).
```json
{"block_id": "page_or_block_uuid"}
```

### API-patch-block-children
Append blocks as children.
```json
{
  "block_id": "uuid",
  "children": [{"object": "block", "type": "paragraph", "paragraph": {"rich_text": [{"text": {"content": "Hello"}}]}}]
}
```

### API-retrieve-a-block
Read a single block's metadata and content.
```json
{"block_id": "uuid"}
```

### API-update-a-block
Update a single block's content/type.
```json
{"block_id": "uuid", "type": "paragraph", "paragraph": {"rich_text": [{"text": {"content": "Updated"}}]}}
```

### API-delete-a-block
Delete (trash) a block. Returns 204 on success.
```json
{"block_id": "uuid"}
```

## Database / Data Source Operations

### API-query-data-source
Filter and sort a data source (database).
```json
{
  "data_source_id": "uuid",
  "filter": {"property": "Status", "select": {"equals": "Active"}},
  "sorts": [{"property": "Date", "direction": "descending"}]
}
```

### API-retrieve-a-data-source
Get schema, properties, and metadata for a data source.
```json
{"data_source_id": "uuid"}
```

### API-update-a-data-source
Change data source properties or schema.
```json
{
  "data_source_id": "uuid",
  "title": [{"text": {"content": "New Title"}}],
  "properties": {"NewField": {"type": "rich_text"}}
}
```

### API-create-a-data-source
Create a new data source (database).
```json
{
  "parent": {"page_id": "uuid"},
  "title": [{"text": {"content": "My DB"}}],
  "properties": {"Name": {"title": {}}, "Status": {"select": {"options": [{"name": "Todo"}]}}}
}
```

### API-list-data-source-templates
List available templates in a data source.
```json
{"data_source_id": "uuid"}
```

### API-retrieve-a-database
Get database metadata including data_source_id mapping (v2 migration bridge).
```json
{"database_id": "uuid"}
```

## User Operations

### API-get-user
Retrieve a single user.
```json
{"user_id": "uuid"}
```

### API-get-users
List all users in the workspace.
```json
{}
```

### API-get-self
Retrieve the bot user associated with the integration token.
```json
{}
```

## Comments

### API-retrieve-a-comment
Retrieve comments on a page or discussion thread.
```json
{"block_id": "page_or_block_uuid"}
```

### API-create-a-comment
Add a comment to a page or reply to a thread.
```json
{
  "parent": {"page_id": "uuid"},
  "rich_text": [{"text": {"content": "Great work!"}}]
}
```

## Notes

- All page/block/property IDs are UUIDs (with or without dashes).
- The MCP server maps directly to the Notion API v2025-09-03.
- Tool errors are returned as structured JSON with `status`, `code`, and `message` fields.
- Database write tools (create/update data source, update page properties) require the integration to have write capabilities in Notion.
- 401 responses mean the `NOTION_API_KEY` env var wasn't available to the server process — check the wrapper script.
