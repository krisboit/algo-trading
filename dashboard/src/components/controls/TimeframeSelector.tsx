import { useStrategy } from '../../context/StrategyContext';

export function TimeframeSelector() {
  const { data, selectedTimeframe, setSelectedTimeframe } = useStrategy();

  if (!data) return null;

  return (
    <div>
      <h3 className="text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400 mb-2">
        Timeframe
      </h3>
      <div className="flex gap-1">
        {data.meta.timeframes.map(tf => (
          <button
            key={tf}
            onClick={() => setSelectedTimeframe(tf)}
            className={`
              px-3 py-1.5 text-xs font-medium rounded-md transition-colors
              ${selectedTimeframe === tf
                ? 'bg-blue-500 text-white'
                : 'bg-gray-100 dark:bg-gray-800 text-gray-600 dark:text-gray-400 hover:bg-gray-200 dark:hover:bg-gray-700'
              }
            `}
          >
            {tf}
          </button>
        ))}
      </div>
    </div>
  );
}
