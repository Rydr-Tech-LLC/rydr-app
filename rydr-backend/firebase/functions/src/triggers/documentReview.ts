import { onObjectFinalized, deploymentProject } from "../workspaceFunctions";
import { reviewUploadedDocument } from "../services/documentReviewService";

export const onDocumentUploadedForReview = onObjectFinalized(
  {
    bucket: `${deploymentProject() || "rydrapp-c7ec1"}.firebasestorage.app`,
    memory: "1GiB",
    region: deploymentProject() === "rydr-test-c7ec1" ? "us-central1" : "us-east1",
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
