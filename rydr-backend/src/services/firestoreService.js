const { getFirestore } = require("../config/firebase");

function collection(collectionName) {
  return getFirestore().collection(collectionName);
}

function doc(collectionName, documentId) {
  return collection(collectionName).doc(documentId);
}

module.exports = {
  getFirestore,
  collection,
  doc
};
