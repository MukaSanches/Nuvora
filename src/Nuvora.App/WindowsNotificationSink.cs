using Microsoft.Toolkit.Uwp.Notifications;
using Nuvora.Core;

namespace Nuvora.App;

public sealed class WindowsNotificationSink : INotificationSink
{
    public Task PublishAsync(ContentItem item, CancellationToken ct)
    {
        var toast = new ToastContentBuilder().AddText(item.Kind == ContentKind.Live ? "Nuvora • AO VIVO" : $"Nuvora • {item.SourceName}").AddText(item.Title);
        if (!string.IsNullOrWhiteSpace(item.Summary)) toast.AddText(item.Summary.Length > 160 ? item.Summary[..157] + "..." : item.Summary);
        toast.AddArgument("item", item.Id).AddButton(new ToastButton().SetContent("Abrir").AddArgument("url", item.Link.ToString()));
        if (item.Audio is not null) toast.AddButton(new ToastButton().SetContent("Ouvir").AddArgument("audio", item.Audio.ToString()));
        toast.Show(); return Task.CompletedTask;
    }
}
