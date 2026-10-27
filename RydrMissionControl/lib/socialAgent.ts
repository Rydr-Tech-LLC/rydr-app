import 'server-only';
import { createHash, randomUUID } from 'node:crypto';
import { getWorkspaceDb } from './firebaseAdmin';
import { currentWorkspace } from './workspace';
import { socialCopy } from './ai/socialCopy';
import { socialConnection, socialGraph, MetaRequestError } from './socialMeta';
import { cleanCaption, easternDay, metricValue, needsHuman, normalizeSocialConfig, optedOut, publicMediaUrl, replyWindow, socialOpen, withinSendingHours, type SocialConfig } from './socialPolicy';
import { localTimeToISO } from '../../rydr-backend/services/stripe/promotionPolicy';

type Actor = { uid: string; email: string | null };
const hash = (value: string) => createHash('sha256').update(value).digest('hex');
const id = (value: unknown) => { const s = String(value); if (!/^[\w-]{1,128}$/.test(s)) throw new Error('Invalid item ID.'); return s; };
async function refs() { const db = await getWorkspaceDb(), root = db.collection('socialAgent').doc('rowen'); return { db, root, posts: root.collection('posts'), threads: root.collection('threads'), events: root.collection('events') }; }
async function event(kind: string, detail: string, itemId = '') { const { events } = await refs(); await events.add({ kind, detail: detail.slice(0,500), itemId, at: Date.now() }); }
export async function socialSnapshot() {
  const { root, posts, threads, events } = await refs();
  const [saved, queue, inbox, activity, metrics, day] = await Promise.all([root.get(), posts.orderBy('createdAt','desc').limit(100).get(), threads.orderBy('lastInboundAt','desc').limit(100).get(), events.orderBy('at','desc').limit(100).get(), root.collection('metrics').doc('latest').get(), root.collection('days').doc(easternDay()).get()]);
  const data = saved.data();
  const config = data?.config ?? { active: false, facts: '', endsAt: Date.parse('2026-11-01T04:00:00Z'), autoReplies: false, dailyPosts: 2, dailyReplies: 30 };
  return { config, posts: queue.docs.map(d => ({ id: d.id, ...d.data() })), threads: inbox.docs.map(d => ({ id: d.id, ...d.data() })),
    events: activity.docs.map(d => ({ id: d.id, ...d.data() })), metrics: metrics.data() ?? null, today: day.data() ?? {},
    onShift: withinSendingHours(), shiftDay: easternDay(), status: !config.active ? 'Paused' : Date.now() >= config.endsAt ? 'Campaign ended' : !withinSendingHours() ? 'Off shift' : data?.leaseUntil > Date.now() ? 'Working' : 'Ready for next run',
    lastRunAt: data?.lastRunAt ?? null, lastError: data?.lastError ?? '', schedulerLastSeen: data?.schedulerLastSeen ?? null,
    aiReady: Boolean(process.env.OPENAI_API_KEY), webhookReady: data?.webhookReady ?? false, webhookError: data?.webhookError ?? '',
    schedulerCredential: Boolean(process.env.SOCIAL_AGENT_RUN_SECRET || process.env.MARKETING_AGENT_RUN_SECRET) };
}
export async function socialMessages(threadId: string) {
  const { threads } = await refs();
  const snap = await threads.doc(id(threadId)).collection('messages').orderBy('at','desc').limit(50).get();
  return snap.docs.map(d => ({ id: d.id, ...d.data() })).reverse();
}
export async function saveSocialConfig(input: Record<string,unknown>, actor: Actor) {
  const config = normalizeSocialConfig({ ...input, endsAt: Date.parse(localTimeToISO(String(input.endsLocal))) });
  const { root } = await refs(); await root.set({ config, updatedAt: Date.now(), updatedBy: actor.uid }, { merge: true });
  await event('settings', config.active ? 'Social workflows activated with the saved brief and shift limits.' : 'Social workflows paused.');
}
export async function pauseSocial() { const { root } = await refs(); await root.set({ config: { active: false } }, { merge: true }); await event('settings','Rowen paused. Queued work remains saved.'); }
export async function draftSocialPost(topic: string) {
  const { root } = await refs(); const config = (await root.get()).data()?.config;
  if (!config?.facts) throw new Error('Save the approved social brief first.');
  const draft = await socialCopy(config.facts,'post',String(topic).slice(0,2000));
  await event('draft','Rowen prepared a caption and visual brief.'); return draft;
}
export async function saveSocialPost(input: Record<string,unknown>, actor: Actor) {
  const { db, root, posts } = await refs(), operation = id(input.operationId);
  const config = (await root.get()).data()?.config;
  const caption = cleanCaption(input.caption), mediaUrl = publicMediaUrl(input.mediaUrl);
  const mediaType = input.mediaType === 'reel' ? 'reel' : 'image';
  const scheduled = input.schedule === true;
  const dueAt = scheduled ? Date.parse(localTimeToISO(String(input.scheduledLocal))) : null;
  if (scheduled && (!config || !dueAt || dueAt < Date.now() || dueAt >= config.endsAt || !withinSendingHours(new Date(dueAt)))) throw new Error('Schedule during a future weekday 9–5 Eastern shift, before the campaign ends.');
  const content = { caption, mediaUrl, mediaType, aiGenerated: input.aiGenerated === true, dueAt, state: scheduled ? 'queued' : 'draft' };
  const fingerprint = hash(JSON.stringify(content));
  const ref = posts.doc(hash(`${actor.uid}:${operation}`));
  await db.runTransaction(async tx => {
    const prior = (await tx.get(ref)).data();
    if (prior) { if (prior.fingerprint !== fingerprint) throw new Error('This save already completed with different content. Refresh before creating another post.'); return; }
    tx.create(ref, { ...content, fingerprint, createdAt: Date.now(), createdBy: actor.uid, updatedAt: Date.now() });
  });
  return { id: ref.id };
}
export async function changeSocialPost(input: Record<string,unknown>) {
  const { db, root, posts } = await refs(), ref = posts.doc(id(input.id));
  await db.runTransaction(async tx => {
    const [snap, cfg] = await Promise.all([tx.get(ref),tx.get(root)]); const post = snap.data(), config = cfg.data()?.config;
    if (!post) throw new Error('Post not found.');
    if (input.action === 'cancel') {
      if (!['draft','queued','failed'].includes(post.state)) throw new Error('This post cannot be cancelled after publishing starts.');
      tx.update(ref,{state:'cancelled',updatedAt:Date.now()}); return;
    }
    if (input.action === 'resolve') {
      if (!['unknown','processing'].includes(post.state) || (post.state === 'processing' && post.processingAt > Date.now()-600000)) throw new Error('Only an uncertain or abandoned publish can be resolved.');
      tx.update(ref,{state:'resolved',resolution:String(input.resolution ?? '').slice(0,500) || 'Checked manually in Instagram; no automatic retry.',updatedAt:Date.now()}); return;
    }
    if (post.state !== 'draft') throw new Error('Only drafts can be scheduled.');
    const dueAt = Date.parse(localTimeToISO(String(input.scheduledLocal)));
    if (!config || dueAt < Date.now() || dueAt >= config.endsAt || !withinSendingHours(new Date(dueAt))) throw new Error('Choose a future weekday 9–5 Eastern time before the campaign ends.');
    tx.update(ref,{state:'queued',dueAt,updatedAt:Date.now()});
  });
}

