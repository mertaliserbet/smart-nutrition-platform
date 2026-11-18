using Microsoft.EntityFrameworkCore;
using SmartNutrition.Api.Data;
using SmartNutrition.Api.Features.Relationships;

namespace SmartNutrition.Api.Features.PersonalNutritionTargets;

public sealed class PersonalNutritionTargetService(AppDbContext database, RelationshipAccessService access)
{
    public async Task<PersonalNutritionTargetResponse> GetAsync(Guid clientId, CancellationToken token) =>
        PersonalNutritionTargetResponse.From(await database.PersonalNutritionTargets.AsNoTracking().SingleOrDefaultAsync(x => x.ClientId == clientId, token));

    public async Task<PersonalNutritionTargetResponse> PatchAsync(ProfileIdentity actor, PatchPersonalNutritionTargetRequest request, CancellationToken token)
    {
        await using var transaction = await database.Database.BeginTransactionAsync(token);
        // Existing User -> ClientProfile lock order also serializes concurrent first-time upserts.
        await access.LockActorAsync(actor, token);
        var clientId = actor.ClientId!.Value;
        await access.LockClientAsync(clientId, token);
        var row = await database.PersonalNutritionTargets.SingleOrDefaultAsync(x => x.ClientId == clientId, token);
        var created = row is null;
        row ??= new PersonalNutritionTarget(clientId);
        request.Apply(row);
        if (created) database.PersonalNutritionTargets.Add(row);
        await database.SaveChangesAsync(token);
        await transaction.CommitAsync(token);
        return PersonalNutritionTargetResponse.From(row);
    }
}
