import { Eye, EyeOff, BarChart3, TrendingUp } from 'lucide-react';
import { useStrategy } from '../../context/StrategyContext';

export function IndicatorToggle() {
  const { indicatorConfigs, toggleIndicator } = useStrategy();

  if (indicatorConfigs.length === 0) return null;

  const overlays = indicatorConfigs.filter(c => c.location === 'overlay');
  const panels = indicatorConfigs.filter(c => c.location === 'panel');

  return (
    <div>
      <h3 className="text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400 mb-2">
        Indicators
      </h3>

      {overlays.length > 0 && (
        <div className="mb-3">
          <div className="flex items-center gap-1 mb-1.5">
            <TrendingUp className="w-3 h-3 text-gray-400" />
            <span className="text-xs text-gray-400 dark:text-gray-500">Chart Overlays</span>
          </div>
          <div className="space-y-1">
            {overlays.map(config => (
              <IndicatorRow key={config.name} config={config} onToggle={toggleIndicator} />
            ))}
          </div>
        </div>
      )}

      {panels.length > 0 && (
        <div>
          <div className="flex items-center gap-1 mb-1.5">
            <BarChart3 className="w-3 h-3 text-gray-400" />
            <span className="text-xs text-gray-400 dark:text-gray-500">Panels</span>
          </div>
          <div className="space-y-1">
            {panels.map(config => (
              <IndicatorRow key={config.name} config={config} onToggle={toggleIndicator} />
            ))}
          </div>
        </div>
      )}
    </div>
  );
}

interface IndicatorRowProps {
  config: { name: string; visible: boolean; colors: string[] };
  onToggle: (name: string) => void;
}

function IndicatorRow({ config, onToggle }: IndicatorRowProps) {
  return (
    <button
      onClick={() => onToggle(config.name)}
      className={`
        w-full flex items-center gap-2 px-2 py-1.5 rounded-md text-xs transition-colors
        ${config.visible
          ? 'bg-gray-100 dark:bg-gray-800 text-gray-700 dark:text-gray-300'
          : 'text-gray-400 dark:text-gray-600 hover:bg-gray-50 dark:hover:bg-gray-800/50'
        }
      `}
    >
      <div
        className="w-2.5 h-2.5 rounded-full flex-shrink-0"
        style={{
          backgroundColor: config.visible ? config.colors[0] : 'transparent',
          border: config.visible ? 'none' : `1px solid ${config.colors[0]}`,
        }}
      />
      <span className="flex-1 text-left truncate">{config.name}</span>
      {config.visible ? (
        <Eye className="w-3.5 h-3.5 flex-shrink-0" />
      ) : (
        <EyeOff className="w-3.5 h-3.5 flex-shrink-0" />
      )}
    </button>
  );
}
