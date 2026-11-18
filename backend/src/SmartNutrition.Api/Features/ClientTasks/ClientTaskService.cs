using System.Data;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using SmartNutrition.Api.Data;
using SmartNutrition.Api.Features.Dietitians;
using SmartNutrition.Api.Features.Relationships;
using SmartNutrition.Api.Models;

namespace SmartNutrition.Api.Features.ClientTasks;

public sealed class ClientTaskService(AppDbContext database, RelationshipAccessService access, TimeProvider clock)
{
    private async Task<Guid> RequireExpertAsync(ProfileIdentity actor, Guid clientId, Guid? relationshipId, CancellationToken token)
    {
        if (actor.Role != UserRole.Dietitian || actor.DietitianId is null ||
            !await database.DietitianProfiles.AnyAsync(x => x.Id == actor.DietitianId && x.IsVerified && x.User.IsEmailVerified && x.User.Role != UserRole.Admin, token))
            throw new ResourceOperationException(403);
        var relationship = await database.DietitianClientRelationships.AsNoTracking()
            .Where(x => x.ClientId == clientId && x.DietitianId == actor.DietitianId && x.Status == RelationshipStatus.Active &&
                (relationshipId == null || x.Id == relationshipId))
            .Select(x => new { x.Id, Granted = database.DataSharingPermissions.Any(p => p.RelationshipId == x.Id && p.Category == "client_tasks" && p.IsGranted) })
            .SingleOrDefaultAsync(token) ?? throw new ResourceOperationException(404);
        if (!relationship.Granted) throw new ResourceOperationException(403);
        return relationship.Id;
    }
    private async Task RequireReadAsync(ProfileIdentity actor, ClientTask task, CancellationToken token)
    {
        if (actor.Role == UserRole.Client)
        { if (actor.ClientId != task.ClientId) throw new ResourceOperationException(404); return; }
        if (actor.DietitianId != task.DietitianId) throw new ResourceOperationException(404);
        await RequireExpertAsync(actor, task.ClientId, task.RelationshipId, token);
    }
    private async Task<ClientTask> FindAsync(Guid id, CancellationToken token) =>
        await database.ClientTasks.AsNoTracking().SingleOrDefaultAsync(x => x.Id == id, token) ?? throw new ResourceOperationException(404);

