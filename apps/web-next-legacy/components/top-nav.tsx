"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

const links = [
  { href: "/", label: "Home" },
  { href: "/dashboard", label: "Dashboard" },
  { href: "/revision", label: "Revision" },
  { href: "/exam-mode", label: "Exam Mode" },
  { href: "/history", label: "History" },
  { href: "/subscription", label: "Plan" },
  { href: "/teacher", label: "Teacher" },
  { href: "/admin", label: "Admin" },
];

export function TopNav() {
  const pathname = usePathname();

  return (
    <nav className="sticky top-4 z-20 mx-auto flex w-full max-w-7xl items-center justify-between rounded-full border border-white/70 bg-white/80 px-4 py-3 shadow-sm backdrop-blur">
      <Link href="/" className="text-sm font-semibold uppercase tracking-[0.3em] text-ink">
        Right Answer
      </Link>
      <div className="hidden flex-wrap items-center gap-2 md:flex">
        {links.map((link) => (
          <Link
            key={link.href}
            href={link.href}
            className={`rounded-full px-4 py-2 text-sm ${
              pathname === link.href ? "bg-ink text-white" : "text-slate-600"
            }`}
          >
            {link.label}
          </Link>
        ))}
      </div>
      <div className="flex gap-2">
        <Link href="/login" className="rounded-full border border-slate-200 px-4 py-2 text-sm text-slate-700">
          Login
        </Link>
        <Link href="/signup" className="rounded-full bg-coral px-4 py-2 text-sm font-semibold text-white">
          Sign up
        </Link>
      </div>
    </nav>
  );
}
