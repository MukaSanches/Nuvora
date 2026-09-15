namespace Nuvora.Core;

public enum ContentKind { News, Podcast, Live, Release, WebChange }
public enum DeliveryMode { Immediate, Digest, Scheduled }

public sealed record Topic(Guid Id, string Name, TimeSpan PollInterval, DeliveryMode Delivery, bool Enabled = true);
public sealed record Source(Guid Id, Guid TopicId, string Name, Uri Uri, string Provider, bool Enabled = true);
public sealed record ContentItem(string Id, Guid TopicId, ContentKind Kind, string Title, string? Summary, Uri Link, DateTimeOffset PublishedAt, string SourceName, Uri? Audio = null, bool IsLive = false);
public sealed record PlaybackState(string ItemId, TimeSpan Position, TimeSpan? Duration, bool Completed, DateTimeOffset UpdatedAt);
public sealed record FetchContext(Topic Topic, Source Source, DateTimeOffset Since);

public interface IContentProvider
{
    string Name { get; }
    bool CanHandle(Source source);
    Task<IReadOnlyList<ContentItem>> FetchAsync(FetchContext context, CancellationToken cancellationToken);
}

public interface IContentStore
{
    Task InitializeAsync(CancellationToken ct);
    Task<bool> TryAddAsync(ContentItem item, CancellationToken ct);
    Task<IReadOnlyList<ContentItem>> LatestAsync(int limit, CancellationToken ct);
}

public interface INotificationSink { Task PublishAsync(ContentItem item, CancellationToken ct); }
