import { cookies } from 'next/headers';
import { redirect } from 'next/navigation';
import { verifyAdminToken } from '@/lib/auth';

export default async function AdminLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const cookieStore = await cookies();
  const adminSession = cookieStore.get('admin_session');

  if (!adminSession) {
    redirect('/login');
  }

  const payload = verifyAdminToken(adminSession.value);
  if (!payload || !payload.isAdmin) {
    redirect('/login');
  }

  return (
    <div className="min-h-screen bg-gray-50">
      <nav className="bg-white border-b border-gray-200 shadow-sm">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex justify-between h-16 items-center">
            <div className="flex items-center gap-3">
              <div className="w-8 h-8 bg-blue-600 rounded-lg flex items-center justify-center">
                <span className="text-white font-bold text-sm">RA</span>
              </div>
              <span className="text-xl font-semibold text-gray-900">RightAnswer Admin</span>
            </div>
            <div className="flex items-center gap-4">
              <span className="text-sm text-gray-500">{payload.email}</span>
              <a
                href="/api/admin/logout"
                className="text-sm text-red-600 hover:text-red-800 font-medium"
              >
                Logout
              </a>
            </div>
          </div>
        </div>
      </nav>
      <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">{children}</main>
    </div>
  );
}
