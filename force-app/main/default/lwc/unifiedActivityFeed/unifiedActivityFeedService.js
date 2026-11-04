import getUnifiedActivities from "@salesforce/apex/UnifiedActivityController.getUnifiedActivities";
import pinActivityApex from "@salesforce/apex/UnifiedActivityController.pinActivity";
import unpinActivityApex from "@salesforce/apex/UnifiedActivityController.unpinActivity";

export function fetchUnifiedActivities(params) {
  return getUnifiedActivities(params);
}

export function pinActivity(activityId, contextRecordId) {
  return pinActivityApex({ activityId, contextRecordId });
}

export function unpinActivity(activityId, contextRecordId) {
  return unpinActivityApex({ activityId, contextRecordId });
}
