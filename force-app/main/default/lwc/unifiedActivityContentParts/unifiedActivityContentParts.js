import { LightningElement, api } from "lwc";

export default class UnifiedActivityContentParts extends LightningElement {
  @api parts = [];
  @api fallbackText = "";

  get hasParts() {
    return Array.isArray(this.parts) && this.parts.length > 0;
  }

  get showFallback() {
    return !this.hasParts && !!this.fallbackText;
  }

  handleImageClick(event) {
    event.stopPropagation();
    const contentDocumentId = event.currentTarget.dataset.id;
    this.dispatchEvent(
      new CustomEvent("imageclick", { detail: { contentDocumentId } })
    );
  }

  handleImageKeydown(event) {
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      this.handleImageClick(event);
    }
  }
}
