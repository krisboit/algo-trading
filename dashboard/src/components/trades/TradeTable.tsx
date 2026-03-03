import { useState, useMemo } from 'react';
import { ArrowUpDown, Filter } from 'lucide-react';
import { useStrategy } from '../../context/StrategyContext';
import { formatDateTime, formatCurrency, formatPrice, formatDuration } from '../../utils/formatters';
import type { Order } from '../../types/strategy';

type SortField = 'ticket' | 'type' | 'openTime' | 'closeTime' | 'openPrice' | 'closePrice' | 'netProfit' | 'volume';
type SortDir = 'asc' | 'desc';
type TradeFilter = 'all' | 'winners' | 'losers';

export function TradeTable() {
  const { data, selectedOrderTicket, setSelectedOrderTicket } = useStrategy();
  const [sortField, setSortField] = useState<SortField>('openTime');
  const [sortDir, setSortDir] = useState<SortDir>('desc');
  const [filter, setFilter] = useState<TradeFilter>('all');

  const filteredOrders = useMemo(() => {
    if (!data) return [];

    let orders = [...data.orders];

    // Apply filter
    if (filter === 'winners') orders = orders.filter(o => o.netProfit >= 0);
    if (filter === 'losers') orders = orders.filter(o => o.netProfit < 0);

    // Apply sort
    orders.sort((a, b) => {
      let aVal: number | string = 0;
      let bVal: number | string = 0;

      switch (sortField) {
        case 'ticket': aVal = a.ticket; bVal = b.ticket; break;
        case 'type': aVal = a.type; bVal = b.type; break;
        case 'openTime': aVal = a.openTime; bVal = b.openTime; break;
        case 'closeTime': aVal = a.closeTime; bVal = b.closeTime; break;
        case 'openPrice': aVal = a.openPrice; bVal = b.openPrice; break;
        case 'closePrice': aVal = a.closePrice; bVal = b.closePrice; break;
        case 'netProfit': aVal = a.netProfit; bVal = b.netProfit; break;
        case 'volume': aVal = a.volume; bVal = b.volume; break;
      }

      if (typeof aVal === 'string') {
        return sortDir === 'asc'
          ? aVal.localeCompare(bVal as string)
          : (bVal as string).localeCompare(aVal);
      }
      return sortDir === 'asc' ? (aVal as number) - (bVal as number) : (bVal as number) - (aVal as number);
    });

    return orders;
  }, [data, sortField, sortDir, filter]);

  const handleSort = (field: SortField) => {
    if (sortField === field) {
      setSortDir(prev => prev === 'asc' ? 'desc' : 'asc');
    } else {
      setSortField(field);
      setSortDir('desc');
    }
  };

  if (!data) return null;

  const digits = data.meta.symbol.digits;

  return (
    <div className="bg-white dark:bg-surface-dark rounded-xl border border-gray-200 dark:border-gray-700 overflow-hidden">
      {/* Header */}
      <div className="flex items-center justify-between px-3 py-2 border-b border-gray-200 dark:border-gray-700">
        <h3 className="text-xs font-semibold text-gray-600 dark:text-gray-400">
          Trades ({filteredOrders.length})
        </h3>
        <div className="flex items-center gap-1">
          <Filter className="w-3 h-3 text-gray-400" />
          {(['all', 'winners', 'losers'] as TradeFilter[]).map(f => (
            <button
              key={f}
              onClick={() => setFilter(f)}
              className={`px-2 py-0.5 text-xs rounded transition-colors ${
                filter === f
                  ? f === 'winners'
                    ? 'bg-green-100 dark:bg-green-900/30 text-green-700 dark:text-green-400'
                    : f === 'losers'
                      ? 'bg-red-100 dark:bg-red-900/30 text-red-600 dark:text-red-400'
                      : 'bg-blue-100 dark:bg-blue-900/30 text-blue-700 dark:text-blue-400'
                  : 'text-gray-500 dark:text-gray-400 hover:bg-gray-100 dark:hover:bg-gray-800'
              }`}
            >
              {f.charAt(0).toUpperCase() + f.slice(1)}
            </button>
          ))}
        </div>
      </div>

      {/* Table */}
      <div className="overflow-x-auto max-h-[300px] overflow-y-auto">
        <table className="w-full text-xs">
          <thead className="sticky top-0 bg-gray-50 dark:bg-surface-dark-2">
            <tr>
              <SortHeader field="ticket" current={sortField} dir={sortDir} onSort={handleSort}>#</SortHeader>
              <SortHeader field="type" current={sortField} dir={sortDir} onSort={handleSort}>Type</SortHeader>
              <SortHeader field="volume" current={sortField} dir={sortDir} onSort={handleSort}>Vol</SortHeader>
              <SortHeader field="openTime" current={sortField} dir={sortDir} onSort={handleSort}>Open</SortHeader>
              <SortHeader field="closeTime" current={sortField} dir={sortDir} onSort={handleSort}>Close</SortHeader>
              <SortHeader field="openPrice" current={sortField} dir={sortDir} onSort={handleSort}>Entry</SortHeader>
              <SortHeader field="closePrice" current={sortField} dir={sortDir} onSort={handleSort}>Exit</SortHeader>
              <th className="px-2 py-1.5 text-left text-gray-500 dark:text-gray-400 font-medium">Exits</th>
              <SortHeader field="netProfit" current={sortField} dir={sortDir} onSort={handleSort}>P/L</SortHeader>
              <th className="px-2 py-1.5 text-left text-gray-500 dark:text-gray-400 font-medium">Duration</th>
            </tr>
          </thead>
          <tbody>
            {filteredOrders.map(order => (
              <TradeRow
                key={order.ticket}
                order={order}
                digits={digits}
                currency={data.meta.currency}
                isSelected={selectedOrderTicket === order.ticket}
                onClick={() => setSelectedOrderTicket(
                  selectedOrderTicket === order.ticket ? null : order.ticket
                )}
              />
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

interface SortHeaderProps {
  field: SortField;
  current: SortField;
  dir: SortDir;
  onSort: (field: SortField) => void;
  children: React.ReactNode;
}

function SortHeader({ field, current, dir, onSort, children }: SortHeaderProps) {
  return (
    <th
      className="px-2 py-1.5 text-left text-gray-500 dark:text-gray-400 font-medium cursor-pointer
                 hover:text-gray-700 dark:hover:text-gray-300 select-none whitespace-nowrap"
      onClick={() => onSort(field)}
    >
      <div className="flex items-center gap-0.5">
        {children}
        {current === field && (
          <ArrowUpDown className={`w-3 h-3 ${dir === 'asc' ? 'rotate-180' : ''}`} />
        )}
      </div>
    </th>
  );
}

interface TradeRowProps {
  order: Order;
  digits: number;
  currency: string;
  isSelected: boolean;
  onClick: () => void;
}

function TradeRow({ order, digits, currency, isSelected, onClick }: TradeRowProps) {
  const isWin = order.netProfit >= 0;
  const duration = order.closeTime > order.openTime
    ? order.closeTime - order.openTime
    : 0;

  return (
    <tr
      onClick={onClick}
      className={`
        cursor-pointer transition-colors border-b border-gray-100 dark:border-gray-800
        ${isSelected
          ? 'bg-blue-50 dark:bg-blue-900/20'
          : 'hover:bg-gray-50 dark:hover:bg-gray-800/30'
        }
      `}
    >
      <td className="px-2 py-1.5 text-gray-600 dark:text-gray-400">{order.ticket}</td>
      <td className="px-2 py-1.5">
        <span className={`font-medium ${order.type === 'BUY' ? 'text-blue-600 dark:text-blue-400' : 'text-orange-600 dark:text-orange-400'}`}>
          {order.type}
        </span>
      </td>
      <td className="px-2 py-1.5 text-gray-600 dark:text-gray-400">{order.volume.toFixed(2)}</td>
      <td className="px-2 py-1.5 text-gray-600 dark:text-gray-400 whitespace-nowrap">
        {formatDateTime(order.openTime)}
      </td>
      <td className="px-2 py-1.5 text-gray-600 dark:text-gray-400 whitespace-nowrap">
        {order.closeTime > 0 ? formatDateTime(order.closeTime) : '-'}
      </td>
      <td className="px-2 py-1.5 text-gray-600 dark:text-gray-400 font-mono">
        {formatPrice(order.openPrice, digits)}
      </td>
      <td className="px-2 py-1.5 text-gray-600 dark:text-gray-400 font-mono">
        {order.closePrice > 0 ? formatPrice(order.closePrice, digits) : '-'}
      </td>
      <td className="px-2 py-1.5 text-gray-500 dark:text-gray-400">
        {order.exits.length > 1 ? `${order.exits.length} exits` : order.exits[0]?.reason ?? '-'}
      </td>
      <td className="px-2 py-1.5 font-medium">
        <span className={isWin ? 'text-green-600 dark:text-green-400' : 'text-red-500 dark:text-red-400'}>
          {isWin ? '+' : ''}{formatCurrency(order.netProfit, currency)}
        </span>
      </td>
      <td className="px-2 py-1.5 text-gray-500 dark:text-gray-400">
        {duration > 0 ? formatDuration(duration) : '-'}
      </td>
    </tr>
  );
}
