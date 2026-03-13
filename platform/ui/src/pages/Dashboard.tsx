import { useEffect, useState } from 'react';
import { db, collection, getDocs, onSnapshot } from '../services/firebase';
import { COLLECTIONS, WORKER_OFFLINE_THRESHOLD_MS } from '@algo-trading/shared';
import { Activity, CheckCircle, Clock, AlertTriangle, Server, BookOpen } from 'lucide-react';
import Spinner from '../components/Spinner';

interface Stats {
  totalStrategies: number;
  pendingJobs: number;
  runningJobs: number;
  completedJobs: number;
  failedJobs: number;
  onlineWorkers: number;
  totalWorkers: number;
}

export default function Dashboard() {
  const [stats, setStats] = useState<Stats>({
    totalStrategies: 0,
    pendingJobs: 0,
    runningJobs: 0,
    completedJobs: 0,
    failedJobs: 0,
    onlineWorkers: 0,
    totalWorkers: 0,
  });
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const loadStats = async () => {
      try {
        const strategiesSnap = await getDocs(collection(db, COLLECTIONS.STRATEGIES));
        const workersSnap = await getDocs(collection(db, COLLECTIONS.WORKERS));
        const now = Date.now();
        let onlineWorkers = 0;
        workersSnap.docs.forEach((doc) => {
          const data = doc.data();
          if (data.lastPing?.toDate) {
            const lastPing = data.lastPing.toDate().getTime();
            if (now - lastPing < WORKER_OFFLINE_THRESHOLD_MS) onlineWorkers++;
          }
        });
        setStats((prev) => ({
          ...prev,
          totalStrategies: strategiesSnap.size,
          onlineWorkers,
          totalWorkers: workersSnap.size,
        }));
      } catch (err) {
        setError('Failed to load dashboard stats');
        console.error(err);
      }
    };

    loadStats();

    const unsub = onSnapshot(
      collection(db, COLLECTIONS.OPTIMIZATION_JOBS),
      (snap) => {
        const counts = { pending: 0, running: 0, completed: 0, failed: 0 };
        snap.docs.forEach((doc) => {
          const status = doc.data().status;
          if (status === 'pending') counts.pending++;
          else if (status === 'running' || status === 'claimed') counts.running++;
          else if (status === 'completed') counts.completed++;
          else if (status === 'failed') counts.failed++;
        });
        setStats((prev) => ({
          ...prev,
          pendingJobs: counts.pending,
          runningJobs: counts.running,
          completedJobs: counts.completed,
          failedJobs: counts.failed,
        }));
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

  if (loading) {
    return <Spinner text="Loading dashboard..." />;
  }

  const cards = [
    { label: 'Strategies', value: stats.totalStrategies, icon: BookOpen, color: 'text-blue-400' },
    { label: 'Pending Jobs', value: stats.pendingJobs, icon: Clock, color: 'text-yellow-400' },
    { label: 'Running Jobs', value: stats.runningJobs, icon: Activity, color: 'text-blue-400' },
    { label: 'Completed Jobs', value: stats.completedJobs, icon: CheckCircle, color: 'text-green-400' },
    { label: 'Failed Jobs', value: stats.failedJobs, icon: AlertTriangle, color: 'text-red-400' },
    { label: 'Workers Online', value: `${stats.onlineWorkers}/${stats.totalWorkers}`, icon: Server, color: 'text-emerald-400' },
  ];

  return (
    <div>
      <h2 className="text-2xl font-bold text-white mb-6">Dashboard</h2>

      {error && (
        <div className="mb-4 p-3 bg-red-500/10 border border-red-500/30 rounded-lg text-red-400 text-sm">
          {error}
        </div>
      )}

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        {cards.map(({ label, value, icon: Icon, color }) => (
          <div key={label} className="bg-gray-900 border border-gray-800 rounded-xl p-5">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-gray-500">{label}</p>
                <p className="text-3xl font-bold text-white mt-1">{value}</p>
              </div>
              <Icon className={color} size={28} />
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
