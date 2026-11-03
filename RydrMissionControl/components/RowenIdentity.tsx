import RowenStatus from './RowenStatus';
import { CalendarDays, Mail, Plug, Sparkles } from 'lucide-react';
import { Instagram } from './SocialIcons';
import { WorkspaceLink } from './WorkspaceContext';
export function RowenAvatar({className = 'h-20 w-20'}: {className?: string}) {
  return <svg viewBox="0 0 120 120" role="img" aria-label="Rowen, Rydr’s AI marketing assistant" className={className}>
    <rect x="1" y="1" width="118" height="118" rx="36" fill="#fff" fillOpacity=".94"/>
    <path d="M24 110c2-25 18-35 36-35s34 10 36 35" fill="#7333a3"/>
    <path d="m47 82 13 15 13-15" fill="#f7e5ed"/>
    <rect x="27" y="25" width="66" height="57" rx="24" fill="#f4c8b4"/>
    <path d="M27 53V41c0-24 27-31 43-24 14-4 26 7 25 20l-4 15-8-17c-16 9-30 2-35 0-6 11-12 15-21 18" fill="#302640"/>
    <rect x="25" y="47" width="70" height="22" rx="10" fill="#392e49"/>
    <path d="M39 57q5-6 10 0m22 0q5-6 10 0" fill="none" stroke="#b6f2e2" strokeWidth="4" strokeLinecap="round"/>
    <path d="M51 72q9 7 18 0" fill="none" stroke="#a54e5c" strokeWidth="3" strokeLinecap="round"/>
    <circle cx="92" cy="88" r="13" fill="#ee315c"/><path d="m92 80 2.2 5.8L100 88l-5.8 2.2L92 96l-2.2-5.8L84 88l5.8-2.2Z" fill="#fff"/>
  </svg>;
}
export default function RowenIdentity({active, status, subtitle}: {active:'email'|'social'|'connections'|'drafts';status?:string;subtitle?:string}) {
  const links = [{key:'drafts',href:'/campus-growth/drafts',label:'Draft Review',Icon:Mail},{key:'email',href:'/campus-growth/agent',label:'Email outreach',Icon:Mail},{key:'social',href:'/campus-growth/social/workflows',label:'Social workspace',Icon:Instagram},{key:'connections',href:'/campus-growth/social',label:'Connections',Icon:Plug}];
  return <><section className="relative overflow-hidden rounded-3xl bg-gradient-to-br from-rydr-red via-pink-600 to-indigo-600 p-6 text-white shadow-sm sm:p-7">
    <div aria-hidden className="pointer-events-none absolute -right-12 -top-20 h-64 w-64 rounded-full border-[35px] border-white/10"/>
    <div className="relative flex flex-col gap-5 sm:flex-row sm:items-center"><RowenAvatar className="h-24 w-24 shrink-0 drop-shadow-lg"/><div className="flex-1"><p className="flex items-center gap-2 text-xs font-semibold uppercase tracking-[.16em] text-white/80"><Sparkles size={14}/> Your campus connector</p><h2 className="mt-1 text-3xl font-semibold tracking-tight">Meet Rowen.</h2><p className="mt-2 max-w-2xl text-sm text-white/90">{subtitle || 'A thoughtful hello. A useful next step. I help student communities get to know Rydr.'}</p><p className="mt-2 text-xs text-white/75">AI marketing assistant · Rydr Tech LLC · On behalf of Khris Nunnally</p></div><RowenStatus fallback={status}/></div>
  </section><nav aria-label="Rowen workspaces" className="flex flex-wrap gap-2 rounded-2xl border border-line bg-white p-2 shadow-sm">{links.map(({key,href,label,Icon})=><WorkspaceLink key={key} href={href} aria-current={active===key?'page':undefined} className={`flex items-center gap-2 rounded-xl px-4 py-2.5 text-sm font-medium transition ${active===key?'bg-gradient-to-r from-red-50 to-violet-50 text-rydr-burgundy':'text-muted hover:bg-grouped'}`}><Icon size={16}/>{label}</WorkspaceLink>)}</nav></>;
}
