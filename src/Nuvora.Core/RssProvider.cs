using System.Security.Cryptography;
using System.Text;
using System.Xml.Linq;

namespace Nuvora.Core;

public sealed class RssProvider(HttpClient http) : IContentProvider
{
    public string Name => "rss";
    public bool CanHandle(Source source) => source.Provider is "rss" or "podcast" or "podcasting2";

    public async Task<IReadOnlyList<ContentItem>> FetchAsync(FetchContext context, CancellationToken ct)
    {
        using var response = await http.GetAsync(context.Source.Uri, HttpCompletionOption.ResponseHeadersRead, ct);
        response.EnsureSuccessStatusCode();
        await using var stream = await response.Content.ReadAsStreamAsync(ct);
        var doc = await XDocument.LoadAsync(stream, LoadOptions.None, ct);
        var channel = doc.Root?.Element("channel");
        var nodes = channel?.Elements("item") ?? doc.Descendants().Where(x => x.Name.LocalName == "entry");
        return nodes.Select(x => Parse(x, context)).Where(x => x is not null).Cast<ContentItem>()
            .Where(x => x.PublishedAt >= context.Since).OrderByDescending(x => x.PublishedAt).ToArray();
    }

    private static ContentItem? Parse(XElement x, FetchContext c)
    {
        string? Value(string n) => x.Elements().FirstOrDefault(e => e.Name.LocalName == n)?.Value?.Trim();
        var title = Value("title");
        var link = x.Elements().FirstOrDefault(e => e.Name.LocalName == "link")?.Attribute("href")?.Value ?? Value("link");
        var guid = Value("guid") ?? Value("id") ?? link;
        if (string.IsNullOrWhiteSpace(title) || string.IsNullOrWhiteSpace(link) || !Uri.TryCreate(link, UriKind.Absolute, out var uri)) return null;
        var dateText = Value("pubDate") ?? Value("published") ?? Value("updated");
        _ = DateTimeOffset.TryParse(dateText, out var published);
        if (published == default) published = DateTimeOffset.UtcNow;
        var enclosure = x.Elements().FirstOrDefault(e => e.Name.LocalName == "enclosure")?.Attribute("url")?.Value;
        Uri? audio = Uri.TryCreate(enclosure, UriKind.Absolute, out var a) ? a : null;
        var live = x.Name.LocalName.Equals("liveItem", StringComparison.OrdinalIgnoreCase) || x.Ancestors().Any(e => e.Name.LocalName == "liveItem");
        var kind = live ? ContentKind.Live : audio is not null ? ContentKind.Podcast : ContentKind.News;
        var id = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(guid ?? link)));
        return new(id, c.Topic.Id, kind, title, Value("description") ?? Value("summary"), uri, published, c.Source.Name, audio, live);
    }
}
