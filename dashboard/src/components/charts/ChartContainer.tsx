import { useRef, useCallback, useEffect } from 'react';
import type { IChartApi, LogicalRange, Time } from 'lightweight-charts';
import { useStrategy } from '../../context/StrategyContext';
import { CandlestickChart } from './CandlestickChart';
import { IndicatorPanel } from './IndicatorPanel';
import { ChartToolbar } from './ChartToolbar';

export function ChartContainer() {
  const { indicatorConfigs } = useStrategy();

  // Chart registry for time scale sync
  const chartRegistry = useRef<Map<string, IChartApi>>(new Map());
  const isSyncing = useRef(false);

  const panelIndicators = indicatorConfigs.filter(c => c.location === 'panel' && c.visible);

  // Register a chart instance
  const registerChart = useCallback((id: string, chart: IChartApi) => {
    chartRegistry.current.set(id, chart);
  }, []);

  // Unregister a chart instance
  const unregisterChart = useCallback((id: string) => {
    chartRegistry.current.delete(id);
  }, []);

  // Sync visible logical range from one chart to all others
  const syncVisibleRange = useCallback((sourceId: string) => {
    if (isSyncing.current) return;

    const sourceChart = chartRegistry.current.get(sourceId);
    if (!sourceChart) return;

    const logicalRange = sourceChart.timeScale().getVisibleLogicalRange();
    if (!logicalRange) return;

    isSyncing.current = true;

    chartRegistry.current.forEach((chart, id) => {
      if (id !== sourceId) {
        chart.timeScale().setVisibleLogicalRange(logicalRange as LogicalRange);
      }
    });

    isSyncing.current = false;
  }, []);

  // Sync crosshair position from one chart to all others
  const syncCrosshair = useCallback((sourceId: string, time: Time | null) => {
    if (isSyncing.current) return;
    isSyncing.current = true;

    chartRegistry.current.forEach((chart, id) => {
      if (id !== sourceId) {
        if (time !== null) {
          // Move crosshair to time on other charts - use first series
          // setCrosshairPosition requires a series, so we need to get one
          try {
            // In LWC v5, we can pass NaN for price to just set the time
            // We need any series on the chart
            chart.setCrosshairPosition(NaN, time, undefined as never);
          } catch {
            // Fallback: just clear
          }
        } else {
          chart.clearCrosshairPosition();
        }
      }
    });

    isSyncing.current = false;
  }, []);

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      chartRegistry.current.clear();
    };
  }, []);

  return (
    <div className="flex-1 flex flex-col overflow-hidden">
      {/* Toolbar */}
      <ChartToolbar />

      {/* Charts area - flex column, main chart takes remaining space */}
      <div className="flex-1 flex flex-col min-h-0">
        {/* Main candlestick chart - takes all remaining space */}
        <div className="flex-1 min-h-[200px]">
          <CandlestickChart
            chartId="main"
            registerChart={registerChart}
            unregisterChart={unregisterChart}
            syncVisibleRange={syncVisibleRange}
            syncCrosshair={syncCrosshair}
          />
        </div>

        {/* Indicator panels - fixed height each */}
        {panelIndicators.map(config => (
          <IndicatorPanel
            key={config.name}
            config={config}
            chartId={`panel-${config.name}`}
            registerChart={registerChart}
            unregisterChart={unregisterChart}
            syncVisibleRange={syncVisibleRange}
            syncCrosshair={syncCrosshair}
          />
        ))}
      </div>
    </div>
  );
}