    public async Task<ClientTaskResponse> CreateAsync(ProfileIdentity actor, CreateClientTaskRequest request, CancellationToken token)
    {
        if (actor.Role != UserRole.Dietitian) throw new ResourceOperationException(403);
        if (request.ClientId == Guid.Empty) throw new ResourceOperationException(422);
        var description = ClientTaskValidation.Description(request.Description);
        await using var transaction = await database.Database.BeginTransactionAsync(token);
        await RequireExpertAsync(actor, request.ClientId, null, token);
        await access.LockActorAsync(actor, token); await access.LockClientAsync(request.ClientId, token);
        var relationshipId = await RequireExpertAsync(actor, request.ClientId, null, token);
        var now = RecordTime.Normalize(clock.GetUtcNow());
        var row = new ClientTask(request.ClientId, actor.DietitianId!.Value, relationshipId, description, ClientTaskValidation.DueAt(request.DueAt, now), now);
        database.ClientTasks.Add(row); database.ClientTaskVersions.Add(new ClientTaskVersion(row, actor.UserId));
        await database.SaveChangesAsync(token); await transaction.CommitAsync(token);
        return ClientTaskResponse.From(row);
    }
    public async Task<PagedResponse<ClientTaskResponse>> ListAsync(ProfileIdentity actor, Guid? clientId, int page, int size, CancellationToken token)
    {
        await using var transaction = await database.Database.BeginTransactionAsync(IsolationLevel.RepeatableRead, token);
        Guid target; Guid? relationshipId = null;
        if (actor.Role == UserRole.Client) target = actor.ClientId ?? throw new ResourceOperationException(403);
        else
        {
            target = clientId is null || clientId == Guid.Empty ? throw new ResourceOperationException(400) : clientId.Value;
            relationshipId = await RequireExpertAsync(actor, target, null, token);
        }
        var query = database.ClientTasks.AsNoTracking().Where(x => x.ClientId == target);
        if (relationshipId is not null) query = query.Where(x => x.RelationshipId == relationshipId && x.DietitianId == actor.DietitianId);
        var count = await query.CountAsync(token);
        var rows = await query.OrderByDescending(x => x.CreatedAt).ThenBy(x => x.Id).Skip((page - 1) * size).Take(size).ToListAsync(token);
        await transaction.CommitAsync(token);
        return new(rows.Select(ClientTaskResponse.From).ToArray(), count);
    }
    public async Task<ClientTaskResponse> GetAsync(ProfileIdentity actor, Guid id, CancellationToken token)
    {
        await using var transaction = await database.Database.BeginTransactionAsync(IsolationLevel.RepeatableRead, token);
        var row = await FindAsync(id, token); await RequireReadAsync(actor, row, token);
        await transaction.CommitAsync(token); return ClientTaskResponse.From(row);
    }
    public async Task<PagedResponse<ClientTaskVersionResponse>> VersionsAsync(ProfileIdentity actor, Guid id, int page, int size, CancellationToken token)
    {
        await using var transaction = await database.Database.BeginTransactionAsync(IsolationLevel.RepeatableRead, token);
        var row = await FindAsync(id, token); await RequireReadAsync(actor, row, token);
        var query = database.ClientTaskVersions.AsNoTracking().Where(x => x.ClientTaskId == id);
        var count = await query.CountAsync(token);
        var rows = await query.OrderByDescending(x => x.VersionNumber).Skip((page - 1) * size).Take(size).ToListAsync(token);
        await transaction.CommitAsync(token);
        return new(rows.Select(ClientTaskVersionResponse.From).ToArray(), count);
    }
    public async Task<ClientTaskResponse> PatchAsync(ProfileIdentity actor, Guid id, PatchClientTaskRequest request, CancellationToken token)
    {
        if (request.ExpectedVersionNumber < 1) throw new ResourceOperationException(422);
        var fields = new[] { request.Description, request.DueAt, request.Status, request.IsReminderEnabled };
        if (fields.All(x => x.ValueKind == JsonValueKind.Undefined)) throw new ResourceOperationException(400);
        var candidate = await FindAsync(id, token); await RequireReadAsync(actor, candidate, token);
        await using var transaction = await database.Database.BeginTransactionAsync(token);
        await access.LockActorAsync(actor, token); await access.LockClientAsync(candidate.ClientId, token);
        var row = await database.ClientTasks.FromSqlInterpolated($"SELECT * FROM client_tasks WHERE id = {id} FOR UPDATE").SingleAsync(token);
        // Recheck the original relationship and grant after waiting, just like withdrawal/end.
        await RequireReadAsync(actor, row, token);
        if (row.VersionNumber != request.ExpectedVersionNumber || row.IsClosed) throw new ResourceOperationException(409);
        var isClient = actor.Role == UserRole.Client;
        if (isClient ? request.Description.ValueKind != JsonValueKind.Undefined || request.DueAt.ValueKind != JsonValueKind.Undefined
            : request.IsReminderEnabled.ValueKind != JsonValueKind.Undefined) throw new ResourceOperationException(403);
        var description = row.Description; var dueAt = row.DueAt; var status = row.Status; var reminder = row.IsReminderEnabled;
        var now = RecordTime.Normalize(clock.GetUtcNow());
        if (request.Description.ValueKind != JsonValueKind.Undefined)
            description = ClientTaskValidation.Description(ReadString(request.Description));
        if (request.DueAt.ValueKind != JsonValueKind.Undefined)
        {
            var supplied = ClientTaskValidation.ReadDueAt(request.DueAt);
            if (supplied is null) { dueAt = null; reminder = false; }
            else if (RecordTime.Normalize(supplied.Value) != row.DueAt) dueAt = ClientTaskValidation.DueAt(supplied, now < row.CreatedAt ? row.CreatedAt : now);
        }
        if (request.Status.ValueKind != JsonValueKind.Undefined)
        {
            status = ReadString(request.Status) switch
            {
                "pending" => ClientTaskStatus.Pending, "in_progress" => ClientTaskStatus.InProgress,
                "completed" => ClientTaskStatus.Completed, "cancelled" => ClientTaskStatus.Cancelled,
                _ => throw new ResourceOperationException(422)
            };
            if (status != row.Status)
            {
                if (isClient)
                {
                    if (status == ClientTaskStatus.Cancelled) throw new ResourceOperationException(403);
                    if (status != ClientTaskStatus.Completed && !(row.Status == ClientTaskStatus.Pending && status == ClientTaskStatus.InProgress))
                        throw new ResourceOperationException(409);
                }
                else if (status != ClientTaskStatus.Cancelled) throw new ResourceOperationException(403);
            }
        }
        if (request.IsReminderEnabled.ValueKind != JsonValueKind.Undefined)
        {
            if (request.IsReminderEnabled.ValueKind == JsonValueKind.Null) throw new ResourceOperationException(422);
            if (request.IsReminderEnabled.ValueKind is not (JsonValueKind.True or JsonValueKind.False)) throw new ResourceOperationException(400);
            reminder = request.IsReminderEnabled.GetBoolean();
            if (reminder && dueAt is null) throw new ResourceOperationException(422);
        }
        if (row.Revise(description, dueAt, status, reminder, now))
        {
            database.ClientTaskVersions.Add(new ClientTaskVersion(row, actor.UserId));
            await database.SaveChangesAsync(token);
        }
        await transaction.CommitAsync(token); return ClientTaskResponse.From(row);
    }
    private static string? ReadString(JsonElement field)
    {
        if (field.ValueKind == JsonValueKind.Null) throw new ResourceOperationException(422);
        if (field.ValueKind != JsonValueKind.String) throw new ResourceOperationException(400);
        return field.GetString();
    }

    // Caller already owns the actor/client/relationship locks and transaction.
    internal static async Task CancelForRelationshipAsync(AppDbContext database, Guid relationshipId, Guid actor, DateTimeOffset now, CancellationToken token)
    {
        var tasks = await database.ClientTasks.Where(x => x.RelationshipId == relationshipId &&
            (x.Status == ClientTaskStatus.Pending || x.Status == ClientTaskStatus.InProgress)).OrderBy(x => x.Id).ToListAsync(token);
        foreach (var task in tasks)
        {
            task.Revise(task.Description, task.DueAt, ClientTaskStatus.Cancelled, task.IsReminderEnabled, now);
            database.ClientTaskVersions.Add(new ClientTaskVersion(task, actor));
        }
    }
}
