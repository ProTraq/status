import { fetchTimeout } from './util'

export type ProbeIngestEnv = {
  STATUS_PROBE_INGEST_URL?: string
  STATUS_PROBE_INGEST_TOKEN?: string
}

export type ProbeIngestResult = {
  id: string
  status: { ping: number; up: boolean; err: string }
}

/**
 * Copy this cron's probe results to the AWS ingest. A failed POST is logged
 * and does not throw, so the D1 state write still happens. Sustained failure
 * leaves the CloudWatch metric missing, which the alarm treats as a breach.
 */
export async function publishStatusProbes(
  env: ProbeIngestEnv,
  results: Record<string, ProbeIngestResult>
): Promise<void> {
  const url = env.STATUS_PROBE_INGEST_URL?.trim()
  // infra/main writes https://example.com/ until the Function URL output exists.
  if (!url || url.replace(/\/+$/, '') === 'https://example.com') {
    console.log('STATUS_PROBE_INGEST_URL unset, skipping CloudWatch copy')
    return
  }
  const token = env.STATUS_PROBE_INGEST_TOKEN?.trim()
  if (!token) {
    console.log('STATUS_PROBE_INGEST_TOKEN unset, skipping CloudWatch copy')
    return
  }

  const monitors = Object.values(results).map((result) => ({
    id: result.id,
    up: result.status.up,
    ping: result.status.ping,
    err: result.status.err,
  }))

  try {
    const resp = await fetchTimeout(url, 5000, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        authorization: `Bearer ${token}`,
      },
      body: JSON.stringify({ monitors }),
    })
    if (!resp.ok) {
      console.log(
        `Status probe ingest failed: ${resp.status} ${(await resp.text()).slice(0, 300)}`
      )
    } else {
      console.log(`Status probe ingest ok: ${resp.status}`)
      try {
        await resp.body?.cancel()
      } catch (e) {}
    }
  } catch (e) {
    console.log('Status probe ingest error: ' + e)
  }
}
