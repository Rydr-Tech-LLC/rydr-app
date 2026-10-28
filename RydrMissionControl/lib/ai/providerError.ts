/** Only recognized diagnostics; never expose provider response content. */
export async function providerError(response: Response): Promise<Error> {
 const data = await response.json().catch(() => ({}));
 const code = data?.error?.code ?? data?.error?.type;
 if (data?.error?.type === 'insufficient_quota' || ['insufficient_quota','credit_balance_exhausted','organization_spend_limit_exceeded','project_spend_limit_exceeded','organization_usage_limit_exceeded'].includes(code)) return new Error('OpenAI API quota exhausted. Check the API project billing, credits, and spending limit.');
 if (response.status === 429 && ['rate_limit_exceeded','slow_down'].includes(code)) return new Error('OpenAI rate limit reached (429). Try again after the limit resets.');
 if (response.status === 429) return new Error('OpenAI request limited (429). Check API billing and rate limits before retrying.');
 if (response.status === 401) return new Error('OpenAI rejected the configured API key (401).');
 return new Error(`OpenAI drafting unavailable (${response.status}).`);
}
