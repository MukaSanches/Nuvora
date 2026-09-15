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
    private readonly ObservableCollection<ContentItem> _items = [];
    private readonly List<Topic> _topics = [];
    private readonly List<Source> _sources = [];
    private IReadOnlyList<ContentItem> _cache = [];
    private bool _playing;

    public MainWindow(FeedEngine engine, IContentStore store)
    {
        InitializeComponent();
        _engine = engine;
        _store = store;
        Items.ItemsSource = _items;
        Loaded += async (_, _) => await ReloadAsync();
        Player.MediaEnded += (_, _) => { _playing = false; PlayButton.Content = "▶"; };
    }

    private async void Add_Click(object sender, RoutedEventArgs e)
    {
        if (!Uri.TryCreate(FeedUrl.Text.Trim(), UriKind.Absolute, out var uri) || uri.Scheme is not ("https" or "http"))
        {
            MessageBox.Show("Cole o endereço RSS/Atom de uma fonte ou podcast.", "Nuvora", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }

        var topic = new Topic(Guid.NewGuid(), uri.Host, TimeSpan.FromHours(1), DeliveryMode.Immediate);
        _topics.Add(topic);
        _sources.Add(new Source(Guid.NewGuid(), topic.Id, uri.Host, uri, "rss"));
        StatusText.Text = "Atualizando…";
        try
        {
            await _engine.RefreshAsync(_topics, _sources, CancellationToken.None);
            await ReloadAsync();
            FeedUrl.Clear();
            StatusText.Text = "Atualizado agora";
        }
        catch (Exception ex)
        {
            StatusText.Text = "Falha ao atualizar";
            MessageBox.Show($"Não foi possível atualizar essa fonte.\n\n{ex.Message}", "Nuvora", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }

    private async Task ReloadAsync()
    {
        _cache = await _store.LatestAsync(300, CancellationToken.None);
        Show(_cache);
        StatusText.Text = _cache.Count == 0 ? "Adicione sua primeira fonte" : $"{_cache.Count} itens na biblioteca";
    }

    private void Show(IEnumerable<ContentItem> content)
    {
        _items.Clear();
        foreach (var item in content) _items.Add(item);
    }

    private void Today_Click(object sender, RoutedEventArgs e)
    {
        PageTitle.Text = "Hoje"; PageSubtitle.Text = "Notícias e episódios recentes, sem ruído."; Show(_cache);
    }

    private void Podcasts_Click(object sender, RoutedEventArgs e)
    {
        PageTitle.Text = "Podcasts"; PageSubtitle.Text = "Episódios das fontes que você acompanha."; Show(_cache.Where(x => x.Kind == ContentKind.Podcast || x.Audio is not null));
    }

    private void Live_Click(object sender, RoutedEventArgs e)
    {
        PageTitle.Text = "Ao vivo"; PageSubtitle.Text = "Transmissões declaradas como live pelos feeds."; Show(_cache.Where(x => x.IsLive || x.Kind == ContentKind.Live));
    }

    private void Library_Click(object sender, RoutedEventArgs e)
    {
        PageTitle.Text = "Biblioteca"; PageSubtitle.Text = "Tudo que o Nuvora já encontrou."; Show(_cache);
    }

    private void ToggleAdd_Click(object sender, RoutedEventArgs e)
    {
        AddPanel.Visibility = AddPanel.Visibility == Visibility.Visible ? Visibility.Collapsed : Visibility.Visible;
        if (AddPanel.Visibility == Visibility.Visible) FeedUrl.Focus();
    }

    private async void Refresh_Click(object sender, RoutedEventArgs e)
    {
        if (_sources.Count == 0) { await ReloadAsync(); return; }
        StatusText.Text = "Atualizando…";
        try { await _engine.RefreshAsync(_topics, _sources, CancellationToken.None); await ReloadAsync(); StatusText.Text = "Atualizado agora"; }
        catch (Exception ex) { StatusText.Text = "Falha ao atualizar"; MessageBox.Show(ex.Message, "Nuvora"); }
    }

    private void Items_DoubleClick(object sender, MouseButtonEventArgs e)
    {
        if (Items.SelectedItem is not ContentItem item) return;
        if (item.Audio is not null)
        {
            Player.Source = item.Audio; Player.Play(); _playing = true; PlayButton.Content = "❚❚"; NowPlaying.Text = item.Title;
        }
        else Process.Start(new ProcessStartInfo(item.Link.ToString()) { UseShellExecute = true });
    }

    private void PlayPause_Click(object sender, RoutedEventArgs e)
    {
        if (Player.Source is null) return;
        if (_playing) { Player.Pause(); _playing = false; PlayButton.Content = "▶"; }
        else { Player.Play(); _playing = true; PlayButton.Content = "❚❚"; }
    }

    private void Back_Click(object sender, RoutedEventArgs e) => Player.Position = Player.Position > TimeSpan.FromSeconds(15) ? Player.Position - TimeSpan.FromSeconds(15) : TimeSpan.Zero;
    private void Forward_Click(object sender, RoutedEventArgs e) => Player.Position += TimeSpan.FromSeconds(15);
    private void Player_MediaOpened(object sender, RoutedEventArgs e) => PlaybackTime.Text = Player.NaturalDuration.HasTimeSpan ? $"{Player.NaturalDuration.TimeSpan:h\\:mm\\:ss}" : "AO VIVO";
}