export const DEFAULT_VEHICLE_BACKGROUND_PROMPT = "Remove the existing background and place the vehicle on a clean, pure white studio background with a subtle natural ground shadow.";
export function buildVehicleEditPrompt(instruction: string) {
  return `Edit only the background of this vehicle photograph. Preserve the exact vehicle: exterior color, make/model styling, trim, wheels, proportions, viewing angle, windows, badges and all visible vehicle details. Keep the whole vehicle visible. Do not recolor, redesign, replace or add vehicles. Do not add text. Background instructions: ${instruction.trim() || DEFAULT_VEHICLE_BACKGROUND_PROMPT}`;
}
export async function editVehicleBackground(image: { data: Buffer; contentType: string }, apiKey: string, instruction = DEFAULT_VEHICLE_BACKGROUND_PROMPT) {
  if (!apiKey) throw new Error("Image editing is not configured. Configure OPENAI_API_KEY.");
  if (!/^image\/(jpeg|png|webp)$/.test(image.contentType) || image.data.length > 5 * 1024 * 1024) throw new Error("Use a JPEG, PNG or WebP image under 5MB.");
  const form = new FormData();
  form.append("model", process.env.VEHICLE_IMAGE_EDIT_MODEL || "gpt-image-2.5-sunburst");
  form.append("image[]", new Blob([Uint8Array.from(image.data).buffer], { type: image.contentType }), `vehicle.${image.contentType === "image/png" ? "png" : image.contentType === "image/webp" ? "webp" : "jpg"}`);
  form.append("prompt", buildVehicleEditPrompt(instruction.slice(0, 1500)));
  form.append("size", "1536x1024"); form.append("quality", "medium"); form.append("output_format", "jpeg");
  const response = await fetch("https://api.openai.com/v1/images/edits", { method: "POST", headers: { Authorization: `Bearer ${apiKey}` }, body: form, signal: AbortSignal.timeout(240000) });
  const body = await response.json() as any;
  if (!response.ok) {
    if (response.status === 429 || body.error?.code === "insufficient_quota") throw new Error("OpenAI image editing is unavailable due to credits or rate limits. Review API billing and retry.");
    if (response.status === 401) throw new Error("OpenAI image editing authentication failed. Review the configured API key.");
    throw new Error("OpenAI could not edit this image. Check image-model access and retry.");
  }
  const encoded = body.data?.[0]?.b64_json;
  if (typeof encoded !== "string") throw new Error("Image editing returned no image.");
  const data = Buffer.from(encoded, "base64");
  if (!data.length || data.length > 5 * 1024 * 1024 || data[0] !== 0xff || data[1] !== 0xd8) throw new Error("Image editing returned an invalid or oversized JPEG.");
  return { data, contentType: "image/jpeg" };
}
