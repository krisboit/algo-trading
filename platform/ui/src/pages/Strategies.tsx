import { useEffect, useState } from 'react';
import { db, collection, getDocs, doc, deleteDoc, writeBatch, onSnapshot, getDoc, updateDoc } from '../services/firebase';
import { storage, ref, deleteObject } from '../services/firebase';
import { COLLECTIONS, FIRESTORE_BATCH_LIMIT } from '@algo-trading/shared';
import type { Strategy, StrategyVersion } from '@algo-trading/shared';
import { ChevronDown, ChevronRight, Trash2, ExternalLink, Loader2 } from 'lucide-react';

interface StrategyWithVersions {
  id: string;
  strategy: Strategy;
  versions: (StrategyVersion & { id: string })[];
}

interface DeleteInfo {
  strategyId: string;
  versionId: string;
  versionNum: number;
  linkedJobs: number;
  linkedPasses: number;
}

export default function Strategies() {
  const [strategies, setStrategies] = useState<StrategyWithVersions[]>([]);
  const [expanded, setExpanded] = useState<Set<string>>(new Set());
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [deleteConfirm, setDeleteConfirm] = useState<DeleteInfo | null>(null);
  const [deleting, setDeleting] = useState(false);
  const [githubRepoUrl, setGithubRepoUrl] = useState('');

  useEffect(() => {
    // Load GitHub repo URL from config
    getDoc(doc(db, COLLECTIONS.CONFIG, 'settings')).then((snap) => {
      if (snap.exists()) {
        setGithubRepoUrl(snap.data().githubRepoUrl || '');
      }
    }).catch(() => {});

    const unsub = onSnapshot(
      collection(db, COLLECTIONS.STRATEGIES),
      async (snap) => {
        try {
          const results: StrategyWithVersions[] = [];
          for (const stratDoc of snap.docs) {
            const versionsSnap = await getDocs(
              collection(db, COLLECTIONS.STRATEGIES, stratDoc.id, 'versions')
            );
            const versions = versionsSnap.docs
              .map((vDoc) => ({ id: vDoc.id, ...(vDoc.data() as StrategyVersion) }))
              .sort((a, b) => b.version - a.version);
            results.push({
              id: stratDoc.id,
              strategy: stratDoc.data() as Strategy,
              versions,
            });
          }
          results.sort((a, b) => a.strategy.name.localeCompare(b.strategy.name));
          setStrategies(results);
          setError(null);
        } catch (err) {
          setError('Failed to load strategies');
          console.error(err);
        }
        setLoading(false);
      },
      (err) => {
        setError('Failed to connect to Firestore');
        setLoading(false);
        console.error(err);
      },
    );
    return unsub;
  }, []);

  const toggleExpand = (id: string) => {
    setExpanded((prev) => {
      const next = new Set(prev);
      next.has(id) ? next.delete(id) : next.add(id);
      return next;
    });
  };

  const prepareDelete = async (strategyId: string, versionId: string, versionNum: number) => {
    // Count linked jobs and passes for the warning
    let linkedJobs = 0;
    let linkedPasses = 0;
    try {
      const jobsSnap = await getDocs(collection(db, COLLECTIONS.OPTIMIZATION_JOBS));
      for (const jobDoc of jobsSnap.docs) {
        const data = jobDoc.data();
        if (data.strategyName === strategyId && data.strategyVersion === versionNum) {
          linkedJobs++;
          const passesSnap = await getDocs(
            collection(db, COLLECTIONS.OPTIMIZATION_RESULTS, jobDoc.id, 'passes')
          );
          linkedPasses += passesSnap.size;
        }
      }
    } catch {
      // If counting fails, still allow delete
    }
    setDeleteConfirm({ strategyId, versionId, versionNum, linkedJobs, linkedPasses });
  };

  const handleDeleteVersion = async (info: DeleteInfo) => {
    setDeleting(true);
    try {
      const strat = strategies.find(s => s.id === info.strategyId);
      const version = strat?.versions.find(v => v.id === info.versionId);
      if (!version) throw new Error('Version not found');

      // Delete .ex5 from Storage
      try {
        const storageRef = ref(storage, version.ex5StoragePath);
        await deleteObject(storageRef);
      } catch {
        // File may not exist
      }

      // Delete linked jobs and results in batches
      const jobsSnap = await getDocs(collection(db, COLLECTIONS.OPTIMIZATION_JOBS));
      let batch = writeBatch(db);
      let batchCount = 0;

      const commitBatch = async () => {
        if (batchCount > 0) {
          await batch.commit();
          batch = writeBatch(db);
          batchCount = 0;
        }
      };

      for (const jobDoc of jobsSnap.docs) {
        const jobData = jobDoc.data();
        if (jobData.strategyName === info.strategyId && jobData.strategyVersion === info.versionNum) {
          // Delete result passes
          const passesSnap = await getDocs(
            collection(db, COLLECTIONS.OPTIMIZATION_RESULTS, jobDoc.id, 'passes')
          );
          for (const passDoc of passesSnap.docs) {
            batch.delete(passDoc.ref);
            batchCount++;
            if (batchCount >= FIRESTORE_BATCH_LIMIT - 10) await commitBatch();
          }

          // Delete result doc and job doc
          batch.delete(doc(db, COLLECTIONS.OPTIMIZATION_RESULTS, jobDoc.id));
          batchCount++;
          batch.delete(jobDoc.ref);
          batchCount++;
          if (batchCount >= FIRESTORE_BATCH_LIMIT - 10) await commitBatch();
        }
      }

      // Delete version doc
      batch.delete(doc(db, COLLECTIONS.STRATEGIES, info.strategyId, 'versions', info.versionId));
      batchCount++;
      await commitBatch();

      // Update strategy latestVersion if needed
      if (strat) {
        const remainingVersions = strat.versions.filter(v => v.id !== info.versionId);
        if (remainingVersions.length === 0) {
          await deleteDoc(doc(db, COLLECTIONS.STRATEGIES, info.strategyId));
        } else {
          const newLatest = Math.max(...remainingVersions.map(v => v.version));
          await updateDoc(doc(db, COLLECTIONS.STRATEGIES, info.strategyId), {
            latestVersion: newLatest,
          });
        }
      }

      setDeleteConfirm(null);
    } catch (err) {
      setError(`Delete failed: ${err instanceof Error ? err.message : 'Unknown error'}`);
      console.error('Delete failed:', err);
    } finally {
      setDeleting(false);
    }
  };

  const gitCommitUrl = (hash: string) => {
    if (!hash || hash === 'unknown') return null;
    if (!githubRepoUrl) return null;
    return `${githubRepoUrl}/commit/${hash}`;
  };

  if (loading) {
    return (
      <div className="flex items-center gap-3 text-gray-500">
        <Loader2 size={18} className="animate-spin" /> Loading strategies...
      </div>
    );
  }

  return (
    <div>
      <h2 className="text-2xl font-bold text-white mb-6">Strategies</h2>

      {error && (
        <div className="mb-4 p-3 bg-red-500/10 border border-red-500/30 rounded-lg text-red-400 text-sm">
          {error}
          <button onClick={() => setError(null)} className="ml-3 text-red-500 hover:text-red-300">&times;</button>
        </div>
      )}

      {strategies.length === 0 ? (
        <div className="text-gray-500 bg-gray-900 rounded-xl p-8 text-center">
          No strategies deployed yet. Run <code className="text-blue-400">npm run deploy</code> to upload strategies.
        </div>
      ) : (
        <div className="space-y-3">
          {strategies.map(({ id, strategy, versions }) => (
            <div key={id} className="bg-gray-900 border border-gray-800 rounded-xl overflow-hidden">
              <button
                onClick={() => toggleExpand(id)}
                className="w-full flex items-center justify-between p-4 hover:bg-gray-800/50 transition-colors"
              >
                <div className="flex items-center gap-3">
                  {expanded.has(id) ? (
                    <ChevronDown size={18} className="text-gray-500" />
                  ) : (
                    <ChevronRight size={18} className="text-gray-500" />
                  )}
                  <span className="font-medium text-white">{strategy.name}</span>
                  <span className="text-sm text-gray-500">
                    v{strategy.latestVersion} &middot; {versions.length} version{versions.length !== 1 ? 's' : ''}
                  </span>
                </div>
              </button>

              {expanded.has(id) && (
                <div className="border-t border-gray-800">
                  {strategy.description && (
                    <p className="px-4 py-2 text-sm text-gray-400">{strategy.description}</p>
                  )}
                  <table className="w-full text-sm">
                    <thead>
                      <tr className="text-gray-500 border-b border-gray-800">
                        <th className="px-4 py-2 text-left">Version</th>
                        <th className="px-4 py-2 text-left">Git Commit</th>
                        <th className="px-4 py-2 text-left">Inputs</th>
                        <th className="px-4 py-2 text-left">Created</th>
                        <th className="px-4 py-2 text-left">Actions</th>
                      </tr>
                    </thead>
                    <tbody>
                      {versions.map((v) => {
                        const commitUrl = gitCommitUrl(v.gitHash);
                        return (
                          <tr key={v.id} className="border-b border-gray-800/50">
                            <td className="px-4 py-2 text-white font-mono">v{v.version}</td>
                            <td className="px-4 py-2">
                              {commitUrl ? (
                                <a
                                  href={commitUrl}
                                  target="_blank"
                                  rel="noopener noreferrer"
                                  className="text-blue-400 hover:text-blue-300 flex items-center gap-1"
                                >
                                  {v.gitHash.substring(0, 7)}
                                  <ExternalLink size={12} />
                                </a>
                              ) : (
                                <span className="text-gray-600 font-mono">
                                  {v.gitHash?.substring(0, 7) || 'N/A'}
                                </span>
                              )}
                            </td>
                            <td className="px-4 py-2 text-gray-400">{v.inputs?.length || 0} params</td>
                            <td className="px-4 py-2 text-gray-400">
                              {v.createdAt?.toDate ? v.createdAt.toDate().toLocaleDateString() : 'N/A'}
                            </td>
                            <td className="px-4 py-2">
                              {deleteConfirm?.strategyId === id && deleteConfirm?.versionId === v.id ? (
                                <div className="space-y-1">
                                  <p className="text-xs text-yellow-400">
                                    Delete v{v.version}? This will remove {deleteConfirm.linkedJobs} job{deleteConfirm.linkedJobs !== 1 ? 's' : ''} and {deleteConfirm.linkedPasses} result{deleteConfirm.linkedPasses !== 1 ? 's' : ''}.
                                  </p>
                                  <div className="flex items-center gap-2">
                                    <button
                                      onClick={() => handleDeleteVersion(deleteConfirm)}
                                      disabled={deleting}
                                      className="text-red-400 hover:text-red-300 text-xs font-medium disabled:opacity-50"
                                    >
                                      {deleting ? 'Deleting...' : 'Confirm Delete'}
                                    </button>
                                    <button
                                      onClick={() => setDeleteConfirm(null)}
                                      disabled={deleting}
                                      className="text-gray-500 hover:text-gray-300 text-xs"
                                    >
                                      Cancel
                                    </button>
                                  </div>
                                </div>
                              ) : (
                                <button
                                  onClick={() => prepareDelete(id, v.id, v.version)}
                                  className="text-gray-500 hover:text-red-400 transition-colors"
                                >
                                  <Trash2 size={14} />
                                </button>
                              )}
                            </td>
                          </tr>
                        );
                      })}
                    </tbody>
                  </table>
                </div>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