// Called only after the route has verified Meta's raw-body signature.
export async function ingestSocialWebhook(payload: any) {
  if (payload?.object !== 'instagram' || !Array.isArray(payload.entry)) return;
  const { db, root, threads } = await refs();
  const connected = (await db.collection('metaConnections').doc('rydr').get()).data();
  if (!connected?.instagramId) return;
  for (const entry of payload.entry.slice(0,100)) {
    if (String(entry?.id) !== String(connected.instagramId)) continue;
    for (const item of (Array.isArray(entry.messaging) ? entry.messaging : []).slice(0,100)) {
      const sender = String(item?.sender?.id ?? ''), message = item?.message;
      if (!/^\d+$/.test(sender) || sender === String(connected.instagramId) || !message?.mid || message.is_echo || String(item?.recipient?.id) !== String(connected.instagramId)) continue;
      const at = Number(item.timestamp), now = Date.now();
      if (!Number.isFinite(at) || at <= 0 || at > now + 60000) continue;
      const text = typeof message.text === 'string' ? message.text.slice(0,4000) : '[Attachment — review in Instagram]';
      const ref = threads.doc(hash(sender)), mid = hash(String(message.mid)), msg = ref.collection('messages').doc(mid);
      await db.runTransaction(async tx => {
        const [prior, existing] = await Promise.all([tx.get(ref),tx.get(msg)]); const old = prior.data();
        if (message.is_deleted) { if (existing.exists) tx.update(msg,{text:'[Deleted on Instagram]',deleted:true}); if (old?.lastInboundId === mid) tx.update(ref,{text:'[Deleted on Instagram]',state:'human',draft:'',lastInboundAt:old.lastInboundAt}); return; }
        if (existing.exists) return;
        tx.create(msg,{direction:'inbound',text,at,providerId:String(message.mid).slice(0,500)});
        const blocked = Boolean(old?.blocked || optedOut(text));
        if (old && at < old.lastInboundAt && blocked) tx.update(ref,{blocked:true,human:true,state:'human',draft:'',reason:'Opted out; no automated replies.'});
        if (!old || at >= old.lastInboundAt) tx.set(ref,{senderId:sender,text,lastInboundAt:Math.min(at,now),lastInboundId:mid,blocked,
          state: blocked || old?.human || needsHuman(text) || !message.text ? 'human' : 'pending', human:Boolean(old?.human || needsHuman(text) || !message.text),
          draft:'',reason:blocked ? 'Opted out; no automated replies.' : needsHuman(text) || !message.text ? 'Needs Khris’s attention.' : '', updatedAt:now },{merge:true});
      });
    }
  }
  await root.set({lastInboundWebhookAt:Date.now()},{merge:true});
}
export async function reviewSocialReply(input: Record<string,unknown>, actor: Actor) {
  const { db, threads } = await refs(), ref = threads.doc(id(input.id));
  await db.runTransaction(async tx => {
    const thread = (await tx.get(ref)).data(); if (!thread) throw new Error('Conversation not found.');
    if (input.action === 'handoff') { tx.update(ref,{human:true,state:'human',draft:'',reason:'Assigned to Khris.',updatedAt:Date.now()}); return; }
    if (input.action === 'resolveReply') {
      if (!['unknown','processing'].includes(thread.state) || (thread.state === 'processing' && thread.processingAt > Date.now()-600000)) throw new Error('Only uncertain or abandoned sends can be resolved.');
      tx.update(ref,{state:'human',human:true,reason:'Send checked manually; automation remains paused for this conversation.',updatedAt:Date.now()}); return;
    }
    if (thread.blocked || !replyWindow(thread.lastInboundAt)) throw new Error('The reply window is closed or this person opted out.');
    if (['processing','unknown'].includes(thread.state)) throw new Error('Resolve the existing send before replying again.');
    if (String(input.lastInboundId) !== thread.lastInboundId) throw new Error('A newer message arrived. Refresh the conversation before replying.');
    const draft = cleanCaption(input.text); if (draft.length > 1000) throw new Error('Replies must be under 1,000 characters.');
    tx.update(ref,{draft,state:'ready',approvedBy:actor.uid,draftFor:thread.lastInboundId,updatedAt:Date.now()});
  });
}
export async function subscribeSocialInbox() {
  const { root } = await refs(); const { pageId } = await socialConnection();
  try { await socialGraph(`${pageId}/subscribed_apps`,{subscribed_fields:'messages,messaging_postbacks'},'POST'); await root.set({webhookReady:true,webhookError:''},{merge:true}); }
  catch (error) { await root.set({webhookReady:false,webhookError:(error as Error).message},{merge:true}); throw error; }
}

