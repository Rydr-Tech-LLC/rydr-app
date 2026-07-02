import { onObjectFinalized } from "firebase-functions/v2/storage";
import { reviewUploadedDocument } from "../services/documentReviewService";

export const onDocumentUploadedForReview = onObjectFinalized(
  {
    bucket: "rydrapp-c7ec1.firebasestorage.app",
    memory: "1GiB",
    region: "us-east1",
    timeoutSeconds: 120
  },
  async (event) => {
    await reviewUploadedDocument({
      bucket: event.data.bucket,
      contentType: event.data.contentType,
      generation: event.data.generation,
      metadata: event.data.metadata,
      storagePath: event.data.name
    });
  }
);
