import { MaintenanceConfig, PageConfig, WorkerConfig } from './types/config'

const { APP_HOST, DOMAIN, SLACK_WEBHOOK_URL } = process.env as any;

const pageConfig: PageConfig = {
  title: "ProTraq Platform Status",
  logo: '/logo.png',
}

const userAgent = 'Uptimeflare'
const checkProxy = 'worker://wnam';

const workerConfig: WorkerConfig = {
  monitors: [
    {
      id: 'website',
      name: 'Website',
      method: 'GET',
      target: `https://${APP_HOST}/signin/password_signin`,
      tooltip: 'ProTraq web application',
      expectedCodes: [200, 302],
      timeout: 20000,
      headers: {
        'User-Agent': userAgent,
        Authorization: 'Basic cHIwdHJhcTpwcjB0cmFx',
      },
      checkProxy,
      checkProxyFallback: true,
    },
    {
      id: 'api',
      name: 'Platform',
      method: 'GET',
      target: `https://api.${DOMAIN}`,
      tooltip: 'Services that power the ProTraq website and mobile app',
      expectedCodes: [200],
      timeout: 20000,
      headers: {
        'User-Agent': userAgent,
      },
      checkProxy,
      checkProxyFallback: true,
    },
  ],
  notification: {
    webhook: {
      url: SLACK_WEBHOOK_URL,
      method: 'POST',
      payloadType: 'json',
      payload: {
        text: '$MSG',
      },
    },
    timeZone: 'America/Dallas',
    gracePeriod: 1,
  },
}

const maintenances: MaintenanceConfig[] = []

export { maintenances, pageConfig, workerConfig }
