import { StrategyProvider, useStrategy } from './context/StrategyContext';
import { Dashboard } from './components/layout/Dashboard';
import { useEffect } from 'react';

function ThemeManager({ children }: { children: React.ReactNode }) {
  const { theme } = useStrategy();

  useEffect(() => {
    document.documentElement.classList.toggle('dark', theme === 'dark');
  }, [theme]);

  return <>{children}</>;
}

function App() {
  return (
    <StrategyProvider>
      <ThemeManager>
        <Dashboard />
      </ThemeManager>
    </StrategyProvider>
  );
}

export default App;
