import { useEffect, useRef } from 'react';
import {
  createChart,
  LineSeries,
  AreaSeries,
  type IChartApi,
  ColorType,
  CrosshairMode,
  type Time,
} from 'lightweight-charts';
import { useStrategy } from '../../context/StrategyContext';
import { chartColors } from '../../utils/colors';
import {
  transformEquityBalance,
  transformEquityEquity,
  calculateDrawdownSeries,
} from '../../utils/transformers';

export function EquityCurve() {
  const { data, theme } = useStrategy();
  const containerRef = useRef<HTMLDivElement>(null);
  const chartRef = useRef<IChartApi | null>(null);
  const resizeObserverRef = useRef<ResizeObserver | null>(null);

  const colors = theme === 'dark' ? chartColors.dark : chartColors.light;

  useEffect(() => {
    if (!containerRef.current || !data) return;

    // Cleanup previous
    if (chartRef.current) {
      chartRef.current.remove();
      chartRef.current = null;
    }
    resizeObserverRef.current?.disconnect();

    const chart = createChart(containerRef.current, {
      height: 200,
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
      },
      rightPriceScale: {
        borderColor: colors.grid,
      },
    });

    chartRef.current = chart;

    // Balance line
    const balanceSeries = chart.addSeries(LineSeries, {
      color: '#3b82f6',
      lineWidth: 2,
      priceLineVisible: false,
      lastValueVisible: true,
      title: 'Balance',
    });

    const balanceData = transformEquityBalance(data);
    balanceSeries.setData(balanceData as { time: Time; value: number }[]);

    // Equity line
    const equitySeries = chart.addSeries(LineSeries, {
      color: '#8b5cf6',
      lineWidth: 1,
      priceLineVisible: false,
      lastValueVisible: true,
      title: 'Equity',
    });

    const equityData = transformEquityEquity(data);
    equitySeries.setData(equityData as { time: Time; value: number }[]);

    // Drawdown area (on separate scale)
    const ddSeries = chart.addSeries(AreaSeries, {
      lineColor: 'rgba(239, 68, 68, 0.6)',
      topColor: 'rgba(239, 68, 68, 0.0)',
      bottomColor: 'rgba(239, 68, 68, 0.2)',
      lineWidth: 1,
      priceScaleId: 'drawdown',
      priceLineVisible: false,
      lastValueVisible: false,
      title: 'Drawdown %',
    });

    chart.priceScale('drawdown').applyOptions({
      scaleMargins: { top: 0.7, bottom: 0 },
    });

    const ddData = calculateDrawdownSeries(data);
    ddSeries.setData(ddData as { time: Time; value: number }[]);

    chart.timeScale().fitContent();

    // Resize
    resizeObserverRef.current = new ResizeObserver(entries => {
      for (const entry of entries) {
        chart.applyOptions({ width: entry.contentRect.width });
      }
    });
    resizeObserverRef.current.observe(containerRef.current);

    return () => {
      resizeObserverRef.current?.disconnect();
      chart.remove();
      chartRef.current = null;
    };
  }, [data, theme]);

  if (!data) return null;

  return (
    <div className="bg-white dark:bg-surface-dark rounded-xl border border-gray-200 dark:border-gray-700 overflow-hidden">
      <div className="px-3 py-2 border-b border-gray-200 dark:border-gray-700">
        <h3 className="text-xs font-semibold text-gray-600 dark:text-gray-400">
          Equity Curve & Drawdown
        </h3>
      </div>
      <div ref={containerRef} className="w-full" style={{ height: 200 }} />
    </div>
  );
}
