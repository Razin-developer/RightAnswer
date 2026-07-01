export default function Home() {
  return (
    <div className="min-h-screen bg-gray-50 flex items-center justify-center">
      <div className="text-center">
        <div className="inline-flex items-center justify-center w-20 h-20 bg-blue-600 rounded-3xl mb-6">
          <span className="text-white font-bold text-3xl">RA</span>
        </div>
        <h1 className="text-3xl font-bold text-gray-900 mb-2">RightAnswer API</h1>
        <p className="text-gray-500 mb-8">Backend server for the RightAnswer educational AI app</p>
        <div className="flex flex-col sm:flex-row gap-3 justify-center">
          <a
            href="/dashboard"
            className="inline-flex items-center justify-center px-6 py-3 border border-transparent rounded-lg shadow-sm text-sm font-medium text-white bg-blue-600 hover:bg-blue-700 transition-colors"
          >
            Admin Dashboard
          </a>
          <a
            href="/api/auth/me"
            className="inline-flex items-center justify-center px-6 py-3 border border-gray-300 rounded-lg shadow-sm text-sm font-medium text-gray-700 bg-white hover:bg-gray-50 transition-colors"
          >
            API Status
          </a>
        </div>
      </div>
    </div>
  );
}
