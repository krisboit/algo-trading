/**
 * Format a Unix timestamp to a readable date string
 */
export function formatDate(timestamp: number): string {
  const date = new Date(timestamp * 1000);
  return date.toLocaleDateString('en-US', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  });
}

/**
 * Format a Unix timestamp to date + time
 */
export function formatDateTime(timestamp: number): string {
  const date = new Date(timestamp * 1000);
  return date.toLocaleString('en-US', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  });
}

/**
 * Format duration in seconds to human-readable string
 */
export function formatDuration(seconds: number): string {
  if (seconds < 60) return `${seconds}s`;
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m`;
  if (seconds < 86400) {
    const h = Math.floor(seconds / 3600);
    const m = Math.floor((seconds % 3600) / 60);
    return m > 0 ? `${h}h ${m}m` : `${h}h`;
  }
  const d = Math.floor(seconds / 86400);
  const h = Math.floor((seconds % 86400) / 3600);
  return h > 0 ? `${d}d ${h}h` : `${d}d`;
}

/**
 * Format a number as currency
 */
export function formatCurrency(value: number, currency = 'USD'): string {
  const sign = value >= 0 ? '' : '-';
  const abs = Math.abs(value);
  return `${sign}${currency === 'USD' ? '$' : ''}${abs.toFixed(2)}`;
}

/**
 * Format a number with sign
 */
export function formatProfit(value: number): string {
  const sign = value >= 0 ? '+' : '';
  return `${sign}${value.toFixed(2)}`;
}

/**
 * Format a percentage
 */
export function formatPercent(value: number, decimals = 1): string {
  const sign = value >= 0 ? '+' : '';
  return `${sign}${value.toFixed(decimals)}%`;
}

/**
 * Format a price based on symbol digits
 */
export function formatPrice(value: number, digits = 5): string {
  return value.toFixed(digits);
}

/**
 * Format ratio (e.g., Sharpe, profit factor)
 */
export function formatRatio(value: number): string {
  return value.toFixed(2);
}

/**
 * Format a month string ("2024-01") to readable form
 */
export function formatMonth(monthStr: string): string {
  const [year, month] = monthStr.split('-');
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  const monthIdx = parseInt(month, 10) - 1;
  return `${months[monthIdx]} ${year}`;
}
