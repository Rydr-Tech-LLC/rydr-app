const { DOCUMENT_KINDS, DOCUMENT_LABELS, latestDocument } = require('./driverCompliancePolicy');
const DOCUMENT_REJECTION_LABELS = {blurry:'Blurry photo',unreadable:'Unreadable text',incorrect_document:'Incorrect document',incomplete:'Missing page, side or edges',expired:'Expired document',details_mismatch:'Details do not match',other:'Other — add instructions'};
const DOCUMENT_REJECTION_REASONS = {
 blurry: 'The photo is blurry. Upload a clear, focused photo.',
 unreadable: 'The text cannot be read. Upload a well-lit photo with all details readable.',
 incorrect_document: 'This is not the requested document. Upload the correct document.',
 incomplete: 'Part of the document is missing. Include all edges and required sides.',
 expired: 'This document has expired. Upload a current document.',
 details_mismatch: 'The document details do not match your driver or vehicle information. Upload matching proof.',
 other: 'A replacement document is required.'
};
function declineReason(code, note) {
 if (!Object.hasOwn(DOCUMENT_REJECTION_REASONS, code)) throw Error('Choose a valid decline reason');
 const detail = typeof note === 'string' ? note.trim().replace(/\s+/g, ' ').slice(0, 300) : '';
 if (code === 'other' && !detail) throw Error('Explain why a replacement is needed');
 return `${DOCUMENT_REJECTION_REASONS[code]}${detail ? ' ' + detail : ''}`;
}
function documentDeclines(driver) {
 return DOCUMENT_KINDS.flatMap(kind => {
  const record = latestDocument(driver, kind);
  if (record.status !== 'rejected') return [];
  return [{ kind, label: DOCUMENT_LABELS[kind], reason: String(record.driverFacingReason || record.reviewReason || 'Upload a clear, current replacement document.').slice(0, 600), revision: String(record.manualReviewId || record.reviewId || '') + '|' + String(record.storagePath || '') }];
 });
}
module.exports = {DOCUMENT_REJECTION_LABELS, DOCUMENT_REJECTION_REASONS, declineReason, documentDeclines};
