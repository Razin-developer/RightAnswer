import connectDB from '@/lib/mongodb';
import User from '@/lib/models/User';
import Chat from '@/lib/models/Chat';
import ChatMessage from '@/lib/models/ChatMessage';
import ShareToken from '@/lib/models/ShareToken';
import { DeleteUserButton } from './DeleteUserButton';

async function getStats() {
  await connectDB();

  const [totalUsers, totalChats, totalMessages, activeShares] = await Promise.all([
    User.countDocuments(),
    Chat.countDocuments(),
    ChatMessage.countDocuments(),
    ShareToken.countDocuments({ expiresAt: { $gt: new Date() } }),
  ]);

  return { totalUsers, totalChats, totalMessages, activeShares };
}

async function getUsers() {
  await connectDB();

  const users = await User.find()
    .select('-passwordHash -passwordResetToken -passwordResetExpiry')
    .sort({ createdAt: -1 })
    .lean();

  const userIds = users.map((u) => u._id);
  const chatCounts = await Chat.aggregate([
    { $match: { ownerId: { $in: userIds } } },
    { $group: { _id: '$ownerId', count: { $sum: 1 } } },
  ]);

  const chatCountMap: Record<string, number> = {};
  chatCounts.forEach((item: { _id: unknown; count: number }) => {
    chatCountMap[String(item._id)] = item.count;
  });

  return users.map((u) => ({
    id: u._id.toString(),
    email: u.email,
    name: u.name,
    createdAt: u.createdAt.toISOString(),
    chatCount: chatCountMap[u._id.toString()] || 0,
  }));
}

async function getRecentShareTokens() {
  await connectDB();

  const tokens = await ShareToken.find().sort({ createdAt: -1 }).limit(20).lean();

  return tokens.map((t) => ({
    id: t._id.toString(),
    token: t.token.substring(0, 8) + '...',
    type: t.type,
    expiresAt: t.expiresAt.toISOString(),
    redeemed: t.redeemed,
    expired: t.expiresAt < new Date(),
  }));
}

function StatCard({
  title,
  value,
  color,
  icon,
}: {
  title: string;
  value: number;
  color: string;
  icon: string;
}) {
  return (
    <div className="bg-white rounded-xl border border-gray-200 shadow-sm p-6">
      <div className="flex items-center justify-between">
        <div>
          <p className="text-sm font-medium text-gray-500">{title}</p>
          <p className={`text-3xl font-bold mt-1 ${color}`}>{value.toLocaleString()}</p>
        </div>
        <div className="text-4xl opacity-20">{icon}</div>
      </div>
    </div>
  );
}

export default async function DashboardPage() {
  const [stats, users, shareTokens] = await Promise.all([
    getStats(),
    getUsers(),
    getRecentShareTokens(),
  ]);

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-2xl font-bold text-gray-900">Dashboard</h1>
        <p className="text-gray-500 mt-1">Overview of your RightAnswer platform</p>
      </div>

      {/* Stats Cards */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        <StatCard title="Total Users" value={stats.totalUsers} color="text-blue-600" icon="👥" />
        <StatCard title="Total Chats" value={stats.totalChats} color="text-green-600" icon="💬" />
        <StatCard
          title="Total Messages"
          value={stats.totalMessages}
          color="text-purple-600"
          icon="📝"
        />
        <StatCard
          title="Active Share Links"
          value={stats.activeShares}
          color="text-orange-600"
          icon="🔗"
        />
      </div>

      {/* Users Table */}
      <div className="bg-white rounded-xl border border-gray-200 shadow-sm overflow-hidden">
        <div className="px-6 py-4 border-b border-gray-200">
          <h2 className="text-lg font-semibold text-gray-900">Users</h2>
          <p className="text-sm text-gray-500 mt-0.5">{users.length} registered users</p>
        </div>

        {users.length === 0 ? (
          <div className="px-6 py-12 text-center text-gray-500">
            <p className="text-4xl mb-3">👤</p>
            <p>No users yet</p>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead>
                <tr className="bg-gray-50">
                  <th className="text-left px-6 py-3 text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Name
                  </th>
                  <th className="text-left px-6 py-3 text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Email
                  </th>
                  <th className="text-left px-6 py-3 text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Joined
                  </th>
                  <th className="text-left px-6 py-3 text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Chats
                  </th>
                  <th className="text-right px-6 py-3 text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Actions
                  </th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-200">
                {users.map((user) => (
                  <tr key={user.id} className="hover:bg-gray-50 transition-colors">
                    <td className="px-6 py-4">
                      <div className="flex items-center gap-3">
                        <div className="w-8 h-8 rounded-full bg-blue-100 flex items-center justify-center flex-shrink-0">
                          <span className="text-blue-700 text-sm font-medium">
                            {user.name.charAt(0).toUpperCase()}
                          </span>
                        </div>
                        <span className="text-sm font-medium text-gray-900">{user.name}</span>
                      </div>
                    </td>
                    <td className="px-6 py-4 text-sm text-gray-600">{user.email}</td>
                    <td className="px-6 py-4 text-sm text-gray-500">
                      {new Date(user.createdAt).toLocaleDateString('en-US', {
                        year: 'numeric',
                        month: 'short',
                        day: 'numeric',
                      })}
                    </td>
                    <td className="px-6 py-4">
                      <span className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800">
                        {user.chatCount}
                      </span>
                    </td>
                    <td className="px-6 py-4 text-right">
                      <DeleteUserButton userId={user.id} userName={user.name} />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {/* Share Tokens Table */}
      <div className="bg-white rounded-xl border border-gray-200 shadow-sm overflow-hidden">
        <div className="px-6 py-4 border-b border-gray-200">
          <h2 className="text-lg font-semibold text-gray-900">Recent Share Links</h2>
          <p className="text-sm text-gray-500 mt-0.5">Last 20 share tokens created</p>
        </div>

        {shareTokens.length === 0 ? (
          <div className="px-6 py-12 text-center text-gray-500">
            <p className="text-4xl mb-3">🔗</p>
            <p>No share tokens yet</p>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead>
                <tr className="bg-gray-50">
                  <th className="text-left px-6 py-3 text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Token
                  </th>
                  <th className="text-left px-6 py-3 text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Type
                  </th>
                  <th className="text-left px-6 py-3 text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Expires
                  </th>
                  <th className="text-left px-6 py-3 text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Status
                  </th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-200">
                {shareTokens.map((token) => (
                  <tr key={token.id} className="hover:bg-gray-50 transition-colors">
                    <td className="px-6 py-4 text-sm font-mono text-gray-700">{token.token}</td>
                    <td className="px-6 py-4">
                      <span
                        className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium ${
                          token.type === 'chat'
                            ? 'bg-blue-100 text-blue-800'
                            : 'bg-purple-100 text-purple-800'
                        }`}
                      >
                        {token.type}
                      </span>
                    </td>
                    <td className="px-6 py-4 text-sm text-gray-500">
                      {new Date(token.expiresAt).toLocaleString('en-US', {
                        month: 'short',
                        day: 'numeric',
                        hour: '2-digit',
                        minute: '2-digit',
                      })}
                    </td>
                    <td className="px-6 py-4">
                      {token.expired ? (
                        <span className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-600">
                          Expired
                        </span>
                      ) : token.redeemed ? (
                        <span className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-yellow-100 text-yellow-800">
                          Redeemed
                        </span>
                      ) : (
                        <span className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800">
                          Active
                        </span>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  );
}
