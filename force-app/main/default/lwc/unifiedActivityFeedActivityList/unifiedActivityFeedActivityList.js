import { LightningElement, api } from "lwc";

export default class UnifiedActivityFeedActivityList extends LightningElement {
  @api activities = [];
  @api isLoading = false;
  @api isLoadingMore = false;
  @api showLoadMore = false;
  @api emptyMessage = "";

  expandedActivityIds = [];
  expandedCommentIds = [];

  get hasActivities() {
    return this.activities.length > 0;
  }

  get isEmpty() {
    return !this.isLoading && !this.isLoadingMore && !this.hasActivities;
  }

  get displayActivities() {
    const expandedIds = new Set(this.expandedActivityIds);
    const expandedCommentIds = new Set(this.expandedCommentIds);
    return (this.activities || []).map((item) => {
      const isExpanded = expandedIds.has(item.id);
      const isCollapsible = item.isCollapsibleBody === true;
      const comments = item.comments || [];
      const commentsExpanded = expandedCommentIds.has(item.id);
      const commentCount = comments.length;
      return {
        ...item,
        comments,
        isExpanded,
        showPreview: isCollapsible && !isExpanded && !!item.bodyPreview,
        showCollapsedStatus: isCollapsible && !isExpanded && !!item.status,
        showFullBody: !isCollapsible || isExpanded,
        showOpenNote: item.isNote === true,
        toggleLabel: isExpanded ? "Hide email body" : "Show email body",
        expandIcon: isExpanded ? "utility:chevrondown" : "utility:chevronright",
        expandAria: isExpanded ? "true" : "false",
        showCommentsToggle: item.hasComments === true,
        showComments: commentsExpanded,
        commentsToggleLabel: commentsExpanded
          ? "Hide comments"
          : commentCount === 1
            ? "Show 1 comment"
            : `Show ${commentCount} comments`,
        commentsExpandIcon: commentsExpanded
          ? "utility:chevrondown"
          : "utility:chevronright",
        commentsExpandAria: commentsExpanded ? "true" : "false"
      };
    });
  }

  handleToggleBody(event) {
    this.toggleExpandedId("expandedActivityIds", event);
  }

  handleToggleComments(event) {
    this.toggleExpandedId("expandedCommentIds", event);
  }

  toggleExpandedId(stateKey, event) {
    event.stopPropagation();
    const recordId = event.currentTarget.dataset.id;
    if (!recordId) {
      return;
    }
    const current = this[stateKey] || [];
    this[stateKey] = current.includes(recordId)
      ? current.filter((id) => id !== recordId)
      : [...current, recordId];
  }

  handleItemClick(event) {
    const recordId = event.currentTarget.dataset.id;
    this.dispatchEvent(new CustomEvent("itemclick", { detail: { recordId } }));
  }

  handleImageClick(event) {
    event.stopPropagation();
    const contentDocumentId = event.detail?.contentDocumentId;
    if (!contentDocumentId) {
      return;
    }
    this.dispatchEvent(
      new CustomEvent("imageclick", { detail: { contentDocumentId } })
    );
  }

  handleLoadMore() {
    this.dispatchEvent(new CustomEvent("loadmore"));
  }
}
