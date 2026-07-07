import "server-only";

import { emailService, type EmailService, type SendEmailResult } from "./EmailService";
import { betaApprovedTemplate } from "./templates/betaApproved";
import { escapeHtml, genericTemplate, paragraph } from "./templates/genericTemplate";
import { waitlistConfirmationTemplate } from "./templates/waitlistConfirmation";

export interface NotificationResult {
  ok: boolean;
  providerMessageId?: string | null;
  error?: string;
}

export interface WaitlistConfirmationInput {
  to: string;
  firstName?: string;
}

export interface WaitlistInternalAlertInput {
  applicationId: string;
  firstName: string;
  lastName: string;
  email: string;
  phoneNumber: string;
  role: "rider" | "driver";
  source: string;
  created: boolean;
}

export interface BetaApprovalInput {
  to: string;
  firstName?: string;
}

export interface GenericEmailInput {
  to: string | string[];
  subject: string;
  title?: string;
  body: string;
  text?: string;
}

export class NotificationService {
  constructor(private readonly email: EmailService = emailService) {}

  async sendWaitlistConfirmation(input: WaitlistConfirmationInput): Promise<NotificationResult> {
    const template = waitlistConfirmationTemplate({ firstName: input.firstName });
    return this.toNotificationResult(
      await this.email.sendEmail({
        to: input.to,
        subject: template.subject,
        html: template.html,
        text: template.text
      })
    );
  }

  async sendWaitlistInternalAlert(input: WaitlistInternalAlertInput): Promise<NotificationResult> {
    const recipient = waitlistInternalRecipient();
    if (!recipient) {
      return { ok: false, error: "Waitlist internal notification recipient is not configured." };
    }

    const fullName = `${input.firstName} ${input.lastName}`.trim();
    const action = input.created ? "New" : "Updated";
    const subject = `${action} Rydr beta waitlist signup: ${fullName}`;
    const details = [
      ["Name", fullName],
      ["Email", input.email],
      ["Phone", input.phoneNumber],
      ["Role", input.role],
      ["Source", input.source],
      ["Application ID", input.applicationId]
    ];

    const rows = details
      .map(
        ([label, value]) => `
          <tr>
            <td style="padding:10px 14px;color:#6b7280;font-size:13px;font-weight:800;text-transform:uppercase;border-bottom:1px solid #edf0f4;">${escapeHtml(label)}</td>
            <td style="padding:10px 14px;color:#111827;font-size:15px;border-bottom:1px solid #edf0f4;">${escapeHtml(value)}</td>
          </tr>`
      )
      .join("");

    const html = genericTemplate({
      title: subject,
      previewText: `${fullName} joined the ${input.role} beta waitlist.`,
      eyebrow: "Mission Control",
      children: `
        <h1 style="margin:0 0 18px;color:#151515;font-size:28px;line-height:1.18;font-weight:900;">${escapeHtml(subject)}</h1>
        ${paragraph("A beta waitlist request was submitted from the Rydr website. Review the application in Mission Control before approving access.")}
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="width:100%;border:1px solid #e5e7eb;border-radius:10px;border-collapse:separate;border-spacing:0;overflow:hidden;">
          ${rows}
        </table>
      `
    });

    const text = [
      subject,
      "",
      "A beta waitlist request was submitted from the Rydr website.",
      "",
      ...details.map(([label, value]) => `${label}: ${value}`)
    ].join("\n");

    return this.toNotificationResult(
      await this.email.sendEmail({
        to: recipient,
        subject,
        html,
        text,
        replyTo: input.email
      })
    );
  }

  async sendBetaApproval(input: BetaApprovalInput): Promise<NotificationResult> {
    const template = betaApprovedTemplate({
      firstName: input.firstName,
      riderTestFlightUrl: optionalEnv("TESTFLIGHT_RIDER_URL"),
      driverTestFlightUrl: optionalEnv("TESTFLIGHT_DRIVER_URL"),
      discordInviteUrl: optionalEnv("DISCORD_INVITE_URL")
    });

    return this.toNotificationResult(
      await this.email.sendEmail({
        to: input.to,
        subject: template.subject,
        html: template.html,
        text: template.text
      })
    );
  }

  async sendGenericEmail(input: GenericEmailInput): Promise<NotificationResult> {
    const html = genericTemplate({
      title: input.title ?? input.subject,
      previewText: input.subject,
      children: `
        <h1 style="margin:0 0 18px;color:#151515;font-size:28px;line-height:1.18;font-weight:900;">${escapeHtml(input.title ?? input.subject)}</h1>
        ${paragraph(escapeHtml(input.body))}
      `
    });

    return this.toNotificationResult(
      await this.email.sendEmail({
        to: input.to,
        subject: input.subject,
        html,
        text: input.text ?? input.body
      })
    );
  }

  private toNotificationResult(result: SendEmailResult): NotificationResult {
    if (result.ok) {
      return { ok: true, providerMessageId: result.id };
    }
    return { ok: false, error: result.error };
  }
}

function optionalEnv(name: "TESTFLIGHT_RIDER_URL" | "TESTFLIGHT_DRIVER_URL" | "DISCORD_INVITE_URL"): string | undefined {
  const value = process.env[name]?.trim();
  return value ? value : undefined;
}

function waitlistInternalRecipient(): string {
  return process.env.WAITLIST_INTERNAL_NOTIFY_EMAIL?.trim() || "support@rydr-go.com";
}

export const notificationService = new NotificationService();
