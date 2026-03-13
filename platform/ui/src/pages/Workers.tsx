import { useEffect, useState } from 'react';
import { db, collection, onSnapshot, doc, updateDoc } from '../services/firebase';
import { COLLECTIONS, WORKER_OFFLINE_THRESHOLD_MS } from '@algo-trading/shared';
import type { Worker } from '@algo-trading/shared';
import { Circle, Settings, Save } from 'lucide-react';
import Spinner from '../components/Spinner';

interface WorkerDoc {
  id: string;
  data: Worker;
}

export default function Workers() {
  const [workers, setWorkers] = useState<WorkerDoc[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [saveError, setSaveError] = useState<string | null>(null);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [editForm, setEditForm] = useState<{
    name: string;
    prefix: string;
    suffix: string;
    overrides: string;
  }>({ name: '', prefix: '', suffix: '', overrides: '' });

  useEffect(() => {
    const unsub = onSnapshot(
      collection(db, COLLECTIONS.WORKERS),
      (snap) => {
        const docs: WorkerDoc[] = snap.docs
          .map((d) => ({ id: d.id, data: d.data() as Worker }))
          .sort((a, b) => a.data.name.localeCompare(b.data.name));
        setWorkers(docs);
        setLoading(false);
      },
      (err) => {
        console.error('Failed to load workers:', err);
        setError('Failed to load workers. Please refresh.');
        setLoading(false);
      }
    );
    return unsub;
  }, []);

  const isOnline = (w: Worker) => {
    if (!w.lastPing) return false;
    const lastPing = w.lastPing.toDate?.() ? w.lastPing.toDate().getTime() : 0;
    return Date.now() - lastPing < WORKER_OFFLINE_THRESHOLD_MS;
  };

  const relativeTime = (timestamp: { toDate?: () => Date } | null) => {
    if (!timestamp?.toDate) return 'Never';
    const diff = Date.now() - timestamp.toDate().getTime();
    if (diff < 60000) return `${Math.floor(diff / 1000)}s ago`;
    if (diff < 3600000) return `${Math.floor(diff / 60000)}m ago`;
    if (diff < 86400000) return `${Math.floor(diff / 3600000)}h ago`;
    return `${Math.floor(diff / 86400000)}d ago`;
  };

  const formatRuntime = (seconds: number) => {
    const hours = Math.floor(seconds / 3600);
    if (hours > 24) return `${Math.floor(hours / 24)}d ${hours % 24}h`;
    return `${hours}h`;
  };

  const startEdit = (w: WorkerDoc) => {
    setEditingId(w.id);
    setEditForm({
      name: w.data.name,
      prefix: w.data.symbolMapping?.prefix || '',
      suffix: w.data.symbolMapping?.suffix || '',
      overrides: JSON.stringify(w.data.symbolMapping?.overrides || {}, null, 2),
    });
  };

  const saveEdit = async (workerId: string) => {
    setSaveError(null);
    try {
      let overrides = {};
      try {
        overrides = JSON.parse(editForm.overrides);
      } catch {
        setSaveError('Invalid JSON in Symbol Overrides field');
        return;
      }

      await updateDoc(doc(db, COLLECTIONS.WORKERS, workerId), {
        name: editForm.name,
        'symbolMapping.prefix': editForm.prefix,
        'symbolMapping.suffix': editForm.suffix,
        'symbolMapping.overrides': overrides,
      });
      setEditingId(null);
    } catch (err) {
      console.error('Failed to save:', err);
      setSaveError(err instanceof Error ? err.message : 'Failed to save worker config');
    }
  };

  if (loading) {
    return <Spinner />;
  }

  if (error) {
    return (
      <div className="bg-red-500/10 border border-red-500/30 rounded-lg p-4 text-red-400">
        {error}
      </div>
    );
  }

  return (
    <div>
      <h2 className="text-2xl font-bold text-white mb-6">Workers</h2>

      {workers.length === 0 ? (
        <div className="text-gray-500 bg-gray-900 rounded-xl p-8 text-center">
          No workers registered. Start a worker app to register.
        </div>
      ) : (
        <div className="grid gap-4">
          {workers.map(({ id, data }) => (
            <div key={id} className="bg-gray-900 border border-gray-800 rounded-xl p-5">
              <div className="flex items-start justify-between">
                <div className="flex items-center gap-3">
                  <Circle
                    size={10}
                    fill={isOnline(data) ? '#22c55e' : '#ef4444'}
                    className={isOnline(data) ? 'text-green-500' : 'text-red-500'}
                  />
                  <div>
                    <h3 className="text-white font-medium">{data.name || id}</h3>
                    <p className="text-sm text-gray-500">
                      {data.hostname || 'Unknown host'} &middot; Last ping: {relativeTime(data.lastPing)}
                    </p>
                  </div>
                </div>
                <button
                  onClick={() => (editingId === id ? setEditingId(null) : startEdit({ id, data }))}
                  className="text-gray-500 hover:text-gray-300"
                >
                  <Settings size={16} />
                </button>
              </div>

              <div className="mt-4 grid grid-cols-2 md:grid-cols-4 gap-4 text-sm">
                <div>
                  <p className="text-gray-500">Current Job</p>
                  <p className="text-white">{data.currentJobId || 'Idle'}</p>
                </div>
                <div>
                  <p className="text-gray-500">MT5 Version</p>
                  <p className="text-white">{data.mt5Version || 'N/A'}</p>
                </div>
                <div>
                  <p className="text-gray-500">Jobs Completed</p>
                  <p className="text-white">{data.stats?.jobsCompleted || 0}</p>
                </div>
                <div>
                  <p className="text-gray-500">Total Runtime</p>
                  <p className="text-white">{formatRuntime(data.stats?.totalRuntime || 0)}</p>
                </div>
              </div>

              {/* Symbol mapping display */}
              <div className="mt-3 text-sm">
                <p className="text-gray-500">Symbol Mapping</p>
                <p className="text-gray-300 font-mono text-xs">
                  prefix="{data.symbolMapping?.prefix || ''}" suffix="{data.symbolMapping?.suffix || ''}"
                  {data.symbolMapping?.overrides && Object.keys(data.symbolMapping.overrides).length > 0 && (
                    <span> overrides: {JSON.stringify(data.symbolMapping.overrides)}</span>
                  )}
                </p>
              </div>

              {/* Supported symbols */}
              {data.supportedSymbols && data.supportedSymbols.length > 0 && (
                <div className="mt-2 flex flex-wrap gap-1">
                  {data.supportedSymbols.map((sym) => (
                    <span
                      key={sym}
                      className="px-2 py-0.5 bg-gray-800 text-gray-400 rounded text-xs"
                    >
                      {sym}
                    </span>
                  ))}
                </div>
              )}

              {/* Edit form */}
              {editingId === id && (
                <div className="mt-4 p-4 bg-gray-800/50 rounded-lg space-y-3">
                  <div>
                    <label className="block text-xs text-gray-500 mb-1">Worker Name</label>
                    <input
                      type="text"
                      value={editForm.name}
                      onChange={(e) => setEditForm((f) => ({ ...f, name: e.target.value }))}
                      className="w-full bg-gray-800 border border-gray-700 rounded px-3 py-1.5 text-white text-sm"
                    />
                  </div>
                  <div className="grid grid-cols-2 gap-3">
                    <div>
                      <label className="block text-xs text-gray-500 mb-1">Symbol Prefix</label>
                      <input
                        type="text"
                        value={editForm.prefix}
                        onChange={(e) => setEditForm((f) => ({ ...f, prefix: e.target.value }))}
                        className="w-full bg-gray-800 border border-gray-700 rounded px-3 py-1.5 text-white text-sm"
                      />
                    </div>
                    <div>
                      <label className="block text-xs text-gray-500 mb-1">Symbol Suffix</label>
                      <input
                        type="text"
                        value={editForm.suffix}
                        onChange={(e) => setEditForm((f) => ({ ...f, suffix: e.target.value }))}
                        className="w-full bg-gray-800 border border-gray-700 rounded px-3 py-1.5 text-white text-sm"
                      />
                    </div>
                  </div>
                  <div>
                    <label className="block text-xs text-gray-500 mb-1">Symbol Overrides (JSON)</label>
                    <textarea
                      value={editForm.overrides}
                      onChange={(e) => setEditForm((f) => ({ ...f, overrides: e.target.value }))}
                      rows={3}
                      className="w-full bg-gray-800 border border-gray-700 rounded px-3 py-1.5 text-white text-sm font-mono"
                    />
                  </div>
                  {saveError && (
                    <div className="bg-red-500/10 border border-red-500/30 rounded px-3 py-2 text-red-400 text-sm">
                      {saveError}
                    </div>
                  )}
                  <button
                    onClick={() => saveEdit(id)}
                    className="flex items-center gap-2 px-3 py-1.5 bg-blue-600 hover:bg-blue-700 text-white rounded text-sm"
                  >
                    <Save size={14} /> Save
                  </button>
                </div>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
