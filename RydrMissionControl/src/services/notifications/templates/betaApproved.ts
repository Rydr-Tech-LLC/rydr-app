import { escapeHtml, genericTemplate, paragraph, primaryButton, type EmailTemplateOutput } from "./genericTemplate";

export interface BetaApprovedTemplateInput {
  firstName?: string;
  role: "rider" | "driver";
  riderTestFlightUrl?: string;
  driverTestFlightUrl?: string;
  discordInviteUrl?: string;
  discordChannelUrl?: string;
}

export function betaApprovedTemplate({
  firstName,
  role,
  riderTestFlightUrl,
  driverTestFlightUrl,
  discordInviteUrl,
  discordChannelUrl
}: BetaApprovedTemplateInput): EmailTemplateOutput {
  const appName = role === "driver" ? "Driver" : "Rider";
  const appUrl = role === "driver" ? driverTestFlightUrl : riderTestFlightUrl;
  const subject = `You’re approved for the Rydr ${appName} Beta`;
  const greeting = firstName?.trim() ? `Hi ${escapeHtml(firstName.trim())},` : "Hi,";
  const buttons = [
    appUrl ? primaryButton(`Download Rydr ${appName}`, appUrl) : "",
    discordInviteUrl ? primaryButton("Join Rydr on Discord", discordInviteUrl) : "",
    discordChannelUrl ? primaryButton("Beta questions & concerns", discordChannelUrl) : ""
  ]
    .filter(Boolean)
    .join("");

  const downloadInstructions = appUrl
    ? paragraph("Use the button below to open TestFlight and install the beta app. If you do not have TestFlight installed yet, your device will prompt you to install it first.")
    : paragraph("Your beta access is approved. We will send the TestFlight download link as soon as it is available.");

  const html = genericTemplate({
    title: subject,
    previewText: "Your Rydr beta access has been approved.",
    children: `
      <h1 style="margin:0 0 18px;color:#151515;font-size:28px;line-height:1.18;font-weight:900;">Welcome to the Rydr ${appName} Beta</h1>
      ${paragraph(greeting)}
      ${paragraph("Congratulations, your Rydr beta access has been approved. Thank you for helping us improve Rydr before the broader launch.")}
      ${downloadInstructions}
      ${buttons ? `<div style="margin:20px 0 12px;">${buttons}</div>` : ""}
      ${paragraph("Use the same phone number you provided on your beta application. For questions, concerns, or bug reports, join our Discord community, then open the beta support channel. Include your app build and steps to reproduce the issue; never post payment details or verification documents.")}
      ${paragraph("The Rydr Team")}
    `
  });

  const textLinks = [
    appUrl ? `${appName} App: ${appUrl}` : "",
    discordInviteUrl ? `Join Discord: ${discordInviteUrl}` : "",
    discordChannelUrl ? `Beta questions & concerns: ${discordChannelUrl}` : ""
  ]
    .filter(Boolean)
    .join("\n");

  return {
    subject,
    html,
    text: `${greeting}

Congratulations, your Rydr beta access has been approved. Thank you for helping us improve Rydr before the broader launch.

${textLinks || "We will send the TestFlight download link as soon as it is available."}

Use the same phone number you provided on your beta application. For questions, concerns, or bug reports, join our Discord community, then open the beta support channel. Include your app build and steps to reproduce the issue; never post payment details or verification documents.

The Rydr Team`
  };
}
