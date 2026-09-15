using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Windows;
using System.Windows.Input;
using Nuvora.Core;

namespace Nuvora.App;

public partial class MainWindow : Window
{
    private readonly FeedEngine _engine;
    private readonly IContentStore _store;
    private readonly DiscoveryService _discovery;
    private readonly ObservableCollection<ContentItem> _items = [];
    private readonly List<Topic> _topics = [];
    private readonly List<Source> _sources = [];
    private IReadOnlyList<ContentItem> _cache = [];
    private bool _playing;

    public MainWindow(FeedEngine engine, IContentStore store, DiscoveryService discovery)
    {
        InitializeComponent();
        _engine = engine; _store = store; _discovery = discovery;
        Items.ItemsSource = _items;
        Loaded += async (_, _) => await BootstrapBrazilAsync();
        Player.MediaEnded += (_, _) => { _playing = false; PlayButton.Content = "▶"; };
    }

    private async Task BootstrapBrazilAsync()
    {
        StatusText.Text = "Preparando seu Nuvora…";
        if ((await _store.LatestAsync(1, CancellationToken.None)).Count == 0)
        {
            foreach (var preset in DiscoveryService.BrazilianNews)
            {
                var topic = new Topic(Guid.NewGuid(), preset.Category, TimeSpan.FromHours(1), DeliveryMode.Digest);
                _topics.Add(topic); _sources.Add(new(Guid.NewGuid(), topic.Id, preset.Name, preset.Feed, preset.Provider));
            }

            // Apple BR gives us a dynamic starter catalog instead of shipping stale podcast URLs.
            foreach (var term in new[] { "notícias", "brasil", "tecnologia", "esportes", "história", "cinema", "negócios", "ciência" })
            {
                try
                {
                    foreach (var podcast in await _discovery.SearchBrazilianPodcastsAsync(term, 15))
                    {
                        if (_sources.Any(s => s.Uri == podcast.Feed)) continue;
                        var topic = new Topic(Guid.NewGuid(), "Podcasts", TimeSpan.FromHours(2), DeliveryMode.Digest);
                        _topics.Add(topic); _sources.Add(new(Guid.NewGuid(), topic.Id, podcast.Name, podcast.Feed, "podcast"));
                    }
                }
                catch { /* discovery is best-effort; curated news still works offline from Apple */ }
            }
            await RefreshAllSafeAsync();
        }
        await ReloadAsync();
    }

    private async Task RefreshAllSafeAsync()
    {
        var pairs = _sources.Select(s => (Source: s, Topic: _topics.First(t => t.Id == s.TopicId))).ToArray();
        var completed = 0;
        foreach (var pair in pairs)
        {
            try { await _engine.RefreshAsync(new[] { pair.Topic }, new[] { pair.Source }, CancellationToken.None); }
            catch { /* one broken publisher must never break the whole catalog */ }
            completed++;
            if (completed % 10 == 0) StatusText.Text = $"Carregando fontes… {completed}/{pairs.Length}";
        }
    }

    private async void Add_Click(object sender, RoutedEventArgs e)
    {
        if (!Uri.TryCreate(FeedUrl.Text.Trim(), UriKind.Absolute, out var uri) || uri.Scheme is not ("https" or "http")) { MessageBox.Show("Cole o endereço RSS/Atom de uma fonte ou podcast.", "Nuvora"); return; }
        var topic = new Topic(Guid.NewGuid(), "Minha fonte", TimeSpan.FromHours(1), DeliveryMode.Immediate);
        var source = new Source(Guid.NewGuid(), topic.Id, uri.Host, uri, "rss"); _topics.Add(topic); _sources.Add(source);
        try { StatusText.Text = "Atualizando…"; await _engine.RefreshAsync(new[] { topic }, new[] { source }, CancellationToken.None); await ReloadAsync(); FeedUrl.Clear(); }
        catch (Exception ex) { MessageBox.Show($"Não foi possível atualizar essa fonte.\n\n{ex.Message}", "Nuvora"); }
    }

    private async Task ReloadAsync() { _cache = await _store.LatestAsync(500, CancellationToken.None); Show(_cache); StatusText.Text = $"{_cache.Count} itens disponíveis"; }
    private void Show(IEnumerable<ContentItem> content) { _items.Clear(); foreach (var item in content) _items.Add(item); }
    private void Today_Click(object sender, RoutedEventArgs e) { PageTitle.Text="Hoje"; PageSubtitle.Text="Notícias e episódios recentes, sem ruído."; Show(_cache); }
    private void Podcasts_Click(object sender, RoutedEventArgs e) { PageTitle.Text="Podcasts"; PageSubtitle.Text="Episódios reproduzíveis encontrados pelo Nuvora."; Show(_cache.Where(x=>x.Kind==ContentKind.Podcast || x.Audio is not null)); }
    private void Live_Click(object sender, RoutedEventArgs e) { PageTitle.Text="Ao vivo"; PageSubtitle.Text="Transmissões ao vivo declaradas pelos feeds."; Show(_cache.Where(x=>x.IsLive || x.Kind==ContentKind.Live)); }
    private void Library_Click(object sender, RoutedEventArgs e) { PageTitle.Text="Biblioteca"; PageSubtitle.Text="Tudo que o Nuvora já encontrou."; Show(_cache); }
    private void ToggleAdd_Click(object sender, RoutedEventArgs e) { AddPanel.Visibility=AddPanel.Visibility==Visibility.Visible?Visibility.Collapsed:Visibility.Visible; if(AddPanel.Visibility==Visibility.Visible) FeedUrl.Focus(); }
    private async void Refresh_Click(object sender, RoutedEventArgs e) { StatusText.Text="Atualizando catálogo…"; await RefreshAllSafeAsync(); await ReloadAsync(); }
    private void Items_DoubleClick(object sender, MouseButtonEventArgs e) { if(Items.SelectedItem is not ContentItem item)return; if(item.Audio is not null){Player.Source=item.Audio;Player.Play();_playing=true;PlayButton.Content="❚❚";NowPlaying.Text=item.Title;}else Process.Start(new ProcessStartInfo(item.Link.ToString()){UseShellExecute=true}); }
    private void PlayPause_Click(object sender, RoutedEventArgs e) { if(Player.Source is null)return; if(_playing){Player.Pause();_playing=false;PlayButton.Content="▶";}else{Player.Play();_playing=true;PlayButton.Content="❚❚";} }
    private void Back_Click(object sender, RoutedEventArgs e)=>Player.Position=Player.Position>TimeSpan.FromSeconds(15)?Player.Position-TimeSpan.FromSeconds(15):TimeSpan.Zero;
    private void Forward_Click(object sender, RoutedEventArgs e)=>Player.Position+=TimeSpan.FromSeconds(15);
    private void Player_MediaOpened(object sender, RoutedEventArgs e)=>PlaybackTime.Text=Player.NaturalDuration.HasTimeSpan?$"{Player.NaturalDuration.TimeSpan:h\\:mm\\:ss}":"AO VIVO";
}