export async function syncSocialAnalytics() {
  const { root, posts } = await refs(); const { instagramId } = await socialConnection();
  const previous = (await root.collection('metrics').doc('latest').get()).data();
  if (previous?.syncedAt > Date.now()-300000) return previous;
  const profile = await socialGraph(instagramId,{fields:'id,username,followers_count,media_count'});
  const until = Math.floor(Date.now()/1000), since = until - 7*86400;
  const metrics: Record<string, number | null> = {}, errors: string[] = [];
  for (const name of ['reach','views']) {
    try { metrics[name] = metricValue(await socialGraph(`${instagramId}/insights`,{metric:name,period:'day',metric_type:'total_value',since,until}),name); }
    catch { metrics[name] = null; errors.push(`${name} is unavailable for this account or permission set.`); }
  }
  const data = { username:profile.username, followers: typeof profile.followers_count === 'number' ? profile.followers_count : null,
    mediaCount: typeof profile.media_count === 'number' ? profile.media_count : null, ...metrics, since:since*1000, until:until*1000, syncedAt:Date.now(), errors };
  await root.collection('metrics').doc('latest').set(data);
  await root.collection('metricsHistory').doc(easternDay()).set(data);
  const published = await posts.where('state','==','published').limit(30).get();
  const recent = published.docs.sort((a,b) => (a.data().insightsAt ?? 0)-(b.data().insightsAt ?? 0)).slice(0,3);
  for (const post of recent) {
    if (post.data().insightsAt > Date.now()-3600000) continue;
    try {
      const details = await socialGraph(post.data().mediaId,{fields:'permalink,like_count,comments_count'});
      const reach = await socialGraph(`${post.data().mediaId}/insights`,{metric:'reach'});
      await post.ref.update({insights:{likes:details.like_count ?? null,comments:details.comments_count ?? null,reach:metricValue(reach,'reach')},permalink:details.permalink ?? null,insightsAt:Date.now(),insightsError:''});
    } catch { await post.ref.update({insightsError:'Post insights unavailable. The published post is unchanged.'}); }
  }
  await event('analytics','Updated Instagram account and available post insights.'); return data;
}

