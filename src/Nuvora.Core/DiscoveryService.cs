using System.Net.Http.Json;
using System.Text.Json.Serialization;

namespace Nuvora.Core;

public sealed record DiscoverySource(string Name, string Category, Uri Feed, string Provider = "rss");
public sealed record PodcastSearchResult(string Name, string Author, Uri Feed, Uri? Artwork);

public sealed class DiscoveryService(HttpClient http)
{
    // Catálogo inicial deliberadamente PT-BR. Fontes em inglês foram removidas.
    public static IReadOnlyList<DiscoverySource> BrazilianNews { get; } = new DiscoverySource[]
    {
        new("Agência Brasil", "Brasil", new("https://agenciabrasil.ebc.com.br/rss/ultimasnoticias/feed.xml")),
        new("Agência Senado", "Política", new("https://www12.senado.leg.br/noticias/rss/")),
        new("BBC News Brasil", "Brasil e mundo", new("https://feeds.bbci.co.uk/portuguese/rss.xml")),
        new("CNN Brasil", "Notícias", new("https://www.cnnbrasil.com.br/rss/")),
        new("Folha de S.Paulo", "Notícias", new("https://feeds.folha.uol.com.br/emcimadahora/rss091.xml")),
        new("Folha — Poder", "Política", new("https://feeds.folha.uol.com.br/poder/rss091.xml")),
        new("Folha — Cotidiano", "Cotidiano", new("https://feeds.folha.uol.com.br/cotidiano/rss091.xml")),
        new("G1 — São Paulo", "São Paulo", new("https://g1.globo.com/dynamo/sp/sao-paulo/rss2.xml")),
        new("G1 — Política", "Política", new("https://g1.globo.com/dynamo/politica/rss2.xml")),
        new("Jovem Pan", "Notícias", new("https://jovempan.com.br/feed")),
        new("Poder360", "Política", new("https://www.poder360.com.br/feed/")),
        new("CartaCapital", "Notícias", new("https://www.cartacapital.com.br/feed/")),
        new("O Antagonista", "Política", new("https://www.oantagonista.com/feed/")),
        new("Revista Piauí", "Revista", new("https://piaui.folha.uol.com.br/feed/")),
        new("Revista Oeste", "Notícias", new("https://revistaoeste.com/feed/")),
        new("Jornal de Brasília", "Notícias", new("https://jornaldebrasilia.com.br/feed/")),
        new("Tecnoblog", "Tecnologia", new("https://tecnoblog.net/feed/")),
        new("Exame", "Economia", new("https://exame.com/feed/"))
    };

    // Podcasts brasileiros com RSS público conhecido e episódios de áudio.
    // Esta base garante conteúdo reproduzível mesmo se a descoberta externa falhar.
    public static IReadOnlyList<DiscoverySource> BrazilianPodcasts { get; } = new DiscoverySource[]
    {
        new("Flow Podcast", "Podcasts", new("https://anchor.fm/s/a5637400/podcast/rss"), "podcast")
    };

    public async Task<IReadOnlyList<PodcastSearchResult>> SearchBrazilianPodcastsAsync(string query, int limit = 100, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(query)) query = "podcast brasil";
        limit = Math.Clamp(limit, 1, 200);
        var url = $"https://itunes.apple.com/search?term={Uri.EscapeDataString(query)}&country=BR&lang=pt_br&media=podcast&entity=podcast&limit={limit}";
        var result = await http.GetFromJsonAsync<AppleSearchResponse>(url, cancellationToken: ct);
        return (result?.Results ?? [])
            .Where(x => Uri.TryCreate(x.FeedUrl, UriKind.Absolute, out _))
            .Where(x => IsPortugueseBrazil(x.Country, x.PrimaryGenreName, x.CollectionName, x.ArtistName))
            .Select(x => new PodcastSearchResult(x.CollectionName ?? "Podcast", x.ArtistName ?? "", new Uri(x.FeedUrl!), Uri.TryCreate(x.ArtworkUrl600, UriKind.Absolute, out var art) ? art : null))
            .DistinctBy(x => x.Feed)
            .ToArray();
    }

    private static bool IsPortugueseBrazil(string? country, string? genre, string? name, string? author)
    {
        // A storefront BR já é o filtro principal. Rejeitamos explicitamente resultados marcados para outro país.
        return string.IsNullOrWhiteSpace(country) || country.Equals("BRA", StringComparison.OrdinalIgnoreCase) || country.Equals("BR", StringComparison.OrdinalIgnoreCase);
    }

    private sealed class AppleSearchResponse { [JsonPropertyName("results")] public List<ApplePodcast> Results { get; set; } = []; }
    private sealed class ApplePodcast
    {
        [JsonPropertyName("collectionName")] public string? CollectionName { get; set; }
        [JsonPropertyName("artistName")] public string? ArtistName { get; set; }
        [JsonPropertyName("feedUrl")] public string? FeedUrl { get; set; }
        [JsonPropertyName("artworkUrl600")] public string? ArtworkUrl600 { get; set; }
        [JsonPropertyName("country")] public string? Country { get; set; }
        [JsonPropertyName("primaryGenreName")] public string? PrimaryGenreName { get; set; }
    }
}
