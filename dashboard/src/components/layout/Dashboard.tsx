import { useStrategy } from '../../context/StrategyContext';
import { FileLoader } from '../controls/FileLoader';
import { Header } from './Header';
import { ChartContainer } from '../charts/ChartContainer';
import { EquityCurve } from '../stats/EquityCurve';
import { MonthlyReturns } from '../stats/MonthlyReturns';
import { StatsCards } from '../stats/StatsCards';
import { TradeTable } from '../trades/TradeTable';

export function Dashboard() {
  const { data, activeTab } = useStrategy();

  return (
    <div className="h-full flex flex-col bg-gray-50 dark:bg-surface-dark text-gray-900 dark:text-gray-100">
      <Header />

      {!data ? (
        <FileLoader />
      ) : (
        <div className="flex-1 flex flex-col overflow-hidden">
          {activeTab === 'chart' ? (
            /* Chart tab - full page, no padding, no scroll */
            <ChartContainer />
          ) : (
            /* Analytics tab */
            <main className="flex-1 overflow-y-auto p-4 space-y-4">
              {/* Stats summary row */}
              <StatsCards />

              {/* Equity + Monthly side by side */}
              <div className="grid grid-cols-1 xl:grid-cols-2 gap-4">
                <EquityCurve />
                <MonthlyReturns />
              </div>

              {/* Trade table */}
              <TradeTable />
            </main>
          )}
        </div>
      )}
    </div>
  );
}
