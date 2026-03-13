import { useState } from 'react';
import { signInWithGoogle } from '../services/firebase';
import { Loader2 } from 'lucide-react';

export default function Login() {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleLogin = async () => {
    setLoading(true);
    setError(null);
    try {
      await signInWithGoogle();
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Login failed';
      setError(message);
      console.error('Login failed:', err);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="flex h-screen items-center justify-center bg-gray-950">
      <div className="text-center space-y-6">
        <div>
          <h1 className="text-3xl font-bold text-white">Algo Trading Platform</h1>
          <p className="text-gray-500 mt-2">Strategy Optimization Management</p>
        </div>
        {error && (
          <div className="p-3 bg-red-500/10 border border-red-500/30 rounded-lg text-red-400 text-sm max-w-sm mx-auto">
            {error}
          </div>
        )}
        <button
          onClick={handleLogin}
          disabled={loading}
          className="px-6 py-3 bg-blue-600 hover:bg-blue-700 disabled:bg-blue-800 disabled:opacity-50 text-white rounded-lg font-medium transition-colors flex items-center gap-2 mx-auto"
        >
          {loading && <Loader2 size={16} className="animate-spin" />}
          {loading ? 'Signing in...' : 'Sign in with Google'}
        </button>
      </div>
    </div>
  );
}
