import {
  TrendingUp, TrendingDown, Target, BarChart3,
  Shield, Zap, Trophy, AlertTriangle, Clock, Activity,
} from 'lucide-react';
import { useStrategy } from '../../context/StrategyContext';
import { formatCurrency, formatPercent, formatRatio, formatDuration } from '../../utils/formatters';

export function StatsCards() {
  const { data } = useStrategy();
  if (!data) return null;

  const { stats, meta } = data;

  return (
    <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-6 gap-3">
      <StatCard
        icon={<TrendingUp className="w-4 h-4" />}
        label="Net Profit"
        value={formatCurrency(stats.netProfit, meta.currency)}
        sub={formatPercent(stats.netProfitPct)}
        positive={stats.netProfit >= 0}
      />
      <StatCard
        icon={<Target className="w-4 h-4" />}
        label="Win Rate"
        value={`${(stats.winRate * 100).toFixed(1)}%`}
        sub={`${stats.winningTrades}W / ${stats.losingTrades}L`}
        positive={stats.winRate >= 0.5}
      />
      <StatCard
        icon={<BarChart3 className="w-4 h-4" />}
        label="Profit Factor"
        value={formatRatio(stats.profitFactor)}
        positive={stats.profitFactor >= 1}
      />
      <StatCard
        icon={<AlertTriangle className="w-4 h-4" />}
        label="Max Drawdown"
        value={formatCurrency(-stats.maxDrawdown, meta.currency)}
        sub={formatPercent(-stats.maxDrawdownPct)}
        positive={false}
      />
      <StatCard
        icon={<Shield className="w-4 h-4" />}
        label="Sharpe Ratio"
        value={formatRatio(stats.sharpeRatio)}
        positive={stats.sharpeRatio >= 1}
      />
      <StatCard
        icon={<Zap className="w-4 h-4" />}
        label="Expectancy"
        value={formatCurrency(stats.expectancy, meta.currency)}
        positive={stats.expectancy >= 0}
      />
      <StatCard
        icon={<TrendingUp className="w-4 h-4" />}
        label="Avg Win"
        value={formatCurrency(stats.avgWin, meta.currency)}
        positive={true}
      />
      <StatCard
        icon={<TrendingDown className="w-4 h-4" />}
        label="Avg Loss"
        value={formatCurrency(-stats.avgLoss, meta.currency)}
        positive={false}
      />
      <StatCard
        icon={<Trophy className="w-4 h-4" />}
        label="Best Streak"
        value={`${stats.maxConsecutiveWins}W / ${stats.maxConsecutiveLosses}L`}
      />
      <StatCard
        icon={<Clock className="w-4 h-4" />}
        label="Avg Duration"
        value={formatDuration(stats.avgTradeDuration)}
      />
      <StatCard
        icon={<Activity className="w-4 h-4" />}
        label="Total Trades"
        value={`${stats.totalTrades}`}
      />
      <StatCard
        icon={<Shield className="w-4 h-4" />}
        label="Recovery Factor"
        value={formatRatio(stats.recoveryFactor)}
        positive={stats.recoveryFactor >= 1}
      />
    </div>
  );
}

interface StatCardProps {
  icon: React.ReactNode;
  label: string;
  value: string;
  sub?: string;
  positive?: boolean;
}

function StatCard({ icon, label, value, sub, positive }: StatCardProps) {
  const valueColor = positive === undefined
    ? 'text-gray-700 dark:text-gray-300'
    : positive
      ? 'text-green-600 dark:text-green-400'
      : 'text-red-500 dark:text-red-400';

  return (
    <div className="bg-white dark:bg-surface-dark-2 rounded-lg border border-gray-200 dark:border-gray-700 p-3">
      <div className="flex items-center gap-1.5 text-gray-400 dark:text-gray-500 mb-1">
        {icon}
        <span className="text-[11px] font-medium">{label}</span>
      </div>
      <div className="flex items-baseline gap-1.5">
        <span className={`text-sm font-semibold ${valueColor}`}>{value}</span>
        {sub && (
          <span className={`text-[11px] ${valueColor} opacity-70`}>{sub}</span>
        )}
      </div>
    </div>
  );
}
