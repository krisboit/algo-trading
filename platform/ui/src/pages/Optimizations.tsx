import { useEffect, useState } from 'react';
import { db, collection, getDocs, doc, setDoc, serverTimestamp } from '../services/firebase';
import { COLLECTIONS, MT5_TIMEFRAMES, DEFAULT_SYMBOLS, DEFAULT_DEPOSIT, DEFAULT_LEVERAGE, DEFAULT_MAX_RETRIES, OPTIMIZATION_MODE_LABELS, TICK_MODEL_LABELS, OPTIMIZATION_CRITERION_LABELS } from '@algo-trading/shared';
import type { Strategy, StrategyVersion, StrategyInput, InputOverride, OptimizationMode, TickModel, OptimizationCriterion } from '@algo-trading/shared';
import Spinner from '../components/Spinner';

interface StrategyOption {
  id: string;
  name: string;
  versions: (StrategyVersion & { id: string })[];
}

export default function Optimizations() {
  const [strategies, setStrategies] = useState<StrategyOption[]>([]);
  const [symbols, setSymbols] = useState<{ name: string; description: string }[]>([]);
  const [loading, setLoading] = useState(true);

  // Wizard state
  const [step, setStep] = useState(1);
  const [selectedStrategy, setSelectedStrategy] = useState('');
  const [selectedVersion, setSelectedVersion] = useState<number | null>(null);
  const [selectedSymbols, setSelectedSymbols] = useState<string[]>([]);
  const [selectedTimeframes, setSelectedTimeframes] = useState<string[]>([]);
  const [fromDate, setFromDate] = useState('2025.01.01');
  const [toDate, setToDate] = useState('2026.03.01');
  const [deposit, setDeposit] = useState(DEFAULT_DEPOSIT);
  const [leverage, setLeverage] = useState(DEFAULT_LEVERAGE);
  const [optimizationMode, setOptimizationMode] = useState<OptimizationMode>(2);
  const [model, setModel] = useState<TickModel>(4);
  const [criterion, setCriterion] = useState<OptimizationCriterion>(6);
  const [inputOverrides, setInputOverrides] = useState<Record<string, { min: number; max: number; step: number; enabled: boolean }>>({});
  const [submitting, setSubmitting] = useState(false);
  const [submitted, setSubmitted] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [validationErrors, setValidationErrors] = useState<string[]>([]);

  useEffect(() => {
    const load = async () => {
      try {
        // Load strategies
        const stratSnap = await getDocs(collection(db, COLLECTIONS.STRATEGIES));
        const strats: StrategyOption[] = [];
        for (const d of stratSnap.docs) {
          const versionsSnap = await getDocs(collection(db, COLLECTIONS.STRATEGIES, d.id, 'versions'));
          const versions = versionsSnap.docs
            .map((vd) => ({ id: vd.id, ...(vd.data() as StrategyVersion) }))
            .sort((a, b) => b.version - a.version);
          strats.push({ id: d.id, name: (d.data() as Strategy).name, versions });
        }
        strats.sort((a, b) => a.name.localeCompare(b.name));
        setStrategies(strats);

        // Load symbols
        const symSnap = await getDocs(collection(db, COLLECTIONS.SYMBOLS));
        if (symSnap.empty) {
          setSymbols(DEFAULT_SYMBOLS.map((s) => ({ name: s.name, description: s.description })));
        } else {
          setSymbols(
            symSnap.docs
              .filter((d) => d.data().active !== false)
              .map((d) => ({ name: d.data().name, description: d.data().description }))
          );
        }
      } catch (err) {
        console.error('Failed to load data:', err);
        setError('Failed to load strategies and symbols. Please refresh.');
      }
      setLoading(false);
    };
    load();
  }, []);

  const currentStrategy = strategies.find((s) => s.id === selectedStrategy);
  const currentVersion = currentStrategy?.versions.find((v) => v.version === selectedVersion);
  const totalJobs = selectedSymbols.length * selectedTimeframes.length;

  const initInputOverrides = (inputs: StrategyInput[]) => {
    const overrides: Record<string, { min: number; max: number; step: number; enabled: boolean }> = {};
    for (const input of inputs) {
      overrides[input.name] = {
        min: input.optimize.min,
        max: input.optimize.max,
        step: input.optimize.step,
        enabled: input.optimize.enabled,
      };
    }
    setInputOverrides(overrides);
  };

  const handleVersionChange = (version: number) => {
    setSelectedVersion(version);
    const v = currentStrategy?.versions.find((v) => v.version === version);
    if (v?.inputs) {
      initInputOverrides(v.inputs);
    }
  };

  const toggleSymbol = (sym: string) => {
    setSelectedSymbols((prev) =>
      prev.includes(sym) ? prev.filter((s) => s !== sym) : [...prev, sym]
    );
  };

  const toggleTimeframe = (tf: string) => {
    setSelectedTimeframes((prev) =>
      prev.includes(tf) ? prev.filter((t) => t !== tf) : [...prev, tf]
    );
  };

  const DATE_FORMAT_REGEX = /^\d{4}\.\d{2}\.\d{2}$/;

  const validateForm = (): string[] => {
    const errors: string[] = [];

    if (!DATE_FORMAT_REGEX.test(fromDate)) {
      errors.push('From Date must be in YYYY.MM.DD format');
    }
    if (!DATE_FORMAT_REGEX.test(toDate)) {
      errors.push('To Date must be in YYYY.MM.DD format');
    }
    if (DATE_FORMAT_REGEX.test(fromDate) && DATE_FORMAT_REGEX.test(toDate) && fromDate >= toDate) {
      errors.push('From Date must be before To Date');
    }
    if (deposit <= 0) {
      errors.push('Deposit must be greater than 0');
    }
    if (leverage <= 0) {
      errors.push('Leverage must be greater than 0');
    }

    // Validate input overrides for enabled parameters
    for (const [name, override] of Object.entries(inputOverrides)) {
      if (override.enabled) {
        if (override.min >= override.max) {
          errors.push(`${name}: Min must be less than Max`);
        }
        if (override.step <= 0) {
          errors.push(`${name}: Step must be greater than 0`);
        }
      }
    }

    return errors;
  };

  const handleSubmit = async () => {
    if (!currentStrategy || !currentVersion) return;

    const errors = validateForm();
    if (errors.length > 0) {
      setValidationErrors(errors);
      return;
    }
    setValidationErrors([]);
    setError(null);
    setSubmitting(true);

    try {
      for (const symbol of selectedSymbols) {
        for (const timeframe of selectedTimeframes) {
          const jobRef = doc(collection(db, COLLECTIONS.OPTIMIZATION_JOBS));
          await setDoc(jobRef, {
            strategyName: currentStrategy.name,
            strategyVersion: selectedVersion,
            symbol,
            timeframe,
            fromDate,
            toDate,
            deposit,
            leverage,
            optimizationMode,
            model,
            optimizationCriterion: criterion,
            inputOverrides,
            status: 'pending',
            claimedBy: null,
            claimedAt: null,
            startedAt: null,
            completedAt: null,
            duration: null,
            error: null,
            retryCount: 0,
            maxRetries: DEFAULT_MAX_RETRIES,
            resultSummary: null,
            deploymentGitHash: currentVersion.gitHash,
            createdAt: serverTimestamp(),
            createdBy: 'ui',
            priority: 0,
          });
        }
      }
      setSubmitted(true);
    } catch (err) {
      console.error('Failed to create jobs:', err);
      setError(err instanceof Error ? err.message : 'Failed to create optimization jobs');
    }
    setSubmitting(false);
  };

  if (loading) {
    return <Spinner />;
  }

  if (error && !strategies.length) {
    return (
      <div className="bg-red-500/10 border border-red-500/30 rounded-lg p-4 text-red-400">
        {error}
      </div>
    );
  }

  if (submitted) {
    return (
      <div className="text-center py-12">
        <div className="text-green-400 text-xl font-medium mb-4">
          Created {totalJobs} optimization job{totalJobs !== 1 ? 's' : ''}!
        </div>
        <button
          onClick={() => {
            setSubmitted(false);
            setStep(1);
            setSelectedStrategy('');
            setSelectedVersion(null);
            setSelectedSymbols([]);
            setSelectedTimeframes([]);
          }}
          className="px-4 py-2 bg-gray-800 hover:bg-gray-700 text-white rounded-lg"
        >
          Create More
        </button>
      </div>
    );
  }

  return (
    <div>
      <h2 className="text-2xl font-bold text-white mb-6">Create Optimization Batch</h2>

      {/* Step indicator */}
      <div className="flex items-center gap-2 mb-8">
        {[1, 2, 3, 4, 5].map((s) => (
          <div key={s} className="flex items-center gap-2">
            <div
              className={`w-8 h-8 rounded-full flex items-center justify-center text-sm font-medium ${
                s === step ? 'bg-blue-600 text-white' : s < step ? 'bg-green-600 text-white' : 'bg-gray-800 text-gray-500'
              }`}
            >
              {s}
            </div>
            {s < 5 && <div className={`w-8 h-0.5 ${s < step ? 'bg-green-600' : 'bg-gray-800'}`} />}
          </div>
        ))}
      </div>

      <div className="bg-gray-900 border border-gray-800 rounded-xl p-6">
        {/* Step 1: Strategy + Version */}
        {step === 1 && (
          <div className="space-y-4">
            <h3 className="text-lg font-medium text-white">Select Strategy & Version</h3>
            <div className="grid grid-cols-2 gap-4">
              <div>
                <label className="block text-sm text-gray-400 mb-1">Strategy</label>
                <select
                  value={selectedStrategy}
                  onChange={(e) => {
                    setSelectedStrategy(e.target.value);
                    setSelectedVersion(null);
                  }}
                  className="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-white"
                >
                  <option value="">Select...</option>
                  {strategies.map((s) => (
                    <option key={s.id} value={s.id}>{s.name}</option>
                  ))}
                </select>
              </div>
              <div>
                <label className="block text-sm text-gray-400 mb-1">Version</label>
                <select
                  value={selectedVersion ?? ''}
                  onChange={(e) => handleVersionChange(Number(e.target.value))}
                  className="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-white"
                  disabled={!selectedStrategy}
                >
                  <option value="">Select...</option>
                  {currentStrategy?.versions.map((v) => (
                    <option key={v.id} value={v.version}>v{v.version}</option>
                  ))}
                </select>
              </div>
            </div>
            <div className="flex justify-end">
              <button
                disabled={!selectedStrategy || !selectedVersion}
                onClick={() => setStep(2)}
                className="px-4 py-2 bg-blue-600 hover:bg-blue-700 disabled:bg-gray-700 disabled:text-gray-500 text-white rounded-lg"
              >
                Next
              </button>
            </div>
          </div>
        )}

        {/* Step 2: Symbols + Timeframes */}
        {step === 2 && (
          <div className="space-y-6">
            <div>
              <h3 className="text-lg font-medium text-white mb-3">Select Symbols</h3>
              <div className="flex flex-wrap gap-2">
                {symbols.map((sym) => (
                  <button
                    key={sym.name}
                    onClick={() => toggleSymbol(sym.name)}
                    className={`px-3 py-1.5 rounded-lg text-sm font-medium transition-colors ${
                      selectedSymbols.includes(sym.name)
                        ? 'bg-blue-600 text-white'
                        : 'bg-gray-800 text-gray-400 hover:bg-gray-700'
                    }`}
                  >
                    {sym.name}
                  </button>
                ))}
              </div>
            </div>
            <div>
              <h3 className="text-lg font-medium text-white mb-3">Select Timeframes</h3>
              <div className="flex flex-wrap gap-2">
                {MT5_TIMEFRAMES.filter((tf) => ['M5', 'M15', 'M30', 'H1', 'H4', 'D1'].includes(tf)).map((tf) => (
                  <button
                    key={tf}
                    onClick={() => toggleTimeframe(tf)}
                    className={`px-3 py-1.5 rounded-lg text-sm font-medium transition-colors ${
                      selectedTimeframes.includes(tf)
                        ? 'bg-blue-600 text-white'
                        : 'bg-gray-800 text-gray-400 hover:bg-gray-700'
                    }`}
                  >
                    {tf}
                  </button>
                ))}
              </div>
            </div>
            <div className="flex justify-between">
              <button onClick={() => setStep(1)} className="px-4 py-2 bg-gray-800 hover:bg-gray-700 text-white rounded-lg">
                Back
              </button>
              <button
                disabled={selectedSymbols.length === 0 || selectedTimeframes.length === 0}
                onClick={() => setStep(3)}
                className="px-4 py-2 bg-blue-600 hover:bg-blue-700 disabled:bg-gray-700 disabled:text-gray-500 text-white rounded-lg"
              >
                Next
              </button>
            </div>
          </div>
        )}

        {/* Step 3: Date range + Settings */}
        {step === 3 && (
          <div className="space-y-4">
            <h3 className="text-lg font-medium text-white">Optimization Settings</h3>
            <div className="grid grid-cols-2 lg:grid-cols-3 gap-4">
              <div>
                <label className="block text-sm text-gray-400 mb-1">From Date</label>
                <input
                  type="text"
                  value={fromDate}
                  onChange={(e) => setFromDate(e.target.value)}
                  placeholder="2025.01.01"
                  className="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-white"
                />
              </div>
              <div>
                <label className="block text-sm text-gray-400 mb-1">To Date</label>
                <input
                  type="text"
                  value={toDate}
                  onChange={(e) => setToDate(e.target.value)}
                  placeholder="2026.03.01"
                  className="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-white"
                />
              </div>
              <div>
                <label className="block text-sm text-gray-400 mb-1">Deposit</label>
                <input
                  type="number"
                  value={deposit}
                  onChange={(e) => setDeposit(Number(e.target.value))}
                  className="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-white"
                />
              </div>
              <div>
                <label className="block text-sm text-gray-400 mb-1">Leverage</label>
                <input
                  type="number"
                  value={leverage}
                  onChange={(e) => setLeverage(Number(e.target.value))}
                  className="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-white"
                />
              </div>
              <div>
                <label className="block text-sm text-gray-400 mb-1">Optimization Mode</label>
                <select
                  value={optimizationMode}
                  onChange={(e) => setOptimizationMode(Number(e.target.value) as OptimizationMode)}
                  className="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-white"
                >
                  {Object.entries(OPTIMIZATION_MODE_LABELS).map(([k, v]) => (
                    <option key={k} value={k}>{v}</option>
                  ))}
                </select>
              </div>
              <div>
                <label className="block text-sm text-gray-400 mb-1">Tick Model</label>
                <select
                  value={model}
                  onChange={(e) => setModel(Number(e.target.value) as TickModel)}
                  className="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-white"
                >
                  {Object.entries(TICK_MODEL_LABELS).map(([k, v]) => (
                    <option key={k} value={k}>{v}</option>
                  ))}
                </select>
              </div>
              <div>
                <label className="block text-sm text-gray-400 mb-1">Optimization Criterion</label>
                <select
                  value={criterion}
                  onChange={(e) => setCriterion(Number(e.target.value) as OptimizationCriterion)}
                  className="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-white"
                >
                  {Object.entries(OPTIMIZATION_CRITERION_LABELS).map(([k, v]) => (
                    <option key={k} value={k}>{v}</option>
                  ))}
                </select>
              </div>
            </div>
            {validationErrors.length > 0 && step === 3 && (
              <div className="bg-red-500/10 border border-red-500/30 rounded-lg p-4">
                <ul className="list-disc list-inside text-red-400 text-sm space-y-1">
                  {validationErrors.map((err, i) => (
                    <li key={i}>{err}</li>
                  ))}
                </ul>
              </div>
            )}
            <div className="flex justify-between">
              <button onClick={() => setStep(2)} className="px-4 py-2 bg-gray-800 hover:bg-gray-700 text-white rounded-lg">
                Back
              </button>
              <button
                onClick={() => {
                  const errors: string[] = [];
                  if (!DATE_FORMAT_REGEX.test(fromDate)) errors.push('From Date must be in YYYY.MM.DD format');
                  if (!DATE_FORMAT_REGEX.test(toDate)) errors.push('To Date must be in YYYY.MM.DD format');
                  if (DATE_FORMAT_REGEX.test(fromDate) && DATE_FORMAT_REGEX.test(toDate) && fromDate >= toDate) errors.push('From Date must be before To Date');
                  if (deposit <= 0) errors.push('Deposit must be greater than 0');
                  if (leverage <= 0) errors.push('Leverage must be greater than 0');
                  if (errors.length > 0) {
                    setValidationErrors(errors);
                    return;
                  }
                  setValidationErrors([]);
                  setStep(4);
                }}
                className="px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white rounded-lg"
              >
                Next
              </button>
            </div>
          </div>
        )}

        {/* Step 4: Input ranges */}
        {step === 4 && (
          <div className="space-y-4">
            <h3 className="text-lg font-medium text-white">Input Optimization Ranges</h3>
            {currentVersion?.inputs && currentVersion.inputs.length > 0 ? (
              <table className="w-full text-sm">
                <thead>
                  <tr className="text-gray-500 border-b border-gray-800">
                    <th className="px-3 py-2 text-left">Enabled</th>
                    <th className="px-3 py-2 text-left">Parameter</th>
                    <th className="px-3 py-2 text-left">Default</th>
                    <th className="px-3 py-2 text-left">Min</th>
                    <th className="px-3 py-2 text-left">Max</th>
                    <th className="px-3 py-2 text-left">Step</th>
                  </tr>
                </thead>
                <tbody>
                  {currentVersion.inputs.map((input) => (
                    <tr key={input.name} className="border-b border-gray-800/50">
                      <td className="px-3 py-2">
                        <input
                          type="checkbox"
                          checked={inputOverrides[input.name]?.enabled ?? false}
                          onChange={(e) =>
                            setInputOverrides((prev) => ({
                              ...prev,
                              [input.name]: { ...prev[input.name], enabled: e.target.checked },
                            }))
                          }
                          className="accent-blue-600"
                        />
                      </td>
                      <td className="px-3 py-2">
                        <div className="text-white">{input.name}</div>
                        <div className="text-xs text-gray-500">{input.label}</div>
                      </td>
                      <td className="px-3 py-2 text-gray-400">{String(input.default)}</td>
                      <td className="px-3 py-2">
                        <input
                          type="number"
                          value={inputOverrides[input.name]?.min ?? 0}
                          onChange={(e) =>
                            setInputOverrides((prev) => ({
                              ...prev,
                              [input.name]: { ...prev[input.name], min: Number(e.target.value) },
                            }))
                          }
                          className="w-20 bg-gray-800 border border-gray-700 rounded px-2 py-1 text-white text-sm"
                        />
                      </td>
                      <td className="px-3 py-2">
                        <input
                          type="number"
                          value={inputOverrides[input.name]?.max ?? 0}
                          onChange={(e) =>
                            setInputOverrides((prev) => ({
                              ...prev,
                              [input.name]: { ...prev[input.name], max: Number(e.target.value) },
                            }))
                          }
                          className="w-20 bg-gray-800 border border-gray-700 rounded px-2 py-1 text-white text-sm"
                        />
                      </td>
                      <td className="px-3 py-2">
                        <input
                          type="number"
                          value={inputOverrides[input.name]?.step ?? 0}
                          onChange={(e) =>
                            setInputOverrides((prev) => ({
                              ...prev,
                              [input.name]: { ...prev[input.name], step: Number(e.target.value) },
                            }))
                          }
                          className="w-20 bg-gray-800 border border-gray-700 rounded px-2 py-1 text-white text-sm"
                        />
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            ) : (
              <p className="text-gray-500">No inputs found for this strategy version.</p>
            )}
            <div className="flex justify-between">
              <button onClick={() => setStep(3)} className="px-4 py-2 bg-gray-800 hover:bg-gray-700 text-white rounded-lg">
                Back
              </button>
              <button onClick={() => setStep(5)} className="px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white rounded-lg">
                Review
              </button>
            </div>
          </div>
        )}

        {/* Step 5: Review + Submit */}
        {step === 5 && (
          <div className="space-y-4">
            <h3 className="text-lg font-medium text-white">Review & Submit</h3>
            <div className="grid grid-cols-2 gap-4 text-sm">
              <div>
                <span className="text-gray-500">Strategy:</span>
                <span className="text-white ml-2">{currentStrategy?.name} v{selectedVersion}</span>
              </div>
              <div>
                <span className="text-gray-500">Symbols:</span>
                <span className="text-white ml-2">{selectedSymbols.join(', ')}</span>
              </div>
              <div>
                <span className="text-gray-500">Timeframes:</span>
                <span className="text-white ml-2">{selectedTimeframes.join(', ')}</span>
              </div>
              <div>
                <span className="text-gray-500">Date Range:</span>
                <span className="text-white ml-2">{fromDate} — {toDate}</span>
              </div>
              <div>
                <span className="text-gray-500">Mode:</span>
                <span className="text-white ml-2">{OPTIMIZATION_MODE_LABELS[optimizationMode]}</span>
              </div>
              <div>
                <span className="text-gray-500">Deposit / Leverage:</span>
                <span className="text-white ml-2">${deposit.toLocaleString()} / 1:{leverage}</span>
              </div>
            </div>
            <div className="bg-blue-600/10 border border-blue-600/30 rounded-lg p-4 text-center">
              <p className="text-blue-400 text-lg font-medium">
                This will create <strong>{totalJobs}</strong> optimization job{totalJobs !== 1 ? 's' : ''}
              </p>
              <p className="text-sm text-gray-500 mt-1">
                1 strategy &times; {selectedSymbols.length} symbol{selectedSymbols.length !== 1 ? 's' : ''} &times; {selectedTimeframes.length} timeframe{selectedTimeframes.length !== 1 ? 's' : ''}
              </p>
            </div>
            {validationErrors.length > 0 && (
              <div className="bg-red-500/10 border border-red-500/30 rounded-lg p-4">
                <p className="text-red-400 font-medium mb-2">Please fix the following errors:</p>
                <ul className="list-disc list-inside text-red-400 text-sm space-y-1">
                  {validationErrors.map((err, i) => (
                    <li key={i}>{err}</li>
                  ))}
                </ul>
              </div>
            )}
            {error && (
              <div className="bg-red-500/10 border border-red-500/30 rounded-lg p-4 text-red-400">
                {error}
              </div>
            )}
            <div className="flex justify-between">
              <button onClick={() => setStep(4)} className="px-4 py-2 bg-gray-800 hover:bg-gray-700 text-white rounded-lg">
                Back
              </button>
              <button
                onClick={handleSubmit}
                disabled={submitting}
                className="px-6 py-2 bg-green-600 hover:bg-green-700 disabled:bg-gray-700 text-white rounded-lg font-medium"
              >
                {submitting ? 'Creating...' : 'Submit Jobs'}
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