async function reserve(kind: 'posts' | 'replies', runId: string, item: FirebaseFirestore.DocumentReference) {
  const { db, root } = await refs(), day = root.collection('days').doc(easternDay());
  return db.runTransaction(async tx => {
    const [cfg, tally, saved] = await Promise.all([tx.get(root),tx.get(day),tx.get(item)]), data = cfg.data(), counts = tally.data() ?? {};
    if (!socialOpen(data?.config) || data?.leaseId !== runId || data?.leaseUntil < Date.now()) return false;
    if (saved.data()?.reservedDay === easternDay() && (kind === 'posts' || saved.data()?.reservedFor === saved.data()?.lastInboundId)) return true;
    const cap = kind === 'posts' ? data.config.dailyPosts : data.config.dailyReplies;
    if ((counts[`${kind}Reserved`] ?? 0) >= cap) return false;
    tx.set(day,{[`${kind}Reserved`]:(counts[`${kind}Reserved`] ?? 0)+1},{merge:true}); tx.update(item,{reservedDay:easternDay(),reservedFor:kind==='replies'?saved.data()?.lastInboundId:'post'}); return true;
  });
}
async function tally(kind: string) { const { db, root } = await refs(), ref = root.collection('days').doc(easternDay()); await db.runTransaction(async tx => { const data = (await tx.get(ref)).data(); tx.set(ref,{[kind]:(data?.[kind] ?? 0)+1},{merge:true}); }); }
async function stillOpen(runId: string) { const { root } = await refs(); const data = (await root.get()).data(); return socialOpen(data?.config) && data?.leaseId === runId && data?.leaseUntil > Date.now(); }
async function publishPost(ref: FirebaseFirestore.DocumentReference, runId: string, test: boolean) {
  const { db } = await refs();
  const claimed = await db.runTransaction(async tx => { const p = (await tx.get(ref)).data(); if (p?.state !== 'queued' || p.dueAt > Date.now()) return null; tx.update(ref,{state:'processing',processingAt:Date.now()}); return p; });
  if (!claimed) return;
  let attempted = false;
  try {
    if (!await reserve('posts',runId,ref)) { await ref.update({state:'queued'}); return; }
    if (test) { await ref.update({state:'simulated',updatedAt:Date.now()}); await tally('simulated'); return; }
    const { instagramId } = await socialConnection();
    const container = claimed.containerId ? {id:claimed.containerId} : await socialGraph(`${instagramId}/media`,{caption:claimed.caption,
      ...(claimed.mediaType === 'reel' ? {media_type:'REELS',video_url:claimed.mediaUrl} : {image_url:claimed.mediaUrl}), is_ai_generated:claimed.aiGenerated},'POST');
    if (!/^\d+$/.test(String(container.id))) throw new Error('Meta returned no container ID.');
    await ref.update({containerId:container.id});
    const status = await socialGraph(container.id,{fields:'status_code'});
    if (status.status_code === 'IN_PROGRESS') { await ref.update({state:'queued',dueAt:Date.now()+60000,updatedAt:Date.now()}); return; }
    if (status.status_code !== 'FINISHED') throw new Error(`Media container is ${status.status_code || 'unavailable'}. Review the media before creating another post.`);
    if (!await stillOpen(runId)) { await ref.update({state:'queued'}); return; }
    // Once this request starts, never automatically retry an uncertain publish.
    attempted = true;
    const result = await socialGraph(`${instagramId}/media_publish`,{creation_id:container.id},'POST');
    if (!result.id) throw new Error('Meta returned no published media ID.');
    await ref.update({state:'published',mediaId:result.id,publishedAt:Date.now(),updatedAt:Date.now()});
    await tally('posts'); await event('published','Published scheduled Instagram content.',ref.id);
  } catch (error) {
    const uncertain = attempted && (!(error instanceof MetaRequestError) || error.uncertain);
    // An acknowledged publication is never downgraded by a failed analytics/event write.
    if ((await ref.get()).data()?.state !== 'published') await ref.update({state:uncertain?'unknown':'failed',error:(error as Error).message,updatedAt:Date.now()});
    await event('error',(error as Error).message,ref.id);
  }
}
async function processReply(ref: FirebaseFirestore.DocumentReference, runId: string, test: boolean) {
  const { db, root } = await refs();
  let thread = (await ref.get()).data(); if (!thread || !['pending','ready'].includes(thread.state)) return;
  if (thread.blocked || !replyWindow(thread.lastInboundAt)) { await ref.update({state:'human',human:true,reason:'Reply window closed or opted out.'}); return; }
  const config = (await root.get()).data()?.config as SocialConfig;
  if (thread.state === 'pending') {
    if (thread.human) return;
    const copy = await socialCopy(config.facts,'reply',thread.text);
    const updated = await db.runTransaction(async tx => {
      const fresh = (await tx.get(ref)).data(); if (fresh?.state !== 'pending' || fresh.lastInboundId !== thread!.lastInboundId) return false;
      tx.update(ref,{draft:copy.text,draftFor:fresh.lastInboundId,state:copy.handoff?'human':config.autoReplies?'ready':'review',human:copy.handoff,reason:copy.reason}); return true;
    });
    if (!updated || copy.handoff || !config.autoReplies) return;
    thread = (await ref.get()).data()!; await tally('drafts');
  }
  const claimed = await db.runTransaction(async tx => {
    const fresh = (await tx.get(ref)).data();
    if (fresh?.state !== 'ready' || fresh.blocked || fresh.draftFor !== fresh.lastInboundId || !replyWindow(fresh.lastInboundAt)) return null;
    tx.update(ref,{state:'processing',processingAt:Date.now()}); return fresh;
  });
  if (!claimed) return;
  let attempted = false;
  try {
    if (!await reserve('replies',runId,ref)) { await ref.update({state:'ready'}); return; }
    const fresh = (await ref.get()).data();
    if (!await stillOpen(runId) || fresh?.state !== 'processing' || fresh.lastInboundId !== claimed.lastInboundId || fresh.blocked || !replyWindow(fresh.lastInboundAt)) {
      await db.runTransaction(async tx => { const latest = (await tx.get(ref)).data(); if (latest?.state === 'processing' && latest.lastInboundId === claimed.lastInboundId) tx.update(ref,{state:replyWindow(latest.lastInboundAt)?'ready':'human'}); }); return;
    }
    if (test) { await ref.update({state:'simulated'}); await tally('simulated'); return; }
    const { pageId } = await socialConnection(); attempted = true;
    const response = await socialGraph(`${pageId}/messages`,{recipient:{id:claimed.senderId},message:{text:claimed.draft},messaging_type:'RESPONSE'},'POST');
    if (!response.message_id) throw new Error('Meta returned no reply ID.');
    await ref.collection('messages').doc(hash(response.message_id)).set({direction:'outbound',text:claimed.draft,providerId:response.message_id,at:Date.now()});
    await db.runTransaction(async tx => { const latest = (await tx.get(ref)).data(); if (latest?.lastInboundId === claimed.lastInboundId) tx.update(ref,{state:'replied',repliedAt:Date.now(),draft:''}); });
    await tally('replies'); await event('reply','Replied to an incoming Instagram conversation.',ref.id);
  } catch (error) {
    const uncertain = attempted && (!(error instanceof MetaRequestError) || error.uncertain);
    // Keep a newer inbound message, but stop automation until this send is reconciled.
    await ref.update({state:uncertain?'unknown':'human',human:true,reason:(error as Error).message});
    await event('error',(error as Error).message,ref.id);
  }
}
export async function runSocialAgent(scheduled = false) {
  const { db, root, posts, threads } = await refs(), runId = randomUUID(), started = Date.now(), test = await currentWorkspace() === 'test';
  if (scheduled) await root.set({schedulerLastSeen:started},{merge:true});
  const acquired = await db.runTransaction(async tx => {
    const data = (await tx.get(root)).data(); if (!socialOpen(data?.config) || data?.leaseUntil > started) return false;
    tx.set(root,{leaseId:runId,leaseUntil:started+600000,lastRunAt:started,lastError:''},{merge:true}); return true;
  });
  if (!acquired) return {skipped:true,reason:'Paused, off shift, outside campaign dates, or another run is active.'};
  try {
    await event('run','Rowen started a social shift batch.');
    // Recover abandoned claims as unknown, never by sending again.
    for (const collection of [posts,threads]) {
      const stale = await collection.where('state','==','processing').limit(100).get();
      for (const doc of stale.docs) if (doc.data().processingAt < started-600000) await doc.ref.update({state:'unknown',reason:'A previous run stopped during a send. Check Instagram before resolving.'});
    }
    const queue = await posts.where('state','==','queued').limit(100).get();
    for (const post of queue.docs.sort((a,b)=>a.data().dueAt-b.data().dueAt).slice(0,2)) if (await stillOpen(runId)) await publishPost(post.ref,runId,test);
    const inbox = await threads.where('state','in',['pending','ready']).limit(50).get();
    for (const thread of inbox.docs.sort((a,b)=>a.data().lastInboundAt-b.data().lastInboundAt).slice(0,3)) if (Date.now()-started<150000 && await stillOpen(runId)) await processReply(thread.ref,runId,test);
    const metrics = (await root.collection('metrics').doc('latest').get()).data();
    if (!test && Date.now()-started<150000 && await stillOpen(runId) && (!metrics?.syncedAt || metrics.syncedAt < started-3600000)) await syncSocialAnalytics();
    await event('run','Shift batch complete. Waiting for the next scheduled check.');
    return {ok:true};
  } catch(error) { await root.set({lastError:(error as Error).message},{merge:true}); await event('error',(error as Error).message); return {error:(error as Error).message}; }
  finally { await db.runTransaction(async tx => { const data = (await tx.get(root)).data(); if (data?.leaseId === runId) tx.update(root,{leaseUntil:0}); }); }
}
