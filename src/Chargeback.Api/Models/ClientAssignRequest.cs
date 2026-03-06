namespace Chargeback.Api.Models;

public sealed class ClientAssignRequest
{
    public string PlanId { get; set; } = string.Empty;
    public string? DisplayName { get; set; }
}
