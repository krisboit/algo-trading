import { createContext, useContext, useState, useCallback, type ReactNode } from 'react';
import type { StrategyData, IndicatorConfig } from '../types/strategy';
import { buildIndicatorConfigs } from '../utils/transformers';

type ActiveTab = 'chart' | 'analytics';

interface StrategyContextType {
  data: StrategyData | null;
  fileName: string | null;
  selectedTimeframe: string;
  indicatorConfigs: IndicatorConfig[];
  selectedOrderTicket: number | null;
  theme: 'light' | 'dark';
  activeTab: ActiveTab;
  loadData: (data: StrategyData, fileName: string) => void;
  setSelectedTimeframe: (tf: string) => void;
  toggleIndicator: (name: string) => void;
  setSelectedOrderTicket: (ticket: number | null) => void;
  toggleTheme: () => void;
  setActiveTab: (tab: ActiveTab) => void;
}

const StrategyContext = createContext<StrategyContextType | null>(null);

export function StrategyProvider({ children }: { children: ReactNode }) {
  const [data, setData] = useState<StrategyData | null>(null);
  const [fileName, setFileName] = useState<string | null>(null);
  const [selectedTimeframe, setSelectedTimeframe] = useState<string>('');
  const [indicatorConfigs, setIndicatorConfigs] = useState<IndicatorConfig[]>([]);
  const [selectedOrderTicket, setSelectedOrderTicket] = useState<number | null>(null);
  const [activeTab, setActiveTab] = useState<ActiveTab>('chart');
  const [theme, setTheme] = useState<'light' | 'dark'>(() => {
    const stored = localStorage.getItem('theme');
    if (stored === 'light' || stored === 'dark') return stored;
    return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
  });

  const loadData = useCallback((newData: StrategyData, name: string) => {
    setData(newData);
    setFileName(name);
    const primaryTf = newData.meta.primaryTimeframe;
    setSelectedTimeframe(primaryTf);
    setIndicatorConfigs(buildIndicatorConfigs(newData, primaryTf));
    setSelectedOrderTicket(null);
  }, []);

  const handleSetTimeframe = useCallback((tf: string) => {
    setSelectedTimeframe(tf);
    if (data) {
      setIndicatorConfigs(buildIndicatorConfigs(data, tf));
    }
  }, [data]);

  const toggleIndicator = useCallback((name: string) => {
    setIndicatorConfigs(prev =>
      prev.map(c => c.name === name ? { ...c, visible: !c.visible } : c)
    );
  }, []);

  const toggleTheme = useCallback(() => {
    setTheme(prev => {
      const next = prev === 'dark' ? 'light' : 'dark';
      localStorage.setItem('theme', next);
      return next;
    });
  }, []);

  return (
    <StrategyContext.Provider
      value={{
        data,
        fileName,
        selectedTimeframe,
        indicatorConfigs,
        selectedOrderTicket,
        theme,
        activeTab,
        loadData,
        setSelectedTimeframe: handleSetTimeframe,
        toggleIndicator,
        setSelectedOrderTicket,
        toggleTheme,
        setActiveTab,
      }}
    >
      {children}
    </StrategyContext.Provider>
  );
}

export function useStrategy() {
  const ctx = useContext(StrategyContext);
  if (!ctx) throw new Error('useStrategy must be used within StrategyProvider');
  return ctx;
}
