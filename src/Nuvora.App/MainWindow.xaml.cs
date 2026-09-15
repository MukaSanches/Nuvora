using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Windows;
using System.Windows.Input;
using Nuvora.Core;

namespace Nuvora.App;

public partial class MainWindow : Window
{
    private readonly FeedEngine _engine; private readonly IContentStore _store;
    private readonly ObservableCollection<ContentItem> _items = []; private readonly List<Topic> _topics = []; private readonly List<Source> _sources = [];
    private bool _playing;
    public MainWindow(FeedEngine engine, IContentStore store) { InitializeComponent(); _engine = engine; _store = store; Items.ItemsSource = _items; Loaded += async (_,_) => await ReloadAsync(); }

    private async void Add_Click(object sender, RoutedEventArgs e)
    {
        if (!Uri.TryCreate(FeedUrl.Text.Trim(), UriKind.Absolute, out var uri) || uri.Scheme is not ("https" or "http")) { MessageBox.Show("Informe uma URL RSS/Atom válida."); return; }
        var topic = new Topic(Guid.NewGuid(), "Minha assinatura", TimeSpan.FromHours(1), DeliveryMode.Immediate); _topics.Add(topic);
        _sources.Add(new(Guid.NewGuid(), topic.Id, uri.Host, uri, "podcasting2"));
        try { await _engine.RefreshAsync(_topics, _sources, CancellationToken.None); await ReloadAsync(); FeedUrl.Clear(); }
        catch (Exception ex) { MessageBox.Show($"Não foi possível atualizar o feed: {ex.Message}"); }
    }
    private async Task ReloadAsync() { _items.Clear(); foreach (var i in await _store.LatestAsync(200, CancellationToken.None)) _items.Add(i); }
    private void Items_DoubleClick(object sender, MouseButtonEventArgs e) { if (Items.SelectedItem is not ContentItem i) return; if (i.Audio is not null) { Player.Source=i.Audio; Player.Play(); _playing=true; NowPlaying.Text=i.Title; } else Process.Start(new ProcessStartInfo(i.Link.ToString()){UseShellExecute=true}); }
    private void PlayPause_Click(object sender, RoutedEventArgs e) { if (_playing) { Player.Pause(); _playing=false; } else { Player.Play(); _playing=true; } }
    private void Back_Click(object sender, RoutedEventArgs e) { if (Player.Position > TimeSpan.FromSeconds(15)) Player.Position -= TimeSpan.FromSeconds(15); else Player.Position=TimeSpan.Zero; }
    private void Forward_Click(object sender, RoutedEventArgs e) => Player.Position += TimeSpan.FromSeconds(15);
}
