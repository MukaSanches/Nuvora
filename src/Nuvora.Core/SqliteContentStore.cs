using Microsoft.Data.Sqlite;

namespace Nuvora.Core;

public sealed class SqliteContentStore(string connectionString) : IContentStore
{
    public async Task InitializeAsync(CancellationToken ct)
    {
        await using var db = new SqliteConnection(connectionString); await db.OpenAsync(ct);
        var cmd = db.CreateCommand();
        cmd.CommandText = """
        CREATE TABLE IF NOT EXISTS content(id TEXT PRIMARY KEY, topic TEXT NOT NULL, kind INTEGER NOT NULL, title TEXT NOT NULL, summary TEXT, link TEXT NOT NULL, published TEXT NOT NULL, source TEXT NOT NULL, audio TEXT, live INTEGER NOT NULL);
        CREATE INDEX IF NOT EXISTS ix_content_published ON content(published DESC);
        """;
        await cmd.ExecuteNonQueryAsync(ct);
    }

    public async Task<bool> TryAddAsync(ContentItem i, CancellationToken ct)
    {
        await using var db = new SqliteConnection(connectionString); await db.OpenAsync(ct);
        var cmd = db.CreateCommand();
        cmd.CommandText = "INSERT OR IGNORE INTO content VALUES($id,$topic,$kind,$title,$summary,$link,$published,$source,$audio,$live)";
        cmd.Parameters.AddWithValue("$id", i.Id); cmd.Parameters.AddWithValue("$topic", i.TopicId.ToString()); cmd.Parameters.AddWithValue("$kind", (int)i.Kind);
        cmd.Parameters.AddWithValue("$title", i.Title); cmd.Parameters.AddWithValue("$summary", (object?)i.Summary ?? DBNull.Value); cmd.Parameters.AddWithValue("$link", i.Link.ToString());
        cmd.Parameters.AddWithValue("$published", i.PublishedAt.ToString("O")); cmd.Parameters.AddWithValue("$source", i.SourceName); cmd.Parameters.AddWithValue("$audio", (object?)i.Audio?.ToString() ?? DBNull.Value); cmd.Parameters.AddWithValue("$live", i.IsLive ? 1 : 0);
        return await cmd.ExecuteNonQueryAsync(ct) == 1;
    }

    public async Task<IReadOnlyList<ContentItem>> LatestAsync(int limit, CancellationToken ct)
    {
        var result = new List<ContentItem>(); await using var db = new SqliteConnection(connectionString); await db.OpenAsync(ct);
        var cmd = db.CreateCommand(); cmd.CommandText = "SELECT * FROM content ORDER BY published DESC LIMIT $limit"; cmd.Parameters.AddWithValue("$limit", limit);
        await using var r = await cmd.ExecuteReaderAsync(ct);
        while (await r.ReadAsync(ct)) result.Add(new(r.GetString(0), Guid.Parse(r.GetString(1)), (ContentKind)r.GetInt32(2), r.GetString(3), r.IsDBNull(4)?null:r.GetString(4), new(r.GetString(5)), DateTimeOffset.Parse(r.GetString(6)), r.GetString(7), r.IsDBNull(8)?null:new Uri(r.GetString(8)), r.GetInt32(9)==1));
        return result;
    }
}
