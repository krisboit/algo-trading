import { useStrategy } from '../../context/StrategyContext';
import { TimeframeSelector } from '../controls/TimeframeSelector';
import { IndicatorToggle } from '../controls/IndicatorToggle';
import { StatsCards } from '../stats/StatsCards';

export function Sidebar() {
  const { data } = useStrategy();

  if (!data) return null;

  return (
    <aside className="w-64 flex-shrink-0 border-r border-gray-200 dark:border-gray-700
                      bg-white dark:bg-surface-dark-2 overflow-y-auto">
      <div className="p-3 space-y-4">
        <TimeframeSelector />
        <IndicatorToggle />
        <div className="border-t border-gray-200 dark:border-gray-700 pt-3">
          <StatsCards />
        </div>
      </div>
    </aside>
  );
}
