import { escapeHtml, genericTemplate, paragraph, type EmailTemplateOutput } from "./genericTemplate";

export interface WaitlistConfirmationTemplateInput {
  firstName?: string;
}

export function waitlistConfirmationTemplate({ firstName }: WaitlistConfirmationTemplateInput): EmailTemplateOutput {
  const subject = "You're on the Rydr Beta Waitlist";
  const greeting = firstName?.trim() ? `Hi ${escapeHtml(firstName.trim())},` : "Hi,";

  const html = genericTemplate({
    title: subject,
    eyebrow: "Beta Waitlist",
    previewText: "Your Rydr beta waitlist request has been received.",
    children: `
      <p style="margin:0 0 12px;color:#e11d2e;font-size:12px;line-height:1.4;font-weight:900;letter-spacing:1.7px;text-transform:uppercase;">Request received</p>
      <h1 style="margin:0 0 18px;color:#111827;font-size:30px;line-height:1.18;font-weight:900;">You're on the Rydr Beta Waitlist</h1>
      ${paragraph(greeting)}
      ${paragraph("Thank you for joining the Rydr beta waitlist. We have received your request for the invite-only Atlanta beta.")}
      ${paragraph("Mission Control reviews each request before opening access. If your beta access is approved, we will send a separate email with your next steps.")}
      <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="width:100%;margin:22px 0;border:1px solid #e5e7eb;border-radius:14px;background:#fafafa;">
        <tr>
          <td style="padding:18px 20px;">
            <p style="margin:0 0 6px;color:#111827;font-size:14px;line-height:1.5;font-weight:800;">Current status</p>
            <p style="margin:0;color:#4b5563;font-size:14px;line-height:1.6;">Your request is pending review. No further action is needed right now.</p>
          </td>
        </tr>
      </table>
      ${paragraph("We appreciate your interest in helping shape a safer, more intentional rideshare experience.")}
    `
  });

  return {
    subject,
    html,
    text: `${greeting}

Thank you for joining the Rydr beta waitlist. We are currently preparing for an invite-only beta in Atlanta.

Mission Control reviews each request before opening access. If your beta access is approved, we will send a separate email with your next steps.

Current status: Pending review. No further action is needed right now.

We appreciate your interest in helping shape a safer, more intentional rideshare experience.

The Rydr Team`
  };
}
