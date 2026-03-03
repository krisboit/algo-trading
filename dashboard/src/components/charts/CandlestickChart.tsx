import { useEffect, useRef, useCallback } from 'react';
import {
  createChart,
  createSeriesMarkers,
  CandlestickSeries,
  LineSeries,
  HistogramSeries,
  type IChartApi,
  type ISeriesApi,
  type ISeriesMarkersPluginApi,
  ColorType,
  CrosshairMode,
  LineStyle,
  type SeriesMarker,
  type Time,
} from 'lightweight-charts';
import { useStrategy } from '../../context/StrategyContext';
import { chartColors, tradeColors } from '../../utils/colors';
import {
  transformCandles,
  transformVolume,
  transformIndicator,
  transformTradeMarkers,
} from '../../utils/transformers';

interface Props {
  chartId: string;
  registerChart: (id: string, chart: IChartApi) => void;
  unregisterChart: (id: string) => void;
  syncVisibleRange: (sourceId: string) => void;
  syncCrosshair: (sourceId: string, time: Time | null) => void;
}

export function CandlestickChart({
  chartId,
  registerChart,
  unregisterChart,
  syncVisibleRange,
  syncCrosshair,
}: Props) {
  const { data, selectedTimeframe, indicatorConfigs, selectedOrderTicket, theme } = useStrategy();
  const containerRef = useRef<HTMLDivElement>(null);
  const chartRef = useRef<IChartApi | null>(null);
  const candleSeriesRef = useRef<ISeriesApi<'Candlestick'> | null>(null);
  const volumeSeriesRef = useRef<ISeriesApi<'Histogram'> | null>(null);
  const overlaySeriesRef = useRef<Map<string, ISeriesApi<'Line'>[]>>(new Map());
  const tradeLineSeriesRef = useRef<ISeriesApi<'Line'>[]>([]);
  const markersPluginRef = useRef<ISeriesMarkersPluginApi<Time> | null>(null);
  const resizeObserverRef = useRef<ResizeObserver | null>(null);

  const colors = theme === 'dark' ? chartColors.dark : chartColors.light;

  // Create chart
  useEffect(() => {
    if (!containerRef.current) return;

    const chart = createChart(containerRef.current, {
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
    registerChart(chartId, chart);

    // Handle resize
    resizeObserverRef.current = new ResizeObserver(entries => {
      for (const entry of entries) {
        const { width, height } = entry.contentRect;
        chart.applyOptions({ width, height });
      }
    });
    resizeObserverRef.current.observe(containerRef.current);

    // Time scale sync - fire on scroll/zoom
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
      candleSeriesRef.current = null;
      volumeSeriesRef.current = null;
      overlaySeriesRef.current.clear();
      tradeLineSeriesRef.current = [];
      markersPluginRef.current = null;
    };
  }, [theme]); // eslint-disable-line react-hooks/exhaustive-deps

  // Set data
  useEffect(() => {
    const chart = chartRef.current;
    if (!chart || !data) return;

    const tfData = data.data[selectedTimeframe];
    if (!tfData) return;

    // Remove old series
    if (candleSeriesRef.current) {
      try { chart.removeSeries(candleSeriesRef.current); } catch { /* ignore */ }
    }
    if (volumeSeriesRef.current) {
      try { chart.removeSeries(volumeSeriesRef.current); } catch { /* ignore */ }
    }
    for (const [, seriesList] of overlaySeriesRef.current) {
      for (const s of seriesList) {
        try { chart.removeSeries(s); } catch { /* ignore */ }
      }
    }
    for (const s of tradeLineSeriesRef.current) {
      try { chart.removeSeries(s); } catch { /* ignore */ }
    }

    candleSeriesRef.current = null;
    volumeSeriesRef.current = null;
    overlaySeriesRef.current.clear();
    tradeLineSeriesRef.current = [];
    markersPluginRef.current = null;

    // Candlestick series
    const candleSeries = chart.addSeries(CandlestickSeries, {
      upColor: colors.upColor,
      downColor: colors.downColor,
      borderVisible: false,
      wickUpColor: colors.wickUp,
      wickDownColor: colors.wickDown,
    });

    const candles = transformCandles(tfData);
    candleSeries.setData(candles as { time: Time; open: number; high: number; low: number; close: number }[]);
    candleSeriesRef.current = candleSeries;

    // Create markers plugin
    markersPluginRef.current = createSeriesMarkers(candleSeries);

    // Volume histogram
    const volumeSeries = chart.addSeries(HistogramSeries, {
      priceFormat: { type: 'volume' },
      priceScaleId: 'volume',
    });

    chart.priceScale('volume').applyOptions({
      scaleMargins: { top: 0.85, bottom: 0 },
    });

    const volumes = transformVolume(tfData);
    volumeSeries.setData(volumes as { time: Time; value: number; color: string }[]);
    volumeSeriesRef.current = volumeSeries;

    chart.timeScale().fitContent();
  }, [data, selectedTimeframe, theme]); // eslint-disable-line react-hooks/exhaustive-deps

  // Update overlay indicators
  useEffect(() => {
    const chart = chartRef.current;
    if (!chart || !data) return;

    const tfData = data.data[selectedTimeframe];
    if (!tfData) return;

    // Remove existing overlay series
    for (const [, seriesList] of overlaySeriesRef.current) {
      for (const s of seriesList) {
        try { chart.removeSeries(s); } catch { /* ignore */ }
      }
    }
    overlaySeriesRef.current.clear();

    // Add visible overlay indicators
    const overlays = indicatorConfigs.filter(c => c.location === 'overlay' && c.visible);

    for (const config of overlays) {
      const indData = tfData.indicators[config.name];
      if (!indData) continue;

      const seriesList: ISeriesApi<'Line'>[] = [];

      for (let b = 0; b < indData.buffers.length; b++) {
        const lineData = transformIndicator(indData.data, b);
        if (lineData.length === 0) continue;

        const lineSeries = chart.addSeries(LineSeries, {
          color: config.colors[b],
          lineWidth: 1,
          priceLineVisible: false,
          lastValueVisible: false,
          crosshairMarkerVisible: false,
        });

        lineSeries.setData(lineData as { time: Time; value: number }[]);
        seriesList.push(lineSeries);
      }

      overlaySeriesRef.current.set(config.name, seriesList);
    }
  }, [data, selectedTimeframe, indicatorConfigs, theme]);

  // Update trade markers
  const updateTradeMarkers = useCallback(() => {
    const chart = chartRef.current;
    const markersPlugin = markersPluginRef.current;
    if (!chart || !markersPlugin || !data) return;

    // Remove existing trade lines
    for (const s of tradeLineSeriesRef.current) {
      try { chart.removeSeries(s); } catch { /* ignore */ }
    }
    tradeLineSeriesRef.current = [];

    const trades = transformTradeMarkers(data);
    if (trades.length === 0) {
      markersPlugin.setMarkers([]);
      return;
    }

    const markers: SeriesMarker<Time>[] = [];

    for (const trade of trades) {
      const isSelected = selectedOrderTicket === trade.orderTicket;
      const color = trade.isWin ? tradeColors.winEntry : tradeColors.lossEntry;
      const size = isSelected ? 2 : 1;

      markers.push({
        time: trade.entryTime as Time,
        position: trade.type === 'BUY' ? 'belowBar' : 'aboveBar',
        color,
        shape: trade.type === 'BUY' ? 'arrowUp' : 'arrowDown',
        text: isSelected ? `${trade.type} #${trade.orderTicket}` : '',
        size,
      });

      markers.push({
        time: trade.exitTime as Time,
        position: trade.type === 'BUY' ? 'aboveBar' : 'belowBar',
        color,
        shape: trade.type === 'BUY' ? 'arrowDown' : 'arrowUp',
        text: isSelected ? `Exit ${trade.profit >= 0 ? '+' : ''}${trade.profit.toFixed(2)}` : '',
        size,
      });

      const lineColor = trade.isWin ? tradeColors.winLine : tradeColors.lossLine;
      const lineSeries = chart.addSeries(LineSeries, {
        color: isSelected ? (trade.isWin ? tradeColors.winEntry : tradeColors.lossEntry) : lineColor,
        lineWidth: isSelected ? 2 : 1,
        lineStyle: LineStyle.Dashed,
        priceLineVisible: false,
        lastValueVisible: false,
        crosshairMarkerVisible: false,
        pointMarkersVisible: false,
      });

      lineSeries.setData([
        { time: trade.entryTime as Time, value: trade.entryPrice },
        { time: trade.exitTime as Time, value: trade.exitPrice },
      ]);

      tradeLineSeriesRef.current.push(lineSeries);
    }

    markers.sort((a, b) => (a.time as number) - (b.time as number));
    markersPlugin.setMarkers(markers);
  }, [data, selectedOrderTicket]);

  useEffect(() => {
    updateTradeMarkers();
  }, [updateTradeMarkers, theme]);

  // Zoom to selected order
  useEffect(() => {
    const chart = chartRef.current;
    if (!chart || !data || !selectedOrderTicket) return;

    const order = data.orders.find(o => o.ticket === selectedOrderTicket);
    if (!order || !order.closeTime) return;

    const padding = (order.closeTime - order.openTime) * 0.5;
    chart.timeScale().setVisibleRange({
      from: (order.openTime - padding) as Time,
      to: (order.closeTime + padding) as Time,
    });
  }, [selectedOrderTicket, data]);

  return (
    <div ref={containerRef} className="w-full h-full" />
  );
}
