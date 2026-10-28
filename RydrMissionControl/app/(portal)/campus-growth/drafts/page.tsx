import RowenIdentity from '@/components/RowenIdentity';
import { WorkspaceLink } from '@/components/WorkspaceContext';
import { agentSnapshot } from '@/lib/marketingAgent';
import { socialSnapshot } from '@/lib/socialAgent';
import { getAdminSession } from '@/lib/session';
import { redirect } from 'next/navigation';

export const dynamic = 'force-dynamic';
const panel = 'rounded-2xl border border-line bg-white p-5 shadow-sm';
type Item = { id: string; title: string; text: string; state: string; href: string; recipient?: string };
export default async function DraftReviewPage() {
  if (!await getAdminSession()) redirect('/login');
  const [email, social] = await Promise.all([agentSnapshot(), socialSnapshot()]);
  const contacts = email.leads as any[], posts = social.posts as any[], threads = social.threads as any[];
  const groups: { title: string; empty: string; items: Item[] }[] = [
    { title: 'Email outreach', empty: 'No email drafts awaiting review or sending. Automatic outreach sends eligible drafts during the shift; sent copies remain under Marketing Agent.', items: contacts.filter(l => l.body && ['review','ready'].includes(l.state)).map(l => ({id:l.id,title:l.subject || l.name,text:l.emailBody || l.body,state:l.state === 'review'?'Needs approval':'Queued for automatic sending',recipient:`${l.name} · ${l.email}`,href:`/campus-growth/agent#contact-${l.id}`})) },
    { title: 'Instagram introductions', empty: 'No saved first-contact Instagram drafts. These are generated alongside eligible email contacts; a separate social-only prospect queue is not yet implemented. Facebook first-contact drafts are not currently generated.', items: contacts.filter(l => l.instagramDraft && ['review','ready'].includes(l.state)).map(l => ({id:l.id,title:l.name,text:l.instagramDraft,state:'Manual first contact',recipient:l.instagramUrl || 'No verified Instagram account linked',href:`/campus-growth/agent#contact-${l.id}`})) },
    { title: 'Instagram & Facebook posts', empty: 'No saved post drafts or queued posts. Published posts remain in Social Workspace → Content queue.', items: posts.filter(p => ['draft','queued'].includes(p.state)).map(p => ({id:p.id,title:p.facebookTarget?'Instagram + Facebook post':'Instagram post',text:p.caption,state:p.state==='draft'?'Draft — not scheduled':'Scheduled for automatic publishing',href:'/campus-growth/social/workflows'})) },
    { title: 'Instagram replies', empty: 'No reply drafts awaiting review or sending.', items: threads.filter(t => t.draft && ['review','human','ready'].includes(t.state)).map(t => ({id:t.id,title:'Conversation reply',text:t.draft,state:t.state==='ready'?'Queued for automatic sending':'Needs human review',href:'/campus-growth/social/workflows?tab=inbox'})) },
  ];
  return <div className="space-y-5"><div><h1 className="text-2xl font-semibold text-ink">Rowen’s Draft Review</h1><p className="mt-2 text-sm text-muted">Saved drafts across email and social. Opening this page does not pause automatic sending.</p></div><RowenIdentity active="drafts"/>
    <div className={panel}><p className="text-sm text-muted">This page shows saved drafts, not proposed messages or unsaved text in the content editor. Refresh the page for the latest state. Review controls remain beside each original conversation or post.</p><WorkspaceLink href="/campus-growth/outreach" className="mt-2 inline-block text-sm text-rydr-burgundy underline">Open separately created Outreach Inbox drafts</WorkspaceLink></div>
    {groups.map(group => <section key={group.title} className="space-y-3"><h2 className="text-lg font-semibold">{group.title} <span className="text-sm text-muted">({group.items.length})</span></h2>{!group.items.length?<p className={`${panel} text-sm text-muted`}>{group.empty}</p>:group.items.map(item => <article key={item.id} className={panel}><div className="flex flex-wrap justify-between gap-2"><h3 className="font-semibold">{item.title}</h3><span className="rounded-full bg-grouped px-3 py-1 text-xs">{item.state}</span></div>{item.recipient&&<p className="mt-2 break-words text-xs text-muted">{item.recipient}</p>}<p className="mt-4 whitespace-pre-wrap break-words text-sm">{item.text}</p><WorkspaceLink href={item.href} className="mt-4 inline-block text-sm font-semibold text-rydr-burgundy underline">Open review controls</WorkspaceLink></article>)}</section>)}
  </div>;
}
