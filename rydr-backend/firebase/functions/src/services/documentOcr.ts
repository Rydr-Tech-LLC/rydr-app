type VisionAnnotateResponse = {
  responses?: Array<{
    fullTextAnnotation?: { text?: string };
    textAnnotations?: Array<{ description?: string }>;
    error?: { message?: string };
  }>;
  error?: { message?: string };
};

export async function detectDocumentText(gcsUri: string, accessToken: string): Promise<string> {
  const response = await fetch("https://vision.googleapis.com/v1/images:annotate", {
    method: "POST",
    signal: AbortSignal.timeout(30_000),
    headers: {
      authorization: `Bearer ${accessToken}`,
      "content-type": "application/json"
    },
    body: JSON.stringify({
      requests: [
        {
          image: { source: { imageUri: gcsUri } },
          features: [{ type: "DOCUMENT_TEXT_DETECTION" }]
        }
      ]
    })
  });

  const payload = (await response.json()) as VisionAnnotateResponse;
  if (!response.ok) {
    throw new Error(payload.error?.message ?? `Vision OCR failed with HTTP ${response.status}`);
  }

  const first = payload.responses?.[0];
  if (first?.error?.message) {
    throw new Error(first.error.message);
  }

  return first?.fullTextAnnotation?.text?.trim()
    ?? first?.textAnnotations?.[0]?.description?.trim()
    ?? "";
}
