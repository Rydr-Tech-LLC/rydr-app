import "server-only";

import { Resend } from "resend";

export interface SendEmailInput {
  to: string | string[];
  subject: string;
  html: string;
  text?: string;
  replyTo?: string | string[];
}

export interface SendEmailSuccess {
  ok: true;
  id: string | null;
}

export interface SendEmailFailure {
  ok: false;
  error: string;
}

export type SendEmailResult = SendEmailSuccess | SendEmailFailure;

export class EmailService {
  private readonly apiKey: string | undefined;
  private readonly fromEmail: string | undefined;
  private resend: Resend | null = null;

  constructor(config: { apiKey?: string; fromEmail?: string } = {}) {
    this.apiKey = config.apiKey ?? process.env.RESEND_API_KEY;
    this.fromEmail = config.fromEmail ?? process.env.WAITLIST_FROM_EMAIL;
  }

  async sendEmail(input: SendEmailInput): Promise<SendEmailResult> {
    if (!this.apiKey) {
      return this.fail("Resend API key is not configured.", input);
    }
    if (!this.fromEmail) {
      return this.fail("Waitlist sender email is not configured.", input);
    }
    if (!hasRecipient(input.to)) {
      return this.fail("Email recipient is missing.", input);
    }

    try {
      const response = await this.client().emails.send({
        from: this.fromEmail,
        to: input.to,
        subject: input.subject,
        html: input.html,
        text: input.text,
        replyTo: input.replyTo
      });

      if (response.error) {
        return this.fail(response.error.message || "Resend rejected the email request.", input);
      }

      const id = response.data?.id ?? null;
      console.info("[EmailService] email_sent", {
        subject: input.subject,
        recipientCount: recipientCount(input.to),
        id
      });

      return { ok: true, id };
    } catch (error) {
      return this.fail(error instanceof Error ? error.message : "Unknown email send failure.", input);
    }
  }

  private client(): Resend {
    if (!this.resend) {
      this.resend = new Resend(this.apiKey);
    }
    return this.resend;
  }

  private fail(message: string, input: Pick<SendEmailInput, "to" | "subject">): SendEmailFailure {
    console.error("[EmailService] email_failed", {
      subject: input.subject,
      recipientCount: recipientCount(input.to),
      error: message
    });
    return { ok: false, error: message };
  }
}

function hasRecipient(to: string | string[]): boolean {
  if (Array.isArray(to)) {
    return to.some((recipient) => recipient.trim().length > 0);
  }
  return to.trim().length > 0;
}

function recipientCount(to: string | string[]): number {
  return Array.isArray(to) ? to.length : 1;
}

export const emailService = new EmailService();
