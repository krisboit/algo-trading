import { useStrategy } from '../../context/StrategyContext';
import { formatMonth, formatPercent, formatCurrency } from '../../utils/formatters';

export function MonthlyReturns() {
  const { data } = useStrategy();
  if (!data || !data.stats.monthly || data.stats.monthly.length === 0) return null;

  const { monthly } = data.stats;
  const maxProfit = Math.max(...monthly.map(m => Math.abs(m.profitPct)), 1);

  return (
    <div className="bg-white dark:bg-surface-dark rounded-xl border border-gray-200 dark:border-gray-700 overflow-hidden">
      <div className="px-3 py-2 border-b border-gray-200 dark:border-gray-700">
        <h3 className="text-xs font-semibold text-gray-600 dark:text-gray-400">
          Monthly Returns
        </h3>
      </div>
      <div className="p-3">
        <div className="space-y-1">
          {monthly.map(m => {
            const barWidth = (Math.abs(m.profitPct) / maxProfit) * 100;
            const isPositive = m.profit >= 0;

            return (
              <div key={m.month} className="flex items-center gap-2 text-xs">
                <span className="w-16 text-gray-500 dark:text-gray-400 flex-shrink-0">
                  {formatMonth(m.month)}
                </span>

                <div className="flex-1 h-4 relative">
                  <div className="absolute inset-0 flex items-center">
                    <div className="w-full h-1 bg-gray-100 dark:bg-gray-800 rounded" />
                  </div>
                  <div
                    className={`absolute h-4 rounded-sm ${
                      isPositive
                        ? 'bg-green-500/20 dark:bg-green-500/30'
                        : 'bg-red-500/20 dark:bg-red-500/30'
                    }`}
                    style={{
                      width: `${barWidth}%`,
                      left: isPositive ? '50%' : `${50 - barWidth}%`,
                    }}
                  />
                </div>

                <div className="w-20 text-right flex-shrink-0">
                  <span className={`font-medium ${
                    isPositive ? 'text-green-600 dark:text-green-400' : 'text-red-500 dark:text-red-400'
                  }`}>
                    {formatPercent(m.profitPct)}
                  </span>
                </div>

                <div className="w-20 text-right flex-shrink-0">
                  <span className={`${
                    isPositive ? 'text-green-600 dark:text-green-400' : 'text-red-500 dark:text-red-400'
                  }`}>
                    {formatCurrency(m.profit, data.meta.currency)}
                  </span>
                </div>

                <div className="w-12 text-right flex-shrink-0 text-gray-400">
                  {m.trades}t
                </div>

                <div className="w-12 text-right flex-shrink-0 text-gray-400">
                  {(m.winRate * 100).toFixed(0)}%
                </div>
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
}
