using System.Net.Http.Headers;
using System.Text.Json;
using Chargeback.Api.Models;
using Azure.Identity;
using Azure.Core;
using StackExchange.Redis;

namespace Chargeback.Api.Services;

public interface IDeploymentDiscoveryService
{
    Task<List<DeploymentInfo>> GetDeploymentsAsync(CancellationToken ct = default);
}

public sealed class DeploymentDiscoveryService : IDeploymentDiscoveryService
{
    private const string CacheKey = "deployments:available";
    private static readonly TimeSpan CacheTtl = TimeSpan.FromMinutes(5);

    private readonly IConnectionMultiplexer _redis;
    private readonly IConfiguration _configuration;
    private readonly ILogger<DeploymentDiscoveryService> _logger;
    private readonly TokenCredential _credential;

    public DeploymentDiscoveryService(
        IConnectionMultiplexer redis,
        IConfiguration configuration,
        ILogger<DeploymentDiscoveryService> logger)
    {
        _redis = redis;
        _configuration = configuration;
        _logger = logger;
        _credential = new DefaultAzureCredential();
    }

    public async Task<List<DeploymentInfo>> GetDeploymentsAsync(CancellationToken ct = default)
    {
        var db = _redis.GetDatabase();

        // Check cache first
        var cached = await db.StringGetAsync(CacheKey);
        if (cached.HasValue)
        {
            try
            {
                var cachedList = JsonSerializer.Deserialize<List<DeploymentInfo>>((string)cached!, JsonConfig.Default);
                if (cachedList is not null) return cachedList;
            }
            catch (JsonException) { }
        }

        var endpoint = _configuration["AZURE_AI_ENDPOINT"];
        if (string.IsNullOrWhiteSpace(endpoint))
        {
            _logger.LogWarning("AZURE_AI_ENDPOINT not configured — returning empty deployment list");
            return [];
        }

        try
        {
            // Get token for Azure Cognitive Services
            var tokenResult = await _credential.GetTokenAsync(
                new TokenRequestContext(["https://cognitiveservices.azure.com/.default"]), ct);

            using var httpClient = new HttpClient();
            httpClient.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", tokenResult.Token);

            // Call the Azure OpenAI deployments list API
            var apiUrl = $"{endpoint.TrimEnd('/')}/openai/deployments?api-version=2024-10-21";
            var response = await httpClient.GetAsync(apiUrl, ct);
            response.EnsureSuccessStatusCode();

            var body = await response.Content.ReadAsStringAsync(ct);
            using var doc = JsonDocument.Parse(body);

            var deployments = new List<DeploymentInfo>();
            if (doc.RootElement.TryGetProperty("data", out var data) && data.ValueKind == JsonValueKind.Array)
            {
                foreach (var item in data.EnumerateArray())
                {
                    var id = item.GetProperty("id").GetString() ?? "";
                    var model = "";
                    var modelVersion = "";
                    if (item.TryGetProperty("model", out var modelProp) && modelProp.ValueKind == JsonValueKind.String)
                    {
                        model = modelProp.GetString() ?? "";
                    }

                    var skuName = "";
                    var skuCapacity = 0;
                    if (item.TryGetProperty("sku", out var sku))
                    {
                        skuName = sku.TryGetProperty("name", out var sn) ? sn.GetString() ?? "" : "";
                        skuCapacity = sku.TryGetProperty("capacity", out var sc) && sc.TryGetInt32(out var cap) ? cap : 0;
                    }

                    deployments.Add(new DeploymentInfo
                    {
                        Id = id,
                        Model = model,
                        ModelVersion = modelVersion,
                        SkuName = skuName,
                        SkuCapacity = skuCapacity
                    });
                }
            }

            // Cache the result
            var cacheValue = JsonSerializer.Serialize(deployments, JsonConfig.Default);
            await db.StringSetAsync(CacheKey, cacheValue, CacheTtl);

            _logger.LogInformation("Fetched {Count} deployments from Azure AI Foundry", deployments.Count);
            return deployments;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to fetch deployments from Azure AI Foundry");
            return [];
        }
    }
}
