import { ACTIVITY_TYPE, FILE_ICONS } from "./unifiedActivityFeedConstants";

export function fileIconName(fileName) {
  const extension = String(fileName || "")
    .split(".")
    .pop()
    .toLowerCase();
  return FILE_ICONS[extension] || "doctype:attachment";
}

export function formatActivityDate(value) {
  if (!value) {
    return "";
  }
  const date = new Date(value);
  return date.toLocaleDateString(undefined, {
    month: "short",
    day: "numeric",
    year: "numeric",
    hour: "numeric",
    minute: "2-digit"
  });
}

export function buildPinnedMeta(pinnedByName, pinnedAt) {
  const when = formatActivityDate(pinnedAt);
  const who = pinnedByName ? String(pinnedByName).trim() : "";
  if (who && when) {
    return `by ${who} · ${when}`;
  }
  if (who) {
    return `by ${who}`;
  }
  return when;
}

export function buildPlainTextPreview(value, maxLength = 160) {
  if (!value) {
    return "";
  }
  const text = String(value)
    .replace(/<style[\s\S]*?<\/style>/gi, " ")
    .replace(/<script[\s\S]*?<\/script>/gi, " ")
    .replace(/<br\s*\/?>/gi, " ")
    .replace(/<\/p>/gi, " ")
    .replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;/gi, " ")
    .replace(/&amp;/gi, "&")
    .replace(/&lt;/gi, "<")
    .replace(/&gt;/gi, ">")
    .replace(/&quot;/gi, '"')
    .replace(/&#39;/gi, "'")
    .replace(/\s+/g, " ")
    .trim();
  if (text.length <= maxLength) {
    return text;
  }
  return `${text.slice(0, maxLength).trim()}…`;
}

export function timelineItemClass(type) {
  switch (type) {
    case ACTIVITY_TYPE.CALL:
      return "slds-timeline__item_call";
    case ACTIVITY_TYPE.EVENT:
      return "slds-timeline__item_event";
    case ACTIVITY_TYPE.EMAIL:
      return "slds-timeline__item_email";
    default:
      return "slds-timeline__item_task";
  }
}

export function enrichActivities(data, { showSourceLabels = false } = {}) {
  return (data || []).map((item) => {
    const contentParts = (item.contentParts || []).map((part, index) => ({
      ...part,
      key: `${item.id}-${index}`,
      isText: part.partType === "text",
      isImage: part.partType === "image",
      isFile: part.partType === "file",
      fileIcon: fileIconName(part.fileName),
      isClickable:
        (part.partType === "image" || part.partType === "file") &&
        !!part.contentDocumentId
    }));
    const hasDescription = !!(
      item.description && String(item.description).trim()
    );
    const hasDisplayBody = contentParts.length > 0 || hasDescription;
    const isEmail = item.type === ACTIVITY_TYPE.EMAIL;
    const isNote = item.type === ACTIVITY_TYPE.NOTE;
    const attachmentCount = item.attachmentCount || 0;
    const hasAttachments = isEmail && attachmentCount > 0;

    return {
      ...item,
      contentParts,
      hasContentParts: contentParts.length > 0,
      hasDescription,
      hasDisplayBody,
      showSourceLabel: showSourceLabels && !!item.sourceLabel,
      displayDate: formatActivityDate(item.createdDate),
      timelineClass: `slds-timeline__item_expandable ${timelineItemClass(item.type)}`,
      isTask: item.type === ACTIVITY_TYPE.TASK,
      isCall: item.type === ACTIVITY_TYPE.CALL,
      isEvent: item.type === ACTIVITY_TYPE.EVENT,
      isEmail,
      isNote,
      isFeed: item.type === ACTIVITY_TYPE.FEED,
      isPinned: item.isPinned === true,
      pinnedByName: item.pinnedByName || "",
      pinnedMeta: buildPinnedMeta(item.pinnedByName, item.pinnedAt),
      showPinMenu: !!item.id,
      pinMenuValue: item.isPinned === true ? "unpin" : "pin",
      pinMenuLabel: item.isPinned === true ? "Unpin" : "Pin",
      isCollapsibleBody: isEmail && hasDisplayBody,
      bodyPreview: isEmail ? buildPlainTextPreview(item.description) : "",
      attachmentCount,
      hasAttachments,
      attachmentLabel: hasAttachments
        ? attachmentCount === 1
          ? "1 attachment"
          : `${attachmentCount} attachments`
        : ""
    };
  });
}

export function extractErrorMessage(error) {
  const outputErrors = error?.body?.output?.errors;
  if (Array.isArray(outputErrors) && outputErrors.length > 0) {
    return outputErrors
      .map((item) => item.message)
      .filter((message) => !!message)
      .join(" ");
  }

  const fieldErrors = error?.body?.output?.fieldErrors;
  if (fieldErrors) {
    const messages = [];
    Object.keys(fieldErrors).forEach((field) => {
      (fieldErrors[field] || []).forEach((item) => {
        if (item.message) {
          messages.push(item.message);
        }
      });
    });
    if (messages.length > 0) {
      return messages.join(" ");
    }
  }

  if (error?.body?.message) {
    return error.body.message;
  }
  if (typeof error?.body === "string") {
    return error.body;
  }
  if (error?.message) {
    return error.message;
  }
  return "An unknown error occurred";
}
