'use client';

export function DeleteUserButton({ userId, userName }: { userId: string; userName: string }) {
  async function handleDelete() {
    if (!confirm(`Delete user "${userName}"? This will permanently delete all their data.`)) {
      return;
    }
    const res = await fetch(`/api/admin/users/${userId}`, { method: 'DELETE' });
    if (res.ok) {
      window.location.reload();
    } else {
      const data = await res.json();
      alert(data.error || 'Failed to delete user');
    }
  }

  return (
    <button
      type="button"
      onClick={handleDelete}
      className="text-sm text-red-600 hover:text-red-800 font-medium transition-colors"
    >
      Delete
    </button>
  );
}
