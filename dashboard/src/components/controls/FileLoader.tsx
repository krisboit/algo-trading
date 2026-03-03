import { useState, useCallback, useRef } from 'react';
import { Upload, FileJson, AlertCircle } from 'lucide-react';
import { useStrategy } from '../../context/StrategyContext';
import type { StrategyData } from '../../types/strategy';

export function FileLoader() {
  const { loadData } = useStrategy();
  const [isDragging, setIsDragging] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const processFile = useCallback((file: File) => {
    setError(null);

    if (!file.name.endsWith('.json')) {
      setError('Please select a JSON file');
      return;
    }

    const reader = new FileReader();
    reader.onload = (e) => {
      try {
        const json = JSON.parse(e.target?.result as string) as StrategyData;

        // Basic validation
        if (!json.meta || !json.stats || !json.data || !json.orders || !json.equity) {
          setError('Invalid strategy export format. Missing required fields.');
          return;
        }

        loadData(json, file.name);
      } catch {
        setError('Failed to parse JSON file');
      }
    };
    reader.readAsText(file);
  }, [loadData]);

  const handleDrop = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    setIsDragging(false);
    const file = e.dataTransfer.files[0];
    if (file) processFile(file);
  }, [processFile]);

  const handleDragOver = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    setIsDragging(true);
  }, []);

  const handleDragLeave = useCallback(() => {
    setIsDragging(false);
  }, []);

  const handleClick = () => fileInputRef.current?.click();

  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (file) processFile(file);
  };

  return (
    <div className="flex flex-col items-center justify-center min-h-[60vh] p-8">
      <div
        onDrop={handleDrop}
        onDragOver={handleDragOver}
        onDragLeave={handleDragLeave}
        onClick={handleClick}
        className={`
          w-full max-w-lg p-12 rounded-2xl border-2 border-dashed cursor-pointer
          transition-all duration-200 flex flex-col items-center gap-4
          ${isDragging
            ? 'border-blue-500 bg-blue-50 dark:bg-blue-900/20'
            : 'border-gray-300 dark:border-gray-600 hover:border-blue-400 dark:hover:border-blue-500 hover:bg-gray-50 dark:hover:bg-gray-800/50'
          }
        `}
      >
        <div className={`p-4 rounded-full ${isDragging ? 'bg-blue-100 dark:bg-blue-900/40' : 'bg-gray-100 dark:bg-gray-800'}`}>
          {isDragging ? (
            <FileJson className="w-12 h-12 text-blue-500" />
          ) : (
            <Upload className="w-12 h-12 text-gray-400 dark:text-gray-500" />
          )}
        </div>

        <div className="text-center">
          <p className="text-lg font-medium text-gray-700 dark:text-gray-300">
            {isDragging ? 'Drop your file here' : 'Drop strategy JSON file here'}
          </p>
          <p className="text-sm text-gray-500 dark:text-gray-400 mt-1">
            or click to browse
          </p>
        </div>

        <input
          ref={fileInputRef}
          type="file"
          accept=".json"
          onChange={handleFileChange}
          className="hidden"
        />
      </div>

      {error && (
        <div className="mt-4 flex items-center gap-2 text-red-500 dark:text-red-400">
          <AlertCircle className="w-4 h-4" />
          <span className="text-sm">{error}</span>
        </div>
      )}

      <p className="mt-6 text-sm text-gray-400 dark:text-gray-500">
        Export from MetaTrader 5 Strategy Tester using StrategyExporter
      </p>
    </div>
  );
}
