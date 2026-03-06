using Chargeback.Api.Models;

namespace Chargeback.Api.Services;

/// <summary>
/// Shared service for reading aggregated log data and request traces from Redis.
/// Eliminates the duplicated GetAllLogsFromRedis methods across endpoint classes.
/// </summary>
public interface ILogDataService
{
    /// <summary>
    /// Scans all Redis keys, filters out non-log-entry keys, deserializes cached log data,
    /// and calculates costs. Used by Dashboard, Export, and WebSocket endpoints.
    /// </summary>
    Task<List<LogEntry>> GetAllLogsAsync(ILogger logger);

    /// <summary>
    /// Reads trace records from all traces:* Redis lists and builds request log entries
    /// with client display name resolution.
    /// </summary>
    Task<List<RequestLogEntry>> GetRequestLogsAsync(ILogger logger);
}
