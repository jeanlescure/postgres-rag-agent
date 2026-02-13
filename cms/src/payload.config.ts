import { postgresAdapter } from '@payloadcms/db-postgres'
import { lexicalEditor } from '@payloadcms/richtext-lexical'
import { openapi, rapidoc, redoc, swaggerUI } from 'payload-oapi'
import path from 'path'
import { buildConfig } from 'payload'
import pino from 'pino'
import pinoPretty from 'pino-pretty'
import { fileURLToPath } from 'url'
import sharp from 'sharp'

import { Users } from './collections/Users'
import { Media } from './collections/Media'

const filename = fileURLToPath(import.meta.url)
const dirname = path.dirname(filename)

const logLevel = process.env.PAYLOAD_LOG_LEVEL || 'info'

const prettyStream = pinoPretty({
  colorize: true,
  translateTime: 'SYS:standard',
  ignore: 'pid,hostname',
})

const logger = pino(
  {
    level: logLevel,
  },
  prettyStream,
)

export default buildConfig({
  serverURL: `https://${process.env.NEXT_PUBLIC_PAYLOAD_PUBLIC_HOST || 'localhost:3000'}`,
  routes: {
    admin: process.env.NEXT_PUBLIC_PAYLOAD_ADMIN_PATH || '/admin',
    api: process.env.NEXT_PUBLIC_PAYLOAD_API_PATH || '/api',
    graphQL: process.env.NEXT_PUBLIC_PAYLOAD_GRAPHQL_PATH || '/graphql',
    graphQLPlayground: process.env.PAYLOAD_GRAPHQL_PLAYGROUND_PATH || '/graphql-playground',
  },
  endpoints: [
    {
      path: '/health',
      method: 'get',
      handler: async (req) => {
        return new Response(JSON.stringify({ status: 'ok' }), {
          status: 200,
          headers: { 'Content-Type': 'application/json' },
        })
      },
    },
  ],
  admin: {
    user: Users.slug,
    importMap: {
      baseDir: path.resolve(dirname),
    },
  },
  collections: [Users, Media],
  editor: lexicalEditor(),
  secret: process.env.PAYLOAD_SECRET || '',
  typescript: {
    outputFile: path.resolve(dirname, 'payload-types.ts'),
  },
  db: postgresAdapter({
    pool: {
      connectionString: process.env.DATABASE_URL || '',
    },
  }),
  sharp,
  plugins: [
    openapi({ openapiVersion: '3.0', metadata: { title: 'RAG API', version: '1.0.0' } }),
    swaggerUI({ docsUrl: process.env.PAYLOAD_SWAGGER_PATH || '/swagger' }),
    redoc({ docsUrl: process.env.PAYLOAD_REDOC_PATH || '/redoc' }),
    rapidoc({ docsUrl: process.env.PAYLOAD_RAPIDOC_PATH || '/rapidoc' }),
  ],
  logger,
})
