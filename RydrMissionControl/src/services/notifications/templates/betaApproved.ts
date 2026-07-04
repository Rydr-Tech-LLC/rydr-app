import { escapeHtml, genericTemplate, paragraph, primaryButton, type EmailTemplateOutput } from "./genericTemplate";

export interface BetaApprovedTemplateInput {
  firstName?: string;
  riderTestFlightUrl?: string;
  driverTestFlightUrl?: string;
  discordInviteUrl?: string;
}

export function betaApprovedTemplate({
  firstName,
  riderTestFlightUrl,
  driverTestFlightUrl,
  discordInviteUrl
}: BetaApprovedTemplateInput): EmailTemplateOutput {
  const subject = "Welcome to the Rydr Beta";
  const greeting = firstName?.trim() ? `Hi ${escapeHtml(firstName.trim())},` : "Hi,";
  const buttons = [
    riderTestFlightUrl ? primaryButton("Download Rider App", riderTestFlightUrl) : "",
    driverTestFlightUrl ? primaryButton("Download Driver App", driverTestFlightUrl) : "",
    discordInviteUrl ? primaryButton("Join our Beta Community", discordInviteUrl) : ""
  ]
    .filter(Boolean)
    .join("");

  const downloadInstructions = buttons
    ? paragraph("Use the button below to open TestFlight and install the beta app. If you do not have TestFlight installed yet, your device will prompt you to install it first.")
    : paragraph("Your beta access is approved. We will send the TestFlight download link as soon as it is available.");

  const html = genericTemplate({
    title: subject,
    previewText: "Your Rydr beta access has been approved.",
    children: `
      <h1 style="margin:0 0 18px;color:#151515;font-size:28px;line-height:1.18;font-weight:900;">Welcome to the Rydr Beta</h1>
      ${paragraph(greeting)}
      ${paragraph("Congratulations, your Rydr beta access has been approved. Thank you for helping us improve Rydr before the broader launch.")}
      ${downloadInstructions}
      ${buttons ? `<div style="margin:20px 0 12px;">${buttons}</div>` : ""}
      ${paragraph("Please use the beta carefully and share any issues through the beta support channels so the team can review them quickly.")}
      ${paragraph("The Rydr Team")}
    `
  });

  const textLinks = [
    riderTestFlightUrl ? `Rider App: ${riderTestFlightUrl}` : "",
    driverTestFlightUrl ? `Driver App: ${driverTestFlightUrl}` : "",
    discordInviteUrl ? `Beta Community: ${discordInviteUrl}` : ""
  ]
    .filter(Boolean)
    .join("\n");

  return {
    subject,
    html,
    text: `${greeting}

Congratulations, your Rydr beta access has been approved. Thank you for helping us improve Rydr before the broader launch.

${textLinks || "We will send the TestFlight download link as soon as it is available."}

Please use the beta carefully and share any issues through the beta support channels so the team can review them quickly.

The Rydr Team`
  };
}
