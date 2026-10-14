const { test } = require('node:test');
const assert = require('node:assert/strict');
const { generateKeyPairSync, sign, verify } = require('node:crypto');
const { join, dirname } = require('node:path');

test('Firebase Auth imports when require(esm) is disabled by the host', () => {
  assert.equal(typeof require('firebase-admin/auth').getAuth, 'function');
});

test('JWKS conversion preserves RSA signatures and rejects tampered content', async () => {
  const { retrieveSigningKeys } = require(join(dirname(require.resolve('jwks-rsa')), 'utils.js'));
  const { publicKey, privateKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
  const jwk = { ...publicKey.export({ format: 'jwk' }), use: 'sig', alg: 'RS256', kid: 'compatibility-test' };
  const keys = await retrieveSigningKeys([jwk]);
  assert.equal(keys.length, 1);
  assert.equal(keys[0].kid, 'compatibility-test');
  const payload = Buffer.from('header.payload');
  const signature = sign('RSA-SHA256', payload, privateKey);
  assert.equal(verify('RSA-SHA256', payload, keys[0].getPublicKey(), signature), true);
  assert.equal(verify('RSA-SHA256', Buffer.from('header.tampered'), keys[0].getPublicKey(), signature), false);
  assert.deepEqual(await retrieveSigningKeys([{ kty: 'RSA', alg: 'RS256', n: 'invalid' }]), []);
});
