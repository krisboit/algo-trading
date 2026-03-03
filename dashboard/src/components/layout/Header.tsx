import { BarChart3, FileJson, Upload, LineChart, LayoutGrid } from 'lucide-react';
import { useRef } from 'react';
import { useStrategy } from '../../context/StrategyContext';
import { ThemeToggle } from '../controls/ThemeToggle';
import { formatDate } from '../../utils/formatters';
import type { StrategyData } from '../../types/strategy';

export function Header() {
  const { data, fileName, loadData, activeTab, setActiveTab } = useStrategy();
  const fileInputRef = useRef<HTMLInputElement>(null);

  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    const reader = new FileReader();
    reader.onload = (ev) => {
      try {
        const json = JSON.parse(ev.target?.result as string) as StrategyData;
        if (json.meta && json.stats && json.data && json.orders && json.equity) {
          loadData(json, file.name);
        }
      } catch { /* ignore */ }
    };
    reader.readAsText(file);
  };

  return (
    <header className="h-10 flex items-center justify-between px-3 border-b border-gray-200 dark:border-gray-700
                       bg-white dark:bg-surface-dark-2 flex-shrink-0">
      {/* Left: Logo + meta + tabs */}
      <div className="flex items-center gap-2">
        <div className="flex items-center gap-1.5 text-blue-600 dark:text-blue-400">
          <BarChart3 className="w-4 h-4" />
          <span className="font-semibold text-xs hidden sm:inline">Strategy Analyzer</span>
        </div>

        {data && (
          <>
            <div className="w-px h-4 bg-gray-300 dark:bg-gray-600" />

            {/* Strategy meta */}
            <div className="flex items-center gap-1.5 text-[11px]">
              <span className="font-medium text-gray-700 dark:text-gray-300">
                {data.meta.symbol.name}
              </span>
              <span className="text-gray-400 dark:text-gray-500">
                {data.meta.primaryTimeframe}
              </span>
              <span className="text-gray-400 dark:text-gray-600 hidden md:inline">
                {formatDate(data.meta.start)} - {formatDate(data.meta.end)}
              </span>
            </div>

            <div className="w-px h-4 bg-gray-300 dark:bg-gray-600" />

            {/* Tab buttons */}
            <div className="flex items-center gap-0.5">
              <TabButton
                active={activeTab === 'chart'}
                onClick={() => setActiveTab('chart')}
                icon={<LineChart className="w-3.5 h-3.5" />}
                label="Chart"
              />
              <TabButton
                active={activeTab === 'analytics'}
                onClick={() => setActiveTab('analytics')}
                icon={<LayoutGrid className="w-3.5 h-3.5" />}
                label="Analytics"
              />
            </div>
          </>
        )}
      </div>

      {/* Right: Controls */}
      <div className="flex items-center gap-1.5">
        {data && (
          <div className="flex items-center gap-1 text-[10px] text-gray-400 dark:text-gray-500 hidden lg:flex">
            <FileJson className="w-3 h-3" />
            <span className="truncate max-w-[150px]">{fileName}</span>
          </div>
        )}

        <button
          onClick={() => fileInputRef.current?.click()}
          className="flex items-center gap-1 px-2 py-1 text-[11px] font-medium rounded
                     bg-blue-500 text-white hover:bg-blue-600 transition-colors"
        >
          <Upload className="w-3 h-3" />
          <span className="hidden sm:inline">Load</span>
        </button>

        <input
          ref={fileInputRef}
          type="file"
          accept=".json"
          onChange={handleFileChange}
          className="hidden"
        />

        <ThemeToggle />
      </div>
    </header>
  );
}

function TabButton({ active, onClick, icon, label }: {
  active: boolean;
  onClick: () => void;
  icon: React.ReactNode;
  label: string;
}) {
  return (
    <button
      onClick={onClick}
      className={`flex items-center gap-1 px-2 py-1 rounded text-[11px] font-medium transition-colors
        ${active
          ? 'bg-blue-500/10 text-blue-600 dark:text-blue-400'
          : 'text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-200 hover:bg-gray-100 dark:hover:bg-gray-800/50'
        }`}
    >
      {icon}
      {label}
    </button>
  );
}
