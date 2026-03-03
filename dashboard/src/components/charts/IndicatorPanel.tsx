import { useEffect, useRef, useState } from 'react';
import {
  createChart,
  LineSeries,
  HistogramSeries,
  type IChartApi,
  type ISeriesApi,
  ColorType,
  CrosshairMode,
  LineStyle,
  type Time,
} from 'lightweight-charts';
import { ChevronDown, ChevronRight } from 'lucide-react';
import { useStrategy } from '../../context/StrategyContext';
import { chartColors } from '../../utils/colors';
import { transformIndicator } from '../../utils/transformers';
import type { IndicatorConfig } from '../../types/strategy';

interface Props {
  config: IndicatorConfig;
  chartId: string;
  registerChart: (id: string, chart: IChartApi) => void;
  unregisterChart: (id: string) => void;
  syncVisibleRange: (sourceId: string) => void;
  syncCrosshair: (sourceId: string, time: Time | null) => void;
}

function getReferenceLines(name: string): { level: number; color: string }[] {
  const n = name.toUpperCase();
  if (n.startsWith('RSI')) {
    return [
      { level: 70, color: 'rgba(239, 68, 68, 0.4)' },
      { level: 30, color: 'rgba(34, 197, 94, 0.4)' },
      { level: 50, color: 'rgba(156, 163, 175, 0.3)' },
    ];
  }
  if (n.startsWith('STOCH') || n.startsWith('WPR')) {
    return [
      { level: 80, color: 'rgba(239, 68, 68, 0.4)' },
      { level: 20, color: 'rgba(34, 197, 94, 0.4)' },
    ];
  }
  if (n.startsWith('CCI')) {
    return [
      { level: 100, color: 'rgba(239, 68, 68, 0.4)' },
      { level: -100, color: 'rgba(34, 197, 94, 0.4)' },
      { level: 0, color: 'rgba(156, 163, 175, 0.3)' },
    ];
  }
  return [];
}

export function IndicatorPanel({
  config,
  chartId,
  registerChart,
  unregisterChart,
  syncVisibleRange,
  syncCrosshair,
}: Props) {
  const { data, selectedTimeframe, theme } = useStrategy();
  const [collapsed, setCollapsed] = useState(false);
  const containerRef = useRef<HTMLDivElement>(null);
  const chartRef = useRef<IChartApi | null>(null);
  const seriesRef = useRef<ISeriesApi<'Line' | 'Histogram'>[]>([]);
  const resizeObserverRef = useRef<ResizeObserver | null>(null);

  const colors = theme === 'dark' ? chartColors.dark : chartColors.light;

  // Create chart
  useEffect(() => {
    if (!containerRef.current || collapsed) return;

    const chart = createChart(containerRef.current, {
      height: 120,
      layout: {
        background: { type: ColorType.Solid, color: colors.background },
        textColor: colors.text,
      },
      grid: {
        vertLines: { color: colors.grid },
        horzLines: { color: colors.grid },
      },
      crosshair: { mode: CrosshairMode.Normal },
      timeScale: {
        timeVisible: true,
        secondsVisible: false,
        borderColor: colors.grid,
        visible: false, // hide time axis on panels - main chart shows it
      },
      rightPriceScale: {
        borderColor: colors.grid,
      },
    });

    chartRef.current = chart;
    registerChart(chartId, chart);

    resizeObserverRef.current = new ResizeObserver(entries => {
      for (const entry of entries) {
        const { width } = entry.contentRect;
        chart.applyOptions({ width });
      }
    });
    resizeObserverRef.current.observe(containerRef.current);

    // Time scale sync
    chart.timeScale().subscribeVisibleLogicalRangeChange(() => {
      syncVisibleRange(chartId);
    });

    // Crosshair sync
    chart.subscribeCrosshairMove((param) => {
      syncCrosshair(chartId, (param.time ?? null) as Time | null);
    });

    return () => {
      resizeObserverRef.current?.disconnect();
      unregisterChart(chartId);
      chart.remove();
      chartRef.current = null;
      seriesRef.current = [];
    };
  }, [collapsed, theme]); // eslint-disable-line react-hooks/exhaustive-deps

  // Set data
  useEffect(() => {
    const chart = chartRef.current;
    if (!chart || !data || collapsed) return;

    const tfData = data.data[selectedTimeframe];
    if (!tfData) return;

    const indData = tfData.indicators[config.name];
    if (!indData) return;

    // Clear old series
    for (const s of seriesRef.current) {
      try { chart.removeSeries(s); } catch { /* ignore */ }
    }
    seriesRef.current = [];

    // Add reference lines
    const refLines = getReferenceLines(config.name);
    for (const ref of refLines) {
      const refSeries = chart.addSeries(LineSeries, {
        color: ref.color,
        lineWidth: 1,
        lineStyle: LineStyle.Dashed,
        priceLineVisible: false,
        lastValueVisible: false,
        crosshairMarkerVisible: false,
      });

      if (indData.data.length > 0) {
        refSeries.setData([
          { time: indData.data[0][0] as Time, value: ref.level },
          { time: indData.data[indData.data.length - 1][0] as Time, value: ref.level },
        ]);
      }
      seriesRef.current.push(refSeries);
    }

    // MACD histogram detection
    const isMACD = config.name.toUpperCase().startsWith('MACD');

    for (let b = 0; b < indData.buffers.length; b++) {
      const lineData = transformIndicator(indData.data, b);
      if (lineData.length === 0) continue;

      if (isMACD && indData.buffers[b] === 'histogram') {
        const histSeries = chart.addSeries(HistogramSeries, {
          color: config.colors[b],
          priceLineVisible: false,
          lastValueVisible: false,
        });

        const histData = lineData.map(d => ({
          time: d.time as Time,
          value: d.value,
          color: d.value >= 0
            ? 'rgba(34, 197, 94, 0.6)'
            : 'rgba(239, 68, 68, 0.6)',
        }));

        histSeries.setData(histData);
        seriesRef.current.push(histSeries);
      } else {
        const lineSeries = chart.addSeries(LineSeries, {
          color: config.colors[b],
          lineWidth: 1,
          priceLineVisible: false,
          lastValueVisible: false,
          crosshairMarkerVisible: true,
        });

        lineSeries.setData(lineData as { time: Time; value: number }[]);
        seriesRef.current.push(lineSeries);
      }
    }

    chart.timeScale().fitContent();
  }, [data, selectedTimeframe, config, collapsed, theme]);

  if (!config.visible) return null;

  return (
    <div className="border-t border-gray-200 dark:border-gray-700/50 flex-shrink-0">
      {/* Header */}
      <button
        onClick={() => setCollapsed(!collapsed)}
        className="w-full flex items-center gap-2 px-2 py-1 text-[11px] font-medium
                   text-gray-500 dark:text-gray-400 hover:bg-gray-50 dark:hover:bg-gray-800/30
                   transition-colors"
      >
        {collapsed ? (
          <ChevronRight className="w-3 h-3" />
        ) : (
          <ChevronDown className="w-3 h-3" />
        )}
        <div
          className="w-1.5 h-1.5 rounded-full"
          style={{ backgroundColor: config.colors[0] }}
        />
        {config.name}
        <span className="text-gray-400 dark:text-gray-500">
          ({config.buffers.join(', ')})
        </span>
      </button>

      {/* Chart */}
      {!collapsed && (
        <div ref={containerRef} className="w-full" style={{ height: 120 }} />
      )}
    </div>
  );
}
