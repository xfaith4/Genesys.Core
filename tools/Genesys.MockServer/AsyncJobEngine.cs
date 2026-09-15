using System.Collections.Concurrent;
using System.Text.Json.Nodes;

namespace Genesys.MockServer;

/// <summary>
/// Simulates Genesys async job flows: submit → poll (QUEUED/RUNNING) → FULFILLED.
/// Thread-safe. Shared across all requests via DI singleton.
/// </summary>
public sealed class AsyncJobEngine
{
    private readonly ConcurrentDictionary<string, AsyncJob> _jobs = new(StringComparer.Ordinal);
    private readonly int _pollingRoundsBeforeFulfilled;

    public AsyncJobEngine(int pollingRoundsBeforeFulfilled = 2)
    {
        _pollingRoundsBeforeFulfilled = pollingRoundsBeforeFulfilled;
    }

    /// <summary>Creates a new demo job and returns its ID.</summary>
    public string CreateJob(AsyncJobKind kind)
    {
        var jobId = $"demo-{kind.ToString().ToLower()}-job-{Guid.NewGuid():N}";
        _jobs[jobId] = new AsyncJob(jobId, kind, 0);
        return jobId;
    }

    /// <summary>
    /// Returns the current state of a job and increments its poll counter.
    /// Terminal state is FULFILLED once poll count reaches the configured threshold.
    /// </summary>
    public string PollJob(string jobId)
    {
        if (!_jobs.TryGetValue(jobId, out var job))
            return "NOT_FOUND";

        // Atomically increment poll count
        var updatedJob = _jobs.AddOrUpdate(
            jobId,
            _ => job with { PollCount = 1 },
            (_, existing) => existing with { PollCount = existing.PollCount + 1 });

        if (updatedJob.PollCount < _pollingRoundsBeforeFulfilled)
        {
            return updatedJob.PollCount == 1 ? "QUEUED" : "RUNNING";
        }

        return "FULFILLED";
    }

    public bool JobExists(string jobId) => _jobs.ContainsKey(jobId);
}

public enum AsyncJobKind { Analytics, Audit, Users }

internal sealed record AsyncJob(string JobId, AsyncJobKind Kind, int PollCount);
