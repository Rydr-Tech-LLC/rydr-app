import { escapeHtml, genericTemplate, paragraph, type EmailTemplateOutput } from "./genericTemplate";

export interface WaitlistConfirmationTemplateInput {
  firstName?: string;
}

export function waitlistConfirmationTemplate({ firstName }: WaitlistConfirmationTemplateInput): EmailTemplateOutput {
  const subject = "You're on the Rydr Beta Waitlist";
  const greeting = firstName?.trim() ? `Hi ${escapeHtml(firstName.trim())},` : "Hi,";

  const html = genericTemplate({
    title: subject,
    previewText: "Thanks for joining the Rydr beta waitlist.",
    children: `
      <h1 style="margin:0 0 18px;color:#151515;font-size:28px;line-height:1.18;font-weight:900;">You're on the Rydr Beta Waitlist</h1>
      ${paragraph(greeting)}
      ${paragraph("Thank you for joining the Rydr beta waitlist. We are currently preparing for an invite-only beta in Atlanta.")}
      ${paragraph("You will receive another email once your beta access is approved. No further action is needed right now.")}
      ${paragraph("We appreciate your interest in helping shape a safer, more intentional rideshare experience.")}
      ${paragraph("The Rydr Team")}
    `
  });

  return {
    subject,
    html,
    text: `${greeting}

Thank you for joining the Rydr beta waitlist. We are currently preparing for an invite-only beta in Atlanta.

You will receive another email once your beta access is approved. No further action is needed right now.

We appreciate your interest in helping shape a safer, more intentional rideshare experience.

The Rydr Team`
  };
}
