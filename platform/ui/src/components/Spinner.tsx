import { Loader2 } from 'lucide-react';

interface SpinnerProps {
  text?: string;
}

export default function Spinner({ text = 'Loading...' }: SpinnerProps) {
  return (
    <div className="flex items-center gap-3 text-gray-500 py-8">
      <Loader2 size={18} className="animate-spin" />
      <span>{text}</span>
    </div>
  );
}
