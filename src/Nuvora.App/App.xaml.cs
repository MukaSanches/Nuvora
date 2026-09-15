using System.IO;
using System.Windows;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Nuvora.Core;

namespace Nuvora.App;

public partial class App : Application
{
    private IHost? _host;
    protected override async void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        var data = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Nuvora");
        Directory.CreateDirectory(data);
        _host = Host.CreateDefaultBuilder().ConfigureServices(s =>
        {
            s.AddHttpClient<RssProvider>(c => { c.Timeout = TimeSpan.FromSeconds(20); c.DefaultRequestHeaders.UserAgent.ParseAdd("Nuvora/0.2 (Windows; +https://github.com/MukaSanches/Nuvora)"); }).AddStandardResilienceHandler();
            s.AddHttpClient<DiscoveryService>(c => { c.Timeout = TimeSpan.FromSeconds(20); c.DefaultRequestHeaders.UserAgent.ParseAdd("Nuvora/0.2"); }).AddStandardResilienceHandler();
            s.AddSingleton<IContentProvider>(sp => sp.GetRequiredService<RssProvider>());
            s.AddSingleton<IContentStore>(_ => new SqliteContentStore($"Data Source={Path.Combine(data, "nuvora.db")}"));
            s.AddSingleton<INotificationSink, WindowsNotificationSink>();
            s.AddSingleton<FeedEngine>();
            s.AddSingleton<MainWindow>();
        }).Build();
        await _host.StartAsync();
        await _host.Services.GetRequiredService<IContentStore>().InitializeAsync(CancellationToken.None);
        _host.Services.GetRequiredService<MainWindow>().Show();
    }
    protected override async void OnExit(ExitEventArgs e)
    {
        if (_host is not null) { await _host.StopAsync(); _host.Dispose(); }
        base.OnExit(e);
    }
}
