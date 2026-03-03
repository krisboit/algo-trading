import { useState, useRef, useEffect } from 'react';
import { Eye, EyeOff, ChevronDown, TrendingUp, BarChart3 } from 'lucide-react';
import { useStrategy } from '../../context/StrategyContext';
import { formatCurrency, formatPercent, formatRatio } from '../../utils/formatters';

export function ChartToolbar() {
  const {
    data, selectedTimeframe, setSelectedTimeframe,
    indicatorConfigs, toggleIndicator,
  } = useStrategy();

  const [showIndicatorMenu, setShowIndicatorMenu] = useState(false);
  const menuRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const handler = (e: MouseEvent) => {
      if (menuRef.current && !menuRef.current.contains(e.target as Node)) {
        setShowIndicatorMenu(false);
      }
    };
    document.addEventListener('mousedown', handler);
    return () => document.removeEventListener('mousedown', handler);
  }, []);

  if (!data) return null;

  const { stats, meta } = data;

  return (
    <div className="flex items-center gap-1 px-2 py-1 border-b border-gray-200 dark:border-gray-700/50
                    bg-white dark:bg-surface-dark text-xs select-none flex-shrink-0 min-h-[32px]">

      {/* Timeframe buttons */}
      <div className="flex items-center gap-0.5 pr-2 border-r border-gray-200 dark:border-gray-700/50">
        {data.meta.timeframes.map(tf => (
          <button
            key={tf}
            onClick={() => setSelectedTimeframe(tf)}
            className={`px-2 py-1 rounded font-medium transition-colors
              ${selectedTimeframe === tf
                ? 'bg-blue-500/10 text-blue-600 dark:text-blue-400'
                : 'text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-200 hover:bg-gray-100 dark:hover:bg-gray-800/50'
              }`}
          >
            {tf}
          </button>
        ))}
      </div>

      {/* Indicator dropdown */}
      <div className="relative" ref={menuRef}>
        <button
          onClick={() => setShowIndicatorMenu(!showIndicatorMenu)}
          className="flex items-center gap-1 px-2 py-1 rounded text-gray-500 dark:text-gray-400
                     hover:text-gray-700 dark:hover:text-gray-200 hover:bg-gray-100 dark:hover:bg-gray-800/50 transition-colors"
        >
          <BarChart3 className="w-3.5 h-3.5" />
          <span>Indicators</span>
          <ChevronDown className="w-3 h-3" />
        </button>

        {showIndicatorMenu && (
          <div className="absolute top-full left-0 mt-1 z-50 w-64 bg-white dark:bg-surface-dark-2
                          rounded-lg shadow-lg border border-gray-200 dark:border-gray-700 py-1 max-h-80 overflow-y-auto">
            {indicatorConfigs.filter(c => c.location === 'overlay').length > 0 && (
              <>
                <div className="px-3 py-1 text-[10px] font-semibold uppercase tracking-wider text-gray-400 dark:text-gray-500
                                flex items-center gap-1">
                  <TrendingUp className="w-3 h-3" />
                  Overlays
                </div>
                {indicatorConfigs.filter(c => c.location === 'overlay').map(config => (
                  <IndicatorMenuItem key={config.name} config={config} onToggle={toggleIndicator} />
                ))}
              </>
            )}
            {indicatorConfigs.filter(c => c.location === 'panel').length > 0 && (
              <>
                <div className="px-3 py-1 mt-1 text-[10px] font-semibold uppercase tracking-wider text-gray-400 dark:text-gray-500
                                flex items-center gap-1 border-t border-gray-100 dark:border-gray-700/50 pt-1.5">
                  <BarChart3 className="w-3 h-3" />
                  Oscillators
                </div>
                {indicatorConfigs.filter(c => c.location === 'panel').map(config => (
                  <IndicatorMenuItem key={config.name} config={config} onToggle={toggleIndicator} />
                ))}
              </>
            )}
          </div>
        )}
      </div>

      {/* Active indicator chips */}
      <div className="flex items-center gap-1 px-1 border-l border-gray-200 dark:border-gray-700/50 ml-1">
        {indicatorConfigs.filter(c => c.visible).map(config => (
          <button
            key={config.name}
            onClick={() => toggleIndicator(config.name)}
            className="flex items-center gap-1 px-1.5 py-0.5 rounded text-[10px] font-medium
                       bg-gray-100 dark:bg-gray-800/60 text-gray-600 dark:text-gray-400
                       hover:bg-gray-200 dark:hover:bg-gray-700 transition-colors"
            title={`Hide ${config.name}`}
          >
            <div
              className="w-1.5 h-1.5 rounded-full flex-shrink-0"
              style={{ backgroundColor: config.colors[0] }}
            />
            {config.name}
          </button>
        ))}
      </div>

      {/* Spacer */}
      <div className="flex-1" />

      {/* Compact performance stats */}
      <div className="flex items-center gap-3 pl-2 border-l border-gray-200 dark:border-gray-700/50 text-[11px]">
        <StatChip
          label="P/L"
          value={formatCurrency(stats.netProfit, meta.currency)}
          sub={formatPercent(stats.netProfitPct)}
          positive={stats.netProfit >= 0}
        />
        <StatChip
          label="WR"
          value={`${(stats.winRate * 100).toFixed(1)}%`}
          sub={`${stats.totalTrades}t`}
          positive={stats.winRate >= 0.5}
        />
        <StatChip
          label="PF"
          value={formatRatio(stats.profitFactor)}
          positive={stats.profitFactor >= 1}
        />
        <StatChip
          label="DD"
          value={formatPercent(-stats.maxDrawdownPct)}
          positive={false}
        />
      </div>
    </div>
  );
}

function StatChip({ label, value, sub, positive }: {
  label: string;
  value: string;
  sub?: string;
  positive?: boolean;
}) {
  const color = positive === undefined
    ? 'text-gray-600 dark:text-gray-400'
    : positive
      ? 'text-green-600 dark:text-green-400'
      : 'text-red-500 dark:text-red-400';

  return (
    <div className="flex items-center gap-1 whitespace-nowrap">
      <span className="text-gray-400 dark:text-gray-500">{label}</span>
      <span className={`font-medium ${color}`}>{value}</span>
      {sub && <span className={`${color} opacity-60`}>{sub}</span>}
    </div>
  );
}

function IndicatorMenuItem({ config, onToggle }: {
  config: { name: string; visible: boolean; colors: string[] };
  onToggle: (name: string) => void;
}) {
  return (
    <button
      onClick={() => onToggle(config.name)}
      className="w-full flex items-center gap-2 px-3 py-1.5 text-xs
                 hover:bg-gray-50 dark:hover:bg-gray-800/50 transition-colors"
    >
      <div
        className="w-2 h-2 rounded-full flex-shrink-0"
        style={{
          backgroundColor: config.visible ? config.colors[0] : 'transparent',
          border: config.visible ? 'none' : `1.5px solid ${config.colors[0]}`,
        }}
      />
      <span className={`flex-1 text-left ${config.visible
        ? 'text-gray-700 dark:text-gray-300'
        : 'text-gray-400 dark:text-gray-600'
      }`}>
        {config.name}
      </span>
      {config.visible ? (
        <Eye className="w-3.5 h-3.5 text-gray-400 dark:text-gray-500" />
      ) : (
        <EyeOff className="w-3.5 h-3.5 text-gray-500 dark:text-gray-600" />
      )}
    </button>
  );
}
