using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Windows;
using System.Windows.Input;
using LibVLCSharp.Shared;
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
    private readonly LibVLC _libVlc;
    private readonly MediaPlayer _mediaPlayer;
    private Media? _media;

    public MainWindow(FeedEngine engine, IContentStore store, DiscoveryService discovery)
    {
        InitializeComponent();
        _engine = engine; _store = store; _discovery = discovery;
        Items.ItemsSource = _items;
        Core.Initialize();
        _libVlc = new LibVLC("--no-video", "--network-caching=1200");
        _mediaPlayer = new MediaPlayer(_libVlc);
        _mediaPlayer.Playing += (_, _) => Dispatcher.Invoke(() => { StatusText.Text = "Reproduzindo"; PlayButton.Content = "❚❚"; });
        _mediaPlayer.Paused += (_, _) => Dispatcher.Invoke(() => { StatusText.Text = "Pausado"; PlayButton.Content = "▶"; });
        _mediaPlayer.Stopped += (_, _) => Dispatcher.Invoke(() => PlayButton.Content = "▶");
        _mediaPlayer.EndReached += (_, _) => Dispatcher.Invoke(() => { PlayButton.Content = "▶"; StatusText.Text = "Episódio finalizado"; });
        _mediaPlayer.EncounteredError += (_, _) => Dispatcher.Invoke(() => { PlayButton.Content = "▶"; StatusText.Text = "Falha ao reproduzir áudio"; MessageBox.Show("Não foi possível reproduzir este episódio. O Nuvora tentou abrir o stream com o mecanismo VLC.", "Nuvora"); });
        Loaded += async (_, _) => await BootstrapBrazilAsync();
        Closed += (_, _) => { _mediaPlayer.Stop(); _media?.Dispose(); _mediaPlayer.Dispose(); _libVlc.Dispose(); };
    }

    private async Task BootstrapBrazilAsync()
    {
        StatusText.Text = "Preparando conteúdo em português do Brasil…";
        foreach (var preset in DiscoveryService.BrazilianNews.Concat(DiscoveryService.BrazilianPodcasts)) AddPreset(preset);
        foreach (var term in new[] { "podcast brasileiro", "notícias brasil", "tecnologia brasil", "esportes brasil", "história brasil", "cinema brasil", "negócios brasil", "ciência brasil" })
        {
            try
            {
                foreach (var podcast in await _discovery.SearchBrazilianPodcastsAsync(term, 12))
                {
                    if (_sources.Any(s => s.Uri == podcast.Feed)) continue;
                    var topic = new Topic(Guid.NewGuid(), "Podcasts", TimeSpan.FromHours(2), DeliveryMode.Digest);
                    _topics.Add(topic); _sources.Add(new Source(Guid.NewGuid(), topic.Id, podcast.Name, podcast.Feed, "podcast"));
                }
            }
            catch { }
        }
        await RefreshAllSafeAsync(); await ReloadAsync();
    }

    private void AddPreset(DiscoverySource preset)
    {
        if (_sources.Any(s => s.Uri == preset.Feed)) return;
        var topic = new Topic(Guid.NewGuid(), preset.Category, TimeSpan.FromHours(1), DeliveryMode.Digest);
        _topics.Add(topic); _sources.Add(new Source(Guid.NewGuid(), topic.Id, preset.Name, preset.Feed, preset.Provider));
    }

    private async Task RefreshAllSafeAsync()
    {
        var pairs = _sources.Select(s => (Source: s, Topic: _topics.First(t => t.Id == s.TopicId))).ToArray(); var completed = 0;
        foreach (var pair in pairs)
        {
            try { await _engine.RefreshAsync(new[] { pair.Topic }, new[] { pair.Source }, CancellationToken.None); } catch { }
            completed++; if (completed % 10 == 0) StatusText.Text = $"Carregando fontes brasileiras… {completed}/{pairs.Length}";
        }
    }

    private async void Add_Click(object sender, RoutedEventArgs e)
    {
        if (!Uri.TryCreate(FeedUrl.Text.Trim(), UriKind.Absolute, out var uri) || uri.Scheme is not ("https" or "http")) { MessageBox.Show("Cole o endereço RSS/Atom de uma fonte ou podcast.", "Nuvora"); return; }
        var topic = new Topic(Guid.NewGuid(), "Minha fonte", TimeSpan.FromHours(1), DeliveryMode.Immediate); var source = new Source(Guid.NewGuid(), topic.Id, uri.Host, uri, "rss"); _topics.Add(topic); _sources.Add(source);
        try { StatusText.Text = "Atualizando…"; await _engine.RefreshAsync(new[] { topic }, new[] { source }, CancellationToken.None); await ReloadAsync(); FeedUrl.Clear(); } catch (Exception ex) { MessageBox.Show($"Não foi possível atualizar essa fonte.\n\n{ex.Message}", "Nuvora"); }
    }

    private async Task ReloadAsync() { _cache = await _store.LatestAsync(500, CancellationToken.None); Show(_cache); StatusText.Text = $"{_cache.Count} itens disponíveis"; }
    private void Show(IEnumerable<ContentItem> content) { _items.Clear(); foreach (var item in content) _items.Add(item); }
    private void Today_Click(object sender, RoutedEventArgs e) { PageTitle.Text="Hoje"; PageSubtitle.Text="Notícias e episódios recentes, sem ruído."; Show(_cache); }
    private void Podcasts_Click(object sender, RoutedEventArgs e) { PageTitle.Text="Podcasts"; PageSubtitle.Text="Episódios com áudio encontrados pelo Nuvora."; Show(_cache.Where(x=>x.Audio is not null)); }
    private void Live_Click(object sender, RoutedEventArgs e) { PageTitle.Text="Ao vivo"; PageSubtitle.Text="Transmissões ao vivo declaradas pelos feeds."; Show(_cache.Where(x=>x.IsLive || x.Kind==ContentKind.Live)); }
    private void Library_Click(object sender, RoutedEventArgs e) { PageTitle.Text="Biblioteca"; PageSubtitle.Text="Tudo que o Nuvora já encontrou."; Show(_cache); }
    private void ToggleAdd_Click(object sender, RoutedEventArgs e) { AddPanel.Visibility=AddPanel.Visibility==Visibility.Visible?Visibility.Collapsed:Visibility.Visible; if(AddPanel.Visibility==Visibility.Visible) FeedUrl.Focus(); }
    private async void Refresh_Click(object sender, RoutedEventArgs e) { StatusText.Text="Atualizando catálogo…"; await RefreshAllSafeAsync(); await ReloadAsync(); }

    private void Items_DoubleClick(object sender, MouseButtonEventArgs e)
    {
        if (Items.SelectedItem is not ContentItem item) return;
        if (item.Audio is null) { Process.Start(new ProcessStartInfo(item.Link.ToString()){UseShellExecute=true}); return; }
        StatusText.Text = "Carregando áudio…"; NowPlaying.Text = item.Title;
        _mediaPlayer.Stop(); _media?.Dispose();
        _media = new Media(_libVlc, item.Audio);
        _media.AddOption(":network-caching=1200");
        if (!_mediaPlayer.Play(_media)) { StatusText.Text = "Não foi possível iniciar o áudio"; MessageBox.Show("O stream não pôde ser iniciado.", "Nuvora"); }
    }

    private void PlayPause_Click(object sender, RoutedEventArgs e) { if (_media is null) return; if (_mediaPlayer.IsPlaying) _mediaPlayer.Pause(); else _mediaPlayer.Play(); }
    private void Back_Click(object sender, RoutedEventArgs e) { if (_mediaPlayer.Time > 15000) _mediaPlayer.Time -= 15000; else _mediaPlayer.Time = 0; }
    private void Forward_Click(object sender, RoutedEventArgs e) { if (_mediaPlayer.Length > 0) _mediaPlayer.Time = Math.Min(_mediaPlayer.Time + 15000, _mediaPlayer.Length); else _mediaPlayer.Time += 15000; }
}
