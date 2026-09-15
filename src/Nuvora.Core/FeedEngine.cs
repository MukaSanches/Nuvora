namespace Nuvora.Core;

public sealed class FeedEngine(IEnumerable<IContentProvider> providers, IContentStore store, INotificationSink notifications)
{
    private readonly IContentProvider[] _providers = providers.ToArray();

    public async Task<int> RefreshAsync(IEnumerable<Topic> topics, IEnumerable<Source> sources, CancellationToken ct)
    {
        var topicMap = topics.Where(t => t.Enabled).ToDictionary(t => t.Id);
        var added = 0;
        foreach (var source in sources.Where(s => s.Enabled))
        {
            if (!topicMap.TryGetValue(source.TopicId, out var topic)) continue;
            var provider = _providers.FirstOrDefault(p => p.CanHandle(source));
            if (provider is null) throw new InvalidOperationException($"Nenhum provedor consegue abrir a fonte '{source.Name}'.");

            // Import a useful initial history. PollInterval is for future refresh cadence,
            // not a limit that should make a newly-added feed look empty.
            var since = DateTimeOffset.UtcNow - TimeSpan.FromDays(30);
            var items = await provider.FetchAsync(new(topic, source, since), ct);

            foreach (var item in items)
            {
                if (!await store.TryAddAsync(item, ct)) continue;
                added++;
                if (topic.Delivery == DeliveryMode.Immediate)
                    await notifications.PublishAsync(item, ct);
            }
        }
        return added;
    }
}
