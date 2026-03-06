namespace Chargeback.Api.Services;

/// <summary>
/// Centralized Redis key patterns to eliminate magic strings across the codebase.
/// </summary>
public static class RedisKeys
{
    public static string Plan(string planId) => $"plan:{planId}";
    public static string Client(string clientAppId) => $"client:{clientAppId}";
    public static string Traces(string clientAppId) => $"traces:{clientAppId}";
    public static string Pricing(string modelId) => $"pricing:{modelId}";
    public static string UsagePolicySettings => "settings:usage-policy";
    public static string ClientUpdateLock(string clientAppId) => $"lock:client:{clientAppId}";
    public static string RateLimitRpm(string clientAppId, long minuteWindow) => $"ratelimit:rpm:{clientAppId}:{minuteWindow}";
    public static string RateLimitTpm(string clientAppId, long minuteWindow) => $"ratelimit:tpm:{clientAppId}:{minuteWindow}";
    public static string LogEntry(string tenantId, string clientAppId, string deploymentId) => $"{tenantId}-{clientAppId}-{deploymentId}";
    public static string ClientLogPattern(string clientAppId) => $"*-{clientAppId}-*";

    // Key prefix patterns for scanning
    public const string PlanPrefix = "plan:*";
    public const string ClientPrefix = "client:*";
    public const string TracesPrefix = "traces:*";
    public const string PricingPrefix = "pricing:*";
    public const string LogEntryPattern = "*-*-*";

    /// <summary>
    /// Prefixes used by non-log-entry data types — used to filter them out when scanning all keys.
    /// </summary>
    public static readonly string[] ExcludedPrefixes = ["plan:", "client:", "traces:", "pricing:", "ratelimit:", "quota:", "lock:", "settings:"];
}
