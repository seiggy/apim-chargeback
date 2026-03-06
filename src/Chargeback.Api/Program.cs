using System.Threading.Channels;
using Chargeback.Api.Endpoints;
using Chargeback.Api.Models;
using Chargeback.Api.Services;
using Microsoft.Identity.Web;

var builder = WebApplication.CreateBuilder(args);

// Aspire service defaults: OpenTelemetry, health checks, service discovery, resilience
builder.AddServiceDefaults();

// Redis via Aspire integration (uses connection named "redis" from AppHost)
builder.AddRedisClient("redis");

// Cosmos DB via Aspire integration (uses connection named "chargeback" from AppHost)
builder.AddAzureCosmosClient("chargeback", configureClientOptions: options =>
{
    options.UseSystemTextJsonSerializerWithOptions = new System.Text.Json.JsonSerializerOptions
    {
        PropertyNamingPolicy = System.Text.Json.JsonNamingPolicy.CamelCase
    };
});

// Register application services
builder.Services.AddSingleton<IChargebackCalculator, ChargebackCalculator>();
builder.Services.AddSingleton<ChargebackMetrics>();
builder.Services.AddSingleton<ILogDataService, LogDataService>();
builder.Services.AddSingleton<IUsagePolicyStore, UsagePolicyStore>();
builder.Services.AddSingleton<IAuditStore, AuditStore>();

// Audit log channel + background writer for batched Cosmos DB writes
builder.Services.AddSingleton(Channel.CreateUnbounded<AuditLogItem>(
    new UnboundedChannelOptions { SingleReader = true }));
builder.Services.AddHostedService<AuditLogWriter>();

// OpenAPI support
builder.Services.AddOpenApi();

// Purview integration for DLP policy validation and audit emission (Agent 365)
builder.Services.AddPurviewServices(builder.Configuration);

// Entra ID JWT Bearer authentication for export endpoints
builder.Services.AddAuthentication()
    .AddMicrosoftIdentityWebApi(builder.Configuration.GetSection("AzureAd"));
builder.Services.AddAuthorizationBuilder()
    .AddPolicy("ExportPolicy", policy =>
        policy.RequireRole("Chargeback.Export"));

// CORS for React frontend
builder.Services.AddCors(options =>
{
    options.AddDefaultPolicy(policy =>
    {
        policy.AllowAnyOrigin()
              .AllowAnyMethod()
              .AllowAnyHeader();
    });
});

var app = builder.Build();

// Aspire health check endpoints
app.MapDefaultEndpoints();

if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
}

app.UseCors();
app.UseAuthentication();
app.UseAuthorization();
app.UseWebSockets();

// Serve the React SPA from wwwroot/
app.UseDefaultFiles();
app.UseStaticFiles();

// Map all endpoints
app.MapLogIngestEndpoints();
app.MapDashboardEndpoints();
app.MapPlanEndpoints();
app.MapExportEndpoints();
app.MapWebSocketEndpoints();
app.MapClientDetailEndpoints();
app.MapPrecheckEndpoints();
app.MapPricingEndpoints();
app.MapUsagePolicyEndpoints();

// SPA client-side routing fallback
app.MapFallbackToFile("index.html");

app.Run();

// Make Program visible to benchmarks and tests
public partial class Program { }
