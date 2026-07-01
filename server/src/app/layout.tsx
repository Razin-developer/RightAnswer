import type { Metadata } from 'next';
import './globals.css';

export const metadata: Metadata = {
  title: 'RightAnswer Server',
  description: 'Backend API for RightAnswer educational AI app',
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
