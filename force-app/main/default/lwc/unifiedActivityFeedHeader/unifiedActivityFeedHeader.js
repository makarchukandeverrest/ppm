import { LightningElement, api } from "lwc";

export default class UnifiedActivityFeedHeader extends LightningElement {
  @api countLabel;
  @api sortIcon;
  @api sortLabel;

  handleNewTask() {
    this.dispatchEvent(new CustomEvent("newtask"));
  }

  handleNewEvent() {
    this.dispatchEvent(new CustomEvent("newevent"));
  }

  handleLogACall() {
    this.dispatchEvent(new CustomEvent("logacall"));
  }

  handleLogAVisit() {
    this.dispatchEvent(new CustomEvent("logavisit"));
  }

  handleNewEmail() {
    this.dispatchEvent(new CustomEvent("newemail"));
  }

  handleNewPost() {
    this.dispatchEvent(new CustomEvent("newpost"));
  }

  handleRefresh() {
    this.dispatchEvent(new CustomEvent("refresh"));
  }

  handleSortToggle() {
    this.dispatchEvent(new CustomEvent("sorttoggle"));
  }
}
