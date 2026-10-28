/** Only recognized diagnostics; never expose provider response content. */
export async function providerError(response: Response): Promise<Error> {
 const data = await response.json().catch(() => ({}));
 const code = data?.error?.code ?? data?.error?.type;
 if (code === 'insufficient_quota') return new Error('OpenAI API quota exhausted. Check the API project billing, credits, and spending limit.');
 if (response.status === 429) return new Error('OpenAI rate limit reached (429). Try again after the limit resets.');
 if (response.status === 401) return new Error('OpenAI rejected the configured API key (401).');
 return new Error(`OpenAI drafting unavailable (${response.status}).`);
}
