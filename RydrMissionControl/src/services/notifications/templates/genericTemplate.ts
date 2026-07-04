export interface GenericTemplateInput {
  title: string;
  previewText?: string;
  children: string;
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

export function genericTemplate({ title, previewText, children }: GenericTemplateInput): string {
  const safePreviewText = previewText ? escapeHtml(previewText) : "";

  return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="color-scheme" content="light">
    <meta name="supported-color-schemes" content="light">
    <title>${escapeHtml(title)}</title>
  </head>
  <body style="margin:0;padding:0;background:#f5f5f7;color:#151515;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
    <div style="display:none;max-height:0;overflow:hidden;opacity:0;color:transparent;">${safePreviewText}</div>
    <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="width:100%;background:#f5f5f7;margin:0;padding:0;">
      <tr>
        <td align="center" style="padding:32px 16px;">
          <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="width:100%;max-width:620px;background:#ffffff;border-radius:22px;overflow:hidden;border:1px solid #ececf1;">
            <tr>
              <td style="padding:28px 30px 20px;border-top:5px solid #e11d2e;">
                <div style="font-size:28px;line-height:1;font-weight:900;letter-spacing:0;color:#151515;">Rydr</div>
                <div style="margin-top:6px;color:#e11d2e;font-size:14px;font-weight:700;">Ride Different.</div>
              </td>
            </tr>
            <tr>
              <td style="padding:4px 30px 30px;">
                ${children}
              </td>
            </tr>
            <tr>
              <td style="padding:22px 30px;background:#fafafa;border-top:1px solid #ececf1;">
                <p style="margin:0;color:#6b7280;font-size:13px;line-height:1.6;">Ride Different.</p>
                <p style="margin:3px 0 0;color:#9ca3af;font-size:12px;line-height:1.6;">&copy; Rydr</p>
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
