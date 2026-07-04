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

export const notificationService = new NotificationService();
