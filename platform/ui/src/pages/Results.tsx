import { useEffect, useState } from 'react';
import { useParams, Link } from 'react-router-dom';
import { db, doc, getDoc, collection, getDocs } from '../services/firebase';
import { COLLECTIONS } from '@algo-trading/shared';
import type { OptimizationJob, OptimizationPass } from '@algo-trading/shared';
import { ArrowLeft, ArrowUpDown } from 'lucide-react';
import Spinner from '../components/Spinner';

type SortKey = 'profit' | 'profitFactor' | 'drawdownPercent' | 'trades' | 'customCriterion' | 'sharpeRatio' | 'recoveryFactor';

export default function Results() {
  const { jobId } = useParams<{ jobId: string }>();
  const [job, setJob] = useState<OptimizationJob | null>(null);
  const [passes, setPasses] = useState<OptimizationPass[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [sortKey, setSortKey] = useState<SortKey>('customCriterion');
  const [sortDesc, setSortDesc] = useState(true);

  useEffect(() => {
    if (!jobId) return;

    const load = async () => {
      try {
        const jobDoc = await getDoc(doc(db, COLLECTIONS.OPTIMIZATION_JOBS, jobId));
        if (jobDoc.exists()) {
          setJob(jobDoc.data() as OptimizationJob);
        }

        const passesSnap = await getDocs(
          collection(db, COLLECTIONS.OPTIMIZATION_RESULTS, jobId, 'passes')
        );
        const passData = passesSnap.docs.map((d) => d.data() as OptimizationPass);
        setPasses(passData);
      } catch (err) {
        console.error('Failed to load results:', err);
        setError('Failed to load optimization results. Please try again.');
      }
      setLoading(false);
    };

    load();
  }, [jobId]);

  const handleSort = (key: SortKey) => {
    if (sortKey === key) {
      setSortDesc(!sortDesc);
    } else {
      setSortKey(key);
      setSortDesc(true);
    }
  };

  const sortedPasses = [...passes].sort((a, b) => {
    const aVal = a[sortKey] ?? 0;
    const bVal = b[sortKey] ?? 0;
    return sortDesc ? (bVal as number) - (aVal as number) : (aVal as number) - (bVal as number);
  });

  // Collect all unique input parameter names
  const inputNames = Array.from(
    new Set(passes.flatMap((p) => Object.keys(p.inputs || {})))
  ).sort();

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

  if (!job) {
    return <div className="text-red-400">Job not found.</div>;
  }

  const SortableHeader = ({ label, field }: { label: string; field: SortKey }) => (
    <th
      className="px-3 py-2 text-left cursor-pointer hover:text-gray-300 select-none"
      onClick={() => handleSort(field)}
    >
      <div className="flex items-center gap-1">
        {label}
        {sortKey === field && <ArrowUpDown size={12} className="text-blue-400" />}
      </div>
    </th>
  );

  return (
    <div>
      <div className="flex items-center gap-4 mb-6">
        <Link to="/jobs" className="text-gray-500 hover:text-gray-300">
          <ArrowLeft size={20} />
        </Link>
        <div>
          <h2 className="text-2xl font-bold text-white">
            {job.strategyName} v{job.strategyVersion}
          </h2>
          <p className="text-gray-500 text-sm">
            {job.symbol} &middot; {job.timeframe} &middot; {job.fromDate} to {job.toDate}
            &middot; {passes.length} profitable passes
          </p>
        </div>
      </div>

      {/* Summary cards */}
      {job.resultSummary && (
        <div className="grid grid-cols-2 md:grid-cols-4 gap-3 mb-6">
          <div className="bg-gray-900 border border-gray-800 rounded-lg p-3">
            <p className="text-xs text-gray-500">Best Profit</p>
            <p className="text-lg font-bold text-green-400">${job.resultSummary.bestProfit.toFixed(2)}</p>
          </div>
          <div className="bg-gray-900 border border-gray-800 rounded-lg p-3">
            <p className="text-xs text-gray-500">Best PF</p>
            <p className="text-lg font-bold text-white">{job.resultSummary.bestProfitFactor.toFixed(2)}</p>
          </div>
          <div className="bg-gray-900 border border-gray-800 rounded-lg p-3">
            <p className="text-xs text-gray-500">Best Custom</p>
            <p className="text-lg font-bold text-blue-400">{job.resultSummary.bestCustomCriterion.toFixed(1)}</p>
          </div>
          <div className="bg-gray-900 border border-gray-800 rounded-lg p-3">
            <p className="text-xs text-gray-500">Best DD%</p>
            <p className="text-lg font-bold text-yellow-400">{job.resultSummary.bestDrawdown.toFixed(1)}%</p>
          </div>
        </div>
      )}

      {/* Results table */}
      {passes.length === 0 ? (
        <div className="text-gray-500 bg-gray-900 rounded-xl p-8 text-center">
          No profitable passes found for this optimization run.
        </div>
      ) : (
        <div className="bg-gray-900 border border-gray-800 rounded-xl overflow-x-auto">
          <table className="w-full text-sm whitespace-nowrap">
            <thead>
              <tr className="text-gray-500 border-b border-gray-800">
                <th className="px-3 py-2 text-left">#</th>
                <SortableHeader label="Profit" field="profit" />
                <SortableHeader label="PF" field="profitFactor" />
                <SortableHeader label="DD%" field="drawdownPercent" />
                <SortableHeader label="Trades" field="trades" />
                <SortableHeader label="Custom" field="customCriterion" />
                <SortableHeader label="Sharpe" field="sharpeRatio" />
                <SortableHeader label="Recovery" field="recoveryFactor" />
                {inputNames.map((name) => (
                  <th key={name} className="px-3 py-2 text-left text-gray-600">
                    {name}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {sortedPasses.map((pass, i) => (
                <tr key={i} className="border-b border-gray-800/50 hover:bg-gray-800/30">
                  <td className="px-3 py-2 text-gray-600">{i + 1}</td>
                  <td className="px-3 py-2 text-green-400 font-mono">{pass.profit.toFixed(2)}</td>
                  <td className="px-3 py-2 text-white font-mono">{pass.profitFactor.toFixed(2)}</td>
                  <td className="px-3 py-2 text-yellow-400 font-mono">{pass.drawdownPercent.toFixed(1)}</td>
                  <td className="px-3 py-2 text-gray-300 font-mono">{pass.trades}</td>
                  <td className="px-3 py-2 text-blue-400 font-mono">{pass.customCriterion.toFixed(1)}</td>
                  <td className="px-3 py-2 text-gray-300 font-mono">{pass.sharpeRatio.toFixed(2)}</td>
                  <td className="px-3 py-2 text-gray-300 font-mono">{pass.recoveryFactor.toFixed(2)}</td>
                  {inputNames.map((name) => (
                    <td key={name} className="px-3 py-2 text-gray-400 font-mono">
                      {pass.inputs?.[name] !== undefined ? String(pass.inputs[name]) : '-'}
                    </td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
