import 'server-only';
import { createHmac } from 'node:crypto';
import { getWorkspaceDb } from './firebaseAdmin';
import { currentWorkspace } from './workspace';
import { metaSettings } from './metaConnection';
import { decryptMetaToken } from './metaSecurity';
export class MetaRequestError extends Error {
  constructor(public uncertain: boolean, public code: number | null, public subcode: number | null) {
    super(uncertain ? 'Meta response was uncertain. Check the relevant Instagram or Facebook account before resolving this item; it will not be retried automatically.' : `Meta rejected the request (code ${code ?? 'unavailable'}${subcode ? `/${subcode}` : ''}). Check account permissions and media requirements.`);
  }
}
export async function socialConnection() {
  const record = (await (await getWorkspaceDb()).collection('metaConnections').doc('rydr').get()).data();
  if (!record?.tokenEncrypted || !record.instagramId || !record.pageId) throw new Error('Connect Rydr’s business accounts first.');
  if (record.expiresAt && record.expiresAt <= Date.now()) throw new Error('Reconnect Meta: the saved token has expired.');
  return { pageId: String(record.pageId), instagramId: String(record.instagramId), token: decryptMetaToken(record.tokenEncrypted, metaSettings().key, `${await currentWorkspace()}:${record.pageId}`) };
}
export async function socialGraph(path: string, params: Record<string, unknown> = {}, method: 'GET' | 'POST' = 'GET') {
  if (!/^[\w/]+$/.test(path)) throw new Error('Invalid Meta endpoint.');
  if (method === 'POST' && await currentWorkspace() !== 'live-beta') throw new Error('Test workspace cannot change Meta accounts.');
  const connection = await socialConnection(), settings = metaSettings();
  const proof = createHmac('sha256', settings.secret).update(connection.token).digest('hex');
  const url = new URL(`https://graph.facebook.com/${settings.version}/${path}`);
  let response: Response;
  try {
    if (method === 'GET') url.search = new URLSearchParams(Object.entries({ ...params, appsecret_proof: proof }).map(([k,v]) => [k,String(v)])).toString();
    response = await fetch(url, { method, headers: { Authorization: `Bearer ${connection.token}`, 'Content-Type': 'application/json' },
      ...(method === 'POST' ? { body: JSON.stringify({ ...params, appsecret_proof: proof }) } : {}), cache: 'no-store', redirect: 'error', signal: AbortSignal.timeout(20000) });
  } catch { throw new MetaRequestError(true, null, null); }
  let data: any;
  try { data = await response.json(); } catch { throw new MetaRequestError(true, null, null); }
  if (!response.ok || data.error) {
    const error = new MetaRequestError(response.status >= 500, Number(data.error?.code) || null, Number(data.error?.error_subcode) || null);
    // Surface only known permission identifiers, never raw provider messages or credentials.
    const required = ['pages_manage_posts','pages_manage_metadata','pages_messaging','instagram_manage_messages','instagram_basic'].filter(scope => String(data.error?.message ?? '').includes(scope));
    if (!error.uncertain && required.length) error.message += ` Meta identified: ${required.join(', ')}.`;
    throw error;
  }
  return data;
}
