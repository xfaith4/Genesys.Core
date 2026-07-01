using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

namespace Genesys.MockServer.Tests;

/// <summary>
/// WebApplicationFactory for running the mock server in-process during xUnit tests.
/// Resolves the catalog and fixtures from the repository root automatically.
/// </summary>
public sealed class MockServerFactory : WebApplicationFactory<Program>
{
    protected override IHost CreateHost(IHostBuilder builder)
    {
        // Configure test-time environment
        var repoRoot = FindRepoRoot();
        Environment.SetEnvironmentVariable("MOCK_CATALOG_PATH",
            Path.Combine(repoRoot, "catalog", "genesys.catalog.json"));
        Environment.SetEnvironmentVariable("MOCK_FIXTURES_PATH",
            Path.Combine(repoRoot, "tests", "fixtures", "demo"));
        Environment.SetEnvironmentVariable("MOCK_POLLING_ROUNDS", "2");

        return base.CreateHost(builder);
    }

    public CatalogLoader GetCatalogLoader() => Services.GetRequiredService<CatalogLoader>();

    private static string FindRepoRoot()
    {
        var dir = AppContext.BaseDirectory;
        for (var i = 0; i < 15; i++)
        {
            if (Directory.Exists(Path.Combine(dir, "catalog")) &&
                File.Exists(Path.Combine(dir, "catalog", "genesys.catalog.json")))
                return dir;
            var parent = Directory.GetParent(dir);
            if (parent is null) break;
            dir = parent.FullName;
        }
        throw new DirectoryNotFoundException(
            "Could not locate repo root containing 'catalog/genesys.catalog.json'. " +
            $"Started from: {AppContext.BaseDirectory}");
    }
}
