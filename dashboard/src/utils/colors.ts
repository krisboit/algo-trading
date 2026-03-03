// Indicator color palette
const INDICATOR_COLORS = [
  '#3b82f6', // blue
  '#f97316', // orange
  '#8b5cf6', // purple
  '#ec4899', // pink
  '#14b8a6', // teal
  '#f59e0b', // amber
  '#6366f1', // indigo
  '#10b981', // emerald
  '#ef4444', // red
  '#06b6d4', // cyan
];

let colorIndex = 0;

export function getIndicatorColors(bufferCount: number): string[] {
  const colors: string[] = [];
  for (let i = 0; i < bufferCount; i++) {
    colors.push(INDICATOR_COLORS[(colorIndex + i) % INDICATOR_COLORS.length]);
  }
  colorIndex += bufferCount;
  return colors;
}

export function resetColorIndex() {
  colorIndex = 0;
}

// Chart theme colors
export const chartColors = {
  light: {
    background: '#ffffff',
    text: '#374151',
    grid: '#e5e7eb',
    crosshair: '#9ca3af',
    upColor: '#22c55e',
    downColor: '#ef4444',
    volumeUp: 'rgba(34, 197, 94, 0.3)',
    volumeDown: 'rgba(239, 68, 68, 0.3)',
    wickUp: '#22c55e',
    wickDown: '#ef4444',
  },
  dark: {
    background: '#0f1117',
    text: '#d1d5db',
    grid: '#1e2235',
    crosshair: '#6b7280',
    upColor: '#22c55e',
    downColor: '#ef4444',
    volumeUp: 'rgba(34, 197, 94, 0.3)',
    volumeDown: 'rgba(239, 68, 68, 0.3)',
    wickUp: '#22c55e',
    wickDown: '#ef4444',
  },
};

export const tradeColors = {
  winEntry: '#22c55e',
  winExit: '#22c55e',
  winLine: 'rgba(34, 197, 94, 0.5)',
  lossEntry: '#ef4444',
  lossExit: '#ef4444',
  lossLine: 'rgba(239, 68, 68, 0.5)',
};
