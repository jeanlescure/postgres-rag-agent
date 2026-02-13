// biome-ignore assist/source/organizeImports: dotenv import must remain at the top
import dotenv from 'dotenv'
import { withPayload } from '@payloadcms/next/withPayload'

dotenv.config({ path: '../.env' })

const serverExternalPackages = [
  'pino',
  'pino-pretty',
]

/** @type {import('next').NextConfig} */
const nextConfig = {
  env: {
    NEXT_PUBLIC_PAYLOAD_PUBLIC_HOST: `${process.env.APP_PAYLOAD_PUBLIC_HOST || 'localhost'}`,
    NEXT_PUBLIC_PAYLOAD_PUBLIC_PORT: process.env.APP_PAYLOAD_PUBLIC_PORT || 3000,
    NEXT_PUBLIC_PAYLOAD_ADMIN_PATH: process.env.APP_PAYLOAD_ADMIN_PATH || '/admin',
    NEXT_PUBLIC_PAYLOAD_API_PATH: process.env.APP_PAYLOAD_API_PATH || '/api',
    NEXT_PUBLIC_PAYLOAD_GRAPHQL_PATH: process.env.APP_PAYLOAD_GRAPHQL_PATH || '/graphql',
    PAYLOAD_GRAPHQL_PLAYGROUND_PATH: process.env.PAYLOAD_GRAPHQL_PLAYGROUND_PATH || '/graphql-playground',
  },
  serverExternalPackages,
  webpack: (webpackConfig, { isServer }) => {
    if (isServer) {
      webpackConfig.externals = [
        ...webpackConfig.externals,
        ...serverExternalPackages,
      ]
    }

    webpackConfig.resolve.extensionAlias = {
      '.cjs': ['.cts', '.cjs'],
      '.js': ['.ts', '.tsx', '.js', '.jsx'],
      '.mjs': ['.mts', '.mjs'],
    }

    return webpackConfig
  },
  turbopack: {
    resolveExtensions: ['.tsx', '.ts', '.jsx', '.js', '.mjs', '.json'],
  },
}

export default withPayload(nextConfig, { devBundleServerPackages: false })
