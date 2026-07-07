export interface GenericTemplateInput {
  title: string;
  previewText?: string;
  children: string;
  eyebrow?: string;
}

export interface EmailTemplateOutput {
  subject: string;
  html: string;
  text: string;
}

export function escapeHtml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

const DEFAULT_LOGO_URL = "https://rydr-go.com/assets/rydr-logo.png";

export function genericTemplate({ title, previewText, children, eyebrow }: GenericTemplateInput): string {
  const safePreviewText = previewText ? escapeHtml(previewText) : "";
  const logoUrl = escapeHtml(process.env.EMAIL_LOGO_URL?.trim() || DEFAULT_LOGO_URL);
  const safeEyebrow = eyebrow ? escapeHtml(eyebrow) : "Rydr";

  return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="color-scheme" content="light">
    <meta name="supported-color-schemes" content="light">
    <title>${escapeHtml(title)}</title>
  </head>
  <body style="margin:0;padding:0;background:#f3f4f6;color:#151515;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
    <div style="display:none;max-height:0;overflow:hidden;opacity:0;color:transparent;">${safePreviewText}</div>
    <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="width:100%;background:#f3f4f6;margin:0;padding:0;">
      <tr>
        <td align="center" style="padding:34px 16px;">
          <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="width:100%;max-width:640px;margin:0 auto;">
            <tr>
              <td align="center" style="padding:0 0 18px;">
                <img src="${logoUrl}" width="104" alt="Rydr" style="display:block;width:104px;max-width:104px;height:auto;margin:0 auto 12px;border:0;outline:none;text-decoration:none;">
                <div style="color:#6b7280;font-size:12px;font-weight:800;letter-spacing:1.8px;text-transform:uppercase;">${safeEyebrow}</div>
              </td>
            </tr>
            <tr>
              <td style="height:4px;background:#e11d2e;border-radius:999px 999px 0 0;font-size:0;line-height:0;">&nbsp;</td>
            </tr>
            <tr>
              <td style="background:#ffffff;border-right:1px solid #e5e7eb;border-left:1px solid #e5e7eb;padding:34px 34px 12px;">
                ${children}
              </td>
            </tr>
            <tr>
              <td style="background:#ffffff;border-right:1px solid #e5e7eb;border-left:1px solid #e5e7eb;padding:0 34px 34px;">
                <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="width:100%;border-top:1px solid #ececf1;">
                  <tr>
                    <td style="padding-top:20px;">
                      <p style="margin:0;color:#6b7280;font-size:13px;line-height:1.6;">Rydr Beta Team</p>
                      <p style="margin:3px 0 0;color:#111827;font-size:13px;line-height:1.6;font-weight:800;">Ride Different. Drive Different.</p>
                    </td>
                  </tr>
                </table>
              </td>
            </tr>
            <tr>
              <td style="padding:18px 20px 0;text-align:center;">
                <p style="margin:0;color:#9ca3af;font-size:12px;line-height:1.6;">&copy; Rydr. This message was sent about your Rydr beta request.</p>
              </td>
            </tr>
          </table>
        </td>
      </tr>
    </table>
  </body>
</html>`;
}

export function paragraph(content: string): string {
  return `<p style="margin:0 0 16px;color:#374151;font-size:16px;line-height:1.65;">${content}</p>`;
}

export function primaryButton(label: string, url: string): string {
  return `<a href="${escapeHtml(url)}" style="display:inline-block;margin:10px 10px 0 0;padding:13px 18px;background:#e11d2e;color:#ffffff;text-decoration:none;border-radius:999px;font-size:14px;font-weight:800;">${escapeHtml(label)}</a>`;
}
