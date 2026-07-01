import type { NextConfig } from 'next';

const nextConfig: NextConfig = {
  experimental: {
    serverActions: {
      bodySizeLimit: '110mb',
    },
  },
  api: {
    bodyParser: {
      sizeLimit: '110mb',
    },
  },
};

export default nextConfig;
