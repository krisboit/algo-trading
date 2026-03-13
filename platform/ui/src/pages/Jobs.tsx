import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { db, collection, onSnapshot, doc, updateDoc } from '../services/firebase';
import { COLLECTIONS, JOB_STATUS_LABELS } from '@algo-trading/shared';
import type { OptimizationJob, JobStatus } from '@algo-trading/shared';
import { XCircle, RotateCcw, Eye } from 'lucide-react';
import Spinner from '../components/Spinner';

interface JobDoc {
  id: string;
  data: OptimizationJob;
}

const STATUS_FILTERS: JobStatus[] = ['pending', 'claimed', 'running', 'completed', 'failed', 'cancelled'];

export default function Jobs() {
  const [jobs, setJobs] = useState<JobDoc[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [filter, setFilter] = useState<JobStatus | 'all'>('all');

  useEffect(() => {
    const unsub = onSnapshot(
      collection(db, COLLECTIONS.OPTIMIZATION_JOBS),
      (snap) => {
        const docs: JobDoc[] = snap.docs
          .map((d) => ({ id: d.id, data: d.data() as OptimizationJob }))
          .sort((a, b) => {
            const aTime = a.data.createdAt?.seconds ?? 0;
            const bTime = b.data.createdAt?.seconds ?? 0;
            return bTime - aTime;
          });
        setJobs(docs);
        setLoading(false);
      },
      (err) => {
        setError('Failed to load jobs');
        setLoading(false);
        console.error(err);
      },
    );
    return unsub;
  }, []);

  const cancelJob = async (jobId: string) => {
    try {
      await updateDoc(doc(db, COLLECTIONS.OPTIMIZATION_JOBS, jobId), {
        status: 'cancelled',
      });
    } catch (err) {
      setError(`Failed to cancel job: ${err instanceof Error ? err.message : 'Unknown error'}`);
    }
  };

  const retryJob = async (jobId: string) => {
    try {
      await updateDoc(doc(db, COLLECTIONS.OPTIMIZATION_JOBS, jobId), {
        status: 'pending',
        claimedBy: null,
        claimedAt: null,
        startedAt: null,
        completedAt: null,
        duration: null,
        error: null,
        retryCount: 0,
      });
    } catch (err) {
      setError(`Failed to retry job: ${err instanceof Error ? err.message : 'Unknown error'}`);
    }
  };

  const filteredJobs = filter === 'all' ? jobs : jobs.filter((j) => j.data.status === filter);

  const statusBadge = (status: string) => {
    const colorMap: Record<string, string> = {
      pending: 'bg-yellow-500/20 text-yellow-400',
      claimed: 'bg-blue-500/20 text-blue-400',
      running: 'bg-blue-500/20 text-blue-400',
      completed: 'bg-green-500/20 text-green-400',
      failed: 'bg-red-500/20 text-red-400',
      cancelled: 'bg-gray-500/20 text-gray-400',
    };
    return (
      <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${colorMap[status] || ''}`}>
        {JOB_STATUS_LABELS[status] || status}
      </span>
    );
  };

  const formatDuration = (seconds: number | null) => {
    if (!seconds) return '-';
    const hrs = Math.floor(seconds / 3600);
    const mins = Math.floor((seconds % 3600) / 60);
    const secs = seconds % 60;
    if (hrs > 0) return `${hrs}h ${mins}m`;
    if (mins > 0) return `${mins}m ${secs}s`;
    return `${secs}s`;
  };

  if (loading) {
    return <Spinner text="Loading jobs..." />;
  }

  return (
    <div>
      <h2 className="text-2xl font-bold text-white mb-6">Optimization Jobs</h2>

      {error && (
        <div className="mb-4 p-3 bg-red-500/10 border border-red-500/30 rounded-lg text-red-400 text-sm">
          {error}
          <button onClick={() => setError(null)} className="ml-3 text-red-500 hover:text-red-300">&times;</button>
        </div>
      )}

      {/* Status filters */}
      <div className="flex flex-wrap gap-2 mb-6">
        <button
          onClick={() => setFilter('all')}
          className={`px-3 py-1.5 rounded-lg text-sm font-medium ${
            filter === 'all' ? 'bg-blue-600 text-white' : 'bg-gray-800 text-gray-400 hover:bg-gray-700'
          }`}
        >
          All ({jobs.length})
        </button>
        {STATUS_FILTERS.map((s) => {
          const count = jobs.filter((j) => j.data.status === s).length;
          return (
            <button
              key={s}
              onClick={() => setFilter(s)}
              className={`px-3 py-1.5 rounded-lg text-sm font-medium ${
                filter === s ? 'bg-blue-600 text-white' : 'bg-gray-800 text-gray-400 hover:bg-gray-700'
              }`}
            >
              {JOB_STATUS_LABELS[s]} ({count})
            </button>
          );
        })}
      </div>

      {filteredJobs.length === 0 ? (
        <div className="text-gray-500 bg-gray-900 rounded-xl p-8 text-center">
          No jobs found.
        </div>
      ) : (
        <div className="bg-gray-900 border border-gray-800 rounded-xl overflow-hidden">
          <table className="w-full text-sm">
            <thead>
              <tr className="text-gray-500 border-b border-gray-800">
                <th className="px-4 py-3 text-left">Strategy</th>
                <th className="px-4 py-3 text-left">Symbol</th>
                <th className="px-4 py-3 text-left">TF</th>
                <th className="px-4 py-3 text-left">Status</th>
                <th className="px-4 py-3 text-left">Worker</th>
                <th className="px-4 py-3 text-left">Duration</th>
                <th className="px-4 py-3 text-left">Results</th>
                <th className="px-4 py-3 text-left">Actions</th>
              </tr>
            </thead>
            <tbody>
              {filteredJobs.map(({ id, data }) => (
                <tr key={id} className="border-b border-gray-800/50 hover:bg-gray-800/30">
                  <td className="px-4 py-3">
                    <span className="text-white">{data.strategyName}</span>
                    <span className="text-gray-500 ml-1">v{data.strategyVersion}</span>
                  </td>
                  <td className="px-4 py-3 text-gray-300">{data.symbol}</td>
                  <td className="px-4 py-3 text-gray-300">{data.timeframe}</td>
                  <td className="px-4 py-3">{statusBadge(data.status)}</td>
                  <td className="px-4 py-3 text-gray-400">{data.claimedBy || '-'}</td>
                  <td className="px-4 py-3 text-gray-400">{formatDuration(data.duration)}</td>
                  <td className="px-4 py-3 text-gray-400">
                    {data.resultSummary ? (
                      <span className="text-green-400">
                        {data.resultSummary.profitablePasses} passes
                      </span>
                    ) : data.error ? (
                      <span className="text-red-400 text-xs truncate max-w-32 inline-block" title={data.error}>
                        {data.error}
                      </span>
                    ) : (
                      '-'
                    )}
                  </td>
                  <td className="px-4 py-3">
                    <div className="flex items-center gap-2">
                      {data.status === 'completed' && data.resultSummary && (
                        <Link
                          to={`/results/${id}`}
                          className="text-blue-400 hover:text-blue-300"
                          title="View results"
                        >
                          <Eye size={14} />
                        </Link>
                      )}
                      {data.status === 'pending' && (
                        <button
                          onClick={() => cancelJob(id)}
                          className="text-gray-500 hover:text-red-400"
                          title="Cancel"
                        >
                          <XCircle size={14} />
                        </button>
                      )}
                      {data.status === 'failed' && (
                        <button
                          onClick={() => retryJob(id)}
                          className="text-gray-500 hover:text-blue-400"
                          title="Retry"
                        >
                          <RotateCcw size={14} />
                        </button>
                      )}
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
