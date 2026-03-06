using System.Threading.Channels;
using Chargeback.Api.Models;
using Chargeback.Api.Services;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Azure.Cosmos;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using NSubstitute;
using StackExchange.Redis;

namespace Chargeback.Tests;

/// <summary>
/// Custom WebApplicationFactory that replaces real Redis with an in-memory FakeRedis
/// and stubs Cosmos DB with a no-op IAuditStore for unit tests.
/// </summary>
public sealed class ChargebackApiFactory : WebApplicationFactory<Program>
{
    public FakeRedis Redis { get; } = new();

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Testing");

        builder.ConfigureAppConfiguration(config =>
        {
            config.AddInMemoryCollection(new Dictionary<string, string?>
            {
                // Provide a dummy connection string so Aspire doesn't throw on missing config
                ["ConnectionStrings:redis"] = "localhost:99999,abortConnect=false,connectTimeout=1",
                // Dummy Cosmos connection for testing
                ["ConnectionStrings:chargeback"] = "AccountEndpoint=https://localhost:8081/;AccountKey=dGVzdA==",
                // Disable AzureAd auth in tests
                ["AzureAd:Instance"] = "https://login.microsoftonline.com/",
                ["AzureAd:TenantId"] = "test-tenant",
                ["AzureAd:ClientId"] = "test-client"
            });
        });

        builder.ConfigureTestServices(services =>
        {
            // Remove all real IConnectionMultiplexer registrations (from Aspire)
            var descriptors = services
                .Where(d => d.ServiceType == typeof(IConnectionMultiplexer))
                .ToList();
            foreach (var d in descriptors) services.Remove(d);

            services.AddSingleton<IConnectionMultiplexer>(Redis.Multiplexer);

            // Replace ILogDataService with a fake that reads from FakeRedis
            var logDescriptors = services
                .Where(d => d.ServiceType == typeof(ILogDataService))
                .ToList();
            foreach (var d in logDescriptors) services.Remove(d);

            // Re-register the real LogDataService; it will use our fake IConnectionMultiplexer
            services.AddSingleton<ILogDataService, LogDataService>();

            // Remove real CosmosClient registrations and replace with stub
            RemoveService<CosmosClient>(services);
            var mockCosmos = Substitute.For<CosmosClient>();
            services.AddSingleton(mockCosmos);

            // Replace IAuditStore with a stub that returns empty collections
            RemoveService<IAuditStore>(services);
            var mockAuditStore = Substitute.For<IAuditStore>();
            mockAuditStore.GetAvailablePeriodsAsync(Arg.Any<CancellationToken>())
                .Returns(Task.FromResult(new List<Chargeback.Api.Models.ExportPeriod>()));
            mockAuditStore.GetClientsForPeriodAsync(Arg.Any<string>(), Arg.Any<CancellationToken>())
                .Returns(Task.FromResult(new List<Chargeback.Api.Models.ExportClient>()));
            mockAuditStore.GetBillingSummariesAsync(Arg.Any<string>(), Arg.Any<CancellationToken>())
                .Returns(Task.FromResult(new List<Chargeback.Api.Models.BillingSummaryDocument>()));
            mockAuditStore.GetClientAuditLogsAsync(Arg.Any<string>(), Arg.Any<string>(), Arg.Any<CancellationToken>())
                .Returns(Task.FromResult(new List<Chargeback.Api.Models.AuditLogDocument>()));
            services.AddSingleton<IAuditStore>(mockAuditStore);

            // Ensure the audit channel is registered (may already be)
            if (!services.Any(d => d.ServiceType == typeof(Channel<AuditLogItem>)))
            {
                services.AddSingleton(Channel.CreateUnbounded<AuditLogItem>(
                    new UnboundedChannelOptions { SingleReader = true }));
            }
        });
    }

    private static void RemoveService<T>(IServiceCollection services)
    {
        var descriptors = services.Where(d => d.ServiceType == typeof(T)).ToList();
        foreach (var d in descriptors) services.Remove(d);
    }
}
