using System.Security.Cryptography;
using System.Text;
using Microsoft.EntityFrameworkCore;
using Npgsql;
using OtpNet;
using SmartNutrition.Api.Data;
using SmartNutrition.Api.Features.Dietitians;
using SmartNutrition.Api.Models;

namespace SmartNutrition.Api.Features.Relationships;

public sealed class RelationshipService(AppDbContext database, RelationshipAccessService access,
    RelationshipMutationLimits limits, TimeProvider clock)
{
    public async Task<InvitationCodeResponse> CreateInvitationAsync(ProfileIdentity actor, string ip, CancellationToken token)
    {
        if (actor.Role != UserRole.Dietitian || actor.DietitianId is null || !actor.IsDietitianVerified) throw new ResourceOperationException(403);
        limits.Acquire("invite", actor.UserId, ip);
        await using var transaction = await database.Database.BeginTransactionAsync(token);
        await access.LockActorAsync(actor, token);
        var profile = await database.DietitianProfiles.FromSqlInterpolated($"SELECT * FROM dietitian_profiles WHERE id = {actor.DietitianId.Value} FOR UPDATE").SingleAsync(token);
        if (!profile.IsVerified) throw new ResourceOperationException(403);
        var code = Base32Encoding.ToString(RandomNumberGenerator.GetBytes(10));
        var expiry = RecordTime.Normalize(clock.GetUtcNow()).AddHours(24);
        profile.SetInvitation(Hash(code), expiry);
        await database.SaveChangesAsync(token); await transaction.CommitAsync(token);
        return new(code, expiry);
    }

    public async Task<RelationshipResponse> RequestAsync(ProfileIdentity actor, RelationshipRequest request, string ip, CancellationToken token)
    {
        if (actor.Role != UserRole.Client || actor.ClientId is null) throw new ResourceOperationException(403);
        if ((request.DietitianId is null) == (request.InvitationCode is null) || request.DietitianId == Guid.Empty)
            throw new ResourceOperationException(400);
        limits.Acquire("request", actor.UserId, ip);
        await using var transaction = await database.Database.BeginTransactionAsync(token);
        await access.LockActorAsync(actor, token); await access.LockClientAsync(actor.ClientId.Value, token);
        if (await database.DietitianClientRelationships.AnyAsync(x => x.ClientId == actor.ClientId && x.Status == RelationshipStatus.Active, token))
            throw new ResourceOperationException(409);
        var code = request.InvitationCode?.Trim().ToUpperInvariant();
        Guid? targetId = request.DietitianId;
        if (code is not null)
        {
            if (code.Length != 16 || code.Any(c => c is not (>= 'A' and <= 'Z') and not (>= '2' and <= '7'))) throw new ResourceOperationException(422);
            var hash = Hash(code);
            targetId = await database.DietitianProfiles.Where(x => x.InvitationCodeHash == hash).Select(x => (Guid?)x.Id).SingleOrDefaultAsync(token);
        }
        if (targetId is null) throw new ResourceOperationException(422);
        var profile = await database.DietitianProfiles.FromSqlInterpolated($"SELECT * FROM dietitian_profiles WHERE id = {targetId.Value} FOR UPDATE").SingleOrDefaultAsync(token);
        if (profile is null || !profile.IsVerified || !await database.Users.AnyAsync(x => x.Id == profile.UserId && x.Role == UserRole.Dietitian && x.IsEmailVerified, token))
            throw new ResourceOperationException(code is null ? 404 : 422);
        if (code is not null && (profile.InvitationCodeHash != Hash(code) || profile.InvitationCodeExpiresAt <= clock.GetUtcNow() || profile.InvitationCodeExpiresAt is null))
            throw new ResourceOperationException(422);
        if (await database.DietitianClientRelationships.AnyAsync(x => x.ClientId == actor.ClientId && x.DietitianId == profile.Id && x.Status == RelationshipStatus.Pending, token))
            throw new ResourceOperationException(409);
        var relationship = new DietitianClientRelationship(actor.ClientId.Value, profile.Id, clock.GetUtcNow());
        database.DietitianClientRelationships.Add(relationship);
        if (code is not null) profile.SetInvitation(null, null);
        try { await database.SaveChangesAsync(token); }
        catch (DbUpdateException error) when (error.InnerException is PostgresException { SqlState: PostgresErrorCodes.UniqueViolation })
        { throw new ResourceOperationException(409); }
        await transaction.CommitAsync(token);
        return RelationshipResponse.From(relationship);
    }

    internal IQueryable<DietitianClientRelationship> Own(ProfileIdentity actor) => database.DietitianClientRelationships.AsNoTracking()
        .Where(x => actor.Role == UserRole.Client ? x.ClientId == actor.ClientId : x.DietitianId == actor.DietitianId);

    public async Task<RelationshipResponse> TransitionAsync(ProfileIdentity actor, Guid id, string action, CancellationToken token)
    {
        var candidate = await Own(actor).SingleOrDefaultAsync(x => x.Id == id, token) ?? throw new ResourceOperationException(404);
        if (action != "end" && (actor.Role != UserRole.Dietitian || !actor.IsDietitianVerified)) throw new ResourceOperationException(403);
        await using var transaction = await database.Database.BeginTransactionAsync(token);
        await access.LockActorAsync(actor, token); await access.LockClientAsync(candidate.ClientId, token);
        var row = await database.DietitianClientRelationships.FromSqlInterpolated($"SELECT * FROM dietitian_client_relationships WHERE id = {id} FOR UPDATE").SingleAsync(token);
        var target = action == "accept" ? RelationshipStatus.Active : action == "reject" ? RelationshipStatus.Rejected : RelationshipStatus.Ended;
        if (row.Status != target)
        {
            if (action == "end")
            {
                if (row.Status is not (RelationshipStatus.Active or RelationshipStatus.Pending)) throw new ResourceOperationException(409);
                row.End(clock.GetUtcNow());
            }
            else
            {
                if (row.Status != RelationshipStatus.Pending) throw new ResourceOperationException(409);
                if (action == "accept" && await database.DietitianClientRelationships.AnyAsync(x => x.ClientId == row.ClientId && x.Status == RelationshipStatus.Active, token))
                    throw new ResourceOperationException(409);
                // Recheck expert verification inside the write transaction as well.
                if (!await database.DietitianProfiles.AnyAsync(x => x.Id == actor.DietitianId && x.IsVerified, token)) throw new ResourceOperationException(403);
                row.Respond(target, clock.GetUtcNow());
            }
            await database.SaveChangesAsync(token);
        }
        await transaction.CommitAsync(token); return RelationshipResponse.From(row);
    }

    private static string Hash(string code) => Convert.ToHexString(SHA256.HashData(Encoding.ASCII.GetBytes(code)));
}
