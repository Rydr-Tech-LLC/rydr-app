import { getAdminSession } from '@/lib/session';
import SocialWorkspace from './SocialWorkspace';
export default async function Page() {
  if (!await getAdminSession()) return <p>Administrator access is required to manage Rowen’s social workflows.</p>;
  return <SocialWorkspace/>;
}
