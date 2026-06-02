import { LightningElement, api, track } from "lwc";

const TYPE_ICONS = {
  meeting: "utility:event",
  deal: "utility:opportunity",
  issue: "utility:bug",
  milestone: "utility:ribbon",
  default: "utility:clock"
};

const STATUS_COLORS = {
  completed: "status-completed",
  pending: "status-pending",
  overdue: "status-overdue"
};

const TYPE_ICON_COLORS = {
  meeting: "icon-meeting",
  deal: "icon-deal",
  issue: "icon-issue",
  milestone: "icon-milestone",
  default: "icon-default"
};

export default class LnchatTimelineView extends LightningElement {
  @track processedEvents = [];

  @api
  set events(value) {
    if (!value || !Array.isArray(value)) {
      this.processedEvents = [];
      return;
    }

    const sorted = [...value].sort((a, b) => {
      if (!a.date) return 1;
      if (!b.date) return -1;
      return new Date(b.date) - new Date(a.date);
    });

    this.processedEvents = sorted.map((event, idx) => ({
      date: event.date || "",
      title: event.title || "",
      description: event.description || "",
      type: event.type || "default",
      status: event.status || "pending",
      formattedDate: this.formatDate(event.date),
      iconName: TYPE_ICONS[event.type] || TYPE_ICONS.default,
      iconClass:
        "timeline-icon " +
        (TYPE_ICON_COLORS[event.type] || TYPE_ICON_COLORS.default),
      statusClass:
        "event-status " +
        (STATUS_COLORS[event.status] || STATUS_COLORS.pending),
      containerClass:
        "timeline-event" + (idx % 2 === 0 ? "" : " timeline-event-alt"),
      cardClass: "event-card",
      isLast: idx === sorted.length - 1
    }));
  }

  get events() {
    return this.processedEvents;
  }

  formatDate(dateStr) {
    if (!dateStr) return "";
    try {
      const date = new Date(dateStr + "T00:00:00");
      return date.toLocaleDateString("en-US", {
        month: "short",
        day: "numeric",
        year: "numeric"
      });
    } catch {
      return dateStr;
    }
  }
}
