import { Link, useLocation } from 'react-router-dom';
import { User } from 'firebase/auth';
import { signOut } from '../services/firebase';
import {
  LayoutDashboard,
  BookOpen,
  Zap,
  ListOrdered,
  Server,
  LogOut,
} from 'lucide-react';

const NAV_ITEMS = [
  { path: '/', label: 'Dashboard', icon: LayoutDashboard },
  { path: '/strategies', label: 'Strategies', icon: BookOpen },
  { path: '/optimizations', label: 'Optimizations', icon: Zap },
  { path: '/jobs', label: 'Jobs', icon: ListOrdered },
  { path: '/workers', label: 'Workers', icon: Server },
];

interface LayoutProps {
  user: User;
  children: React.ReactNode;
}

export default function Layout({ user, children }: LayoutProps) {
  const location = useLocation();

  return (
    <div className="flex h-screen bg-gray-950">
      {/* Sidebar */}
      <aside className="w-64 bg-gray-900 border-r border-gray-800 flex flex-col">
        <div className="p-4 border-b border-gray-800">
          <h1 className="text-lg font-bold text-white">Algo Trading</h1>
          <p className="text-xs text-gray-500 mt-1">Optimization Platform</p>
        </div>

        <nav className="flex-1 p-3 space-y-1">
          {NAV_ITEMS.map(({ path, label, icon: Icon }) => {
            const isActive = path === '/'
              ? location.pathname === '/'
              : location.pathname.startsWith(path);
            return (
              <Link
                key={path}
                to={path}
                className={`flex items-center gap-3 px-3 py-2 rounded-lg text-sm font-medium transition-colors ${
                  isActive
                    ? 'bg-blue-600/20 text-blue-400'
                    : 'text-gray-400 hover:bg-gray-800 hover:text-gray-200'
                }`}
              >
                <Icon size={18} />
                {label}
              </Link>
            );
          })}
        </nav>

        <div className="p-3 border-t border-gray-800">
          <div className="flex items-center gap-3 px-3 py-2">
            {user.photoURL && (
              <img
                src={user.photoURL}
                alt=""
                className="w-8 h-8 rounded-full"
              />
            )}
            <div className="flex-1 min-w-0">
              <p className="text-sm text-gray-300 truncate">
                {user.displayName || user.email}
              </p>
            </div>
            <button
              onClick={() => signOut()}
              className="text-gray-500 hover:text-gray-300 transition-colors"
              title="Sign out"
            >
              <LogOut size={16} />
            </button>
          </div>
        </div>
      </aside>

      {/* Main content */}
      <main className="flex-1 overflow-auto">
        <div className="p-6">{children}</div>
      </main>
    </div>
  );
}
