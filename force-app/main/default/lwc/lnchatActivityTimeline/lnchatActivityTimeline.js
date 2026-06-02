import { LightningElement, api, wire } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import getActivityTimeline from "@salesforce/apex/LNChatController.getActivityTimeline";

const DAY_MS = 24 * 60 * 60 * 1000;
const CLUSTER_PCT = 4; // activities within this % of the axis merge into one node
const TYPE_ICON = {
  call: "utility:call",
  email: "utility:email",
  meeting: "utility:event",
  other: "utility:task"
};

let _key = 0;

export default class LnchatActivityTimeline extends NavigationMixin(
  LightningElement
) {
  @api recordId;
  @api objectApiName;

  loading = true;
  errorMsg = "";
  truncated = false;
  months = [];
  clusters = [];
  coverage = null; // { left, width }
  todayPct = null;
  activeKey = null; // open popover cluster key

  @wire(getActivityTimeline, { recordId: "$recordId" })
  wiredTimeline({ data, error }) {
    this.loading = false;
    if (error) {
      this.errorMsg = "Unable to load activity timeline.";
      return;
    }
    if (!data) {
      return;
    }
    if (data.available === false) {
      this.errorMsg = "";
      this.clusters = [];
      return;
    }
    this.truncated = !!data.truncated;
    this.build((data.activities || []).filter((a) => a && a.dateMs));
  }

  build(activities) {
    if (!activities.length) {
      this.clusters = [];
      return;
    }

    const dates = activities.map((a) => Number(a.dateMs));
    const minMs = Math.min(...dates);
    const maxMs = Math.max(...dates);
    const today = Date.now();

    let start = Math.min(minMs, today);
    let end = Math.max(maxMs, today);
    // pad the axis so endpoints aren't flush against the edge
    const pad = Math.max((end - start) * 0.06, 7 * DAY_MS);
    start -= pad;
    end += pad;
    if (end - start < 30 * DAY_MS) {
      // single date / tiny range — open a readable window
      start -= 45 * DAY_MS;
      end += 45 * DAY_MS;
    }
    const span = end - start;
    const pct = (ms) => ((ms - start) / span) * 100;

    // month gridlines
    this.months = this.buildMonths(start, end, pct);

    // today marker
    const tp = pct(today);
    this.todayPct = tp >= 0 && tp <= 100 ? tp : null;

    // coverage bar (engagement span: first → last activity)
    this.coverage = {
      left: pct(minMs),
      width: Math.max(pct(maxMs) - pct(minMs), 0.5)
    };

    // cluster by proximity along the axis
    const sorted = activities
      .map((a) => ({ ...a, ms: Number(a.dateMs), p: pct(Number(a.dateMs)) }))
      .sort((a, b) => a.ms - b.ms);

    const groups = [];
    let cur = null;
    for (const a of sorted) {
      if (cur && a.p - cur.lastP <= CLUSTER_PCT) {
        cur.items.push(a);
        cur.lastP = a.p;
      } else {
        cur = { items: [a], firstP: a.p, lastP: a.p };
        groups.push(cur);
      }
    }

    this.clusters = groups.map((g) => this.toCluster(g));
  }

  toCluster(g) {
    const items = g.items;
    const count = items.length;
    // representative type = most frequent (tie → most recent)
    const freq = {};
    items.forEach((i) => (freq[i.type] = (freq[i.type] || 0) + 1));
    let repType = items[items.length - 1].type;
    let best = 0;
    Object.keys(freq).forEach((t) => {
      if (freq[t] > best) {
        best = freq[t];
        repType = t;
      }
    });

    const msList = items.map((i) => i.ms);
    const startMs = Math.min(...msList);
    const endMs = Math.max(...msList);
    const key = "c" + ++_key;

    return {
      key,
      left: (g.firstP + g.lastP) / 2,
      count,
      countLabel: count > 1 ? String(count) : "",
      icon: TYPE_ICON[repType] || TYPE_ICON.other,
      ringClass: count > 1 ? "tl-node tl-node-multi" : "tl-node",
      rangeLabel:
        startMs === endMs
          ? this.fmt(startMs)
          : this.fmt(startMs) + " – " + this.fmt(endMs),
      eventsLabel: count + (count === 1 ? " Event" : " Events"),
      // items, computed lazily for the popover
      items: items
        .sort((a, b) => b.ms - a.ms)
        .map((i) => ({
          key: "i" + ++_key,
          id: i.id,
          sobjectType: i.sobjectType,
          subject: i.subject || "(no subject)",
          source: (i.source || "Salesforce").toUpperCase(),
          icon: TYPE_ICON[i.type] || TYPE_ICON.other
        }))
    };
  }

  buildMonths(start, end, pct) {
    const out = [];
    const d = new Date(start);
    d.setDate(1);
    d.setHours(0, 0, 0, 0);
    // step to first month boundary at/after start
    if (d.getTime() < start) {
      d.setMonth(d.getMonth() + 1);
    }
    let guard = 0;
    while (d.getTime() <= end && guard++ < 60) {
      const p = pct(d.getTime());
      // Edge-aware alignment so labels never spill past the card in the narrow chat panel:
      // left-align the first month, right-align the last, center the rest.
      const shift = p < 8 ? "0" : p > 92 ? "-100%" : "-50%";
      out.push({
        key: "m" + d.getTime(),
        label: d.toLocaleDateString("en-US", {
          month: "short",
          year: "numeric"
        }),
        leftStyle: `left:${p}%; transform: translateX(${shift});`
      });
      d.setMonth(d.getMonth() + 1);
    }
    return out;
  }

  fmt(ms) {
    return new Date(ms).toLocaleDateString("en-US", {
      month: "short",
      day: "numeric",
      year: "numeric"
    });
  }

  // ── interaction ──
  get hasClusters() {
    return this.clusters.length > 0;
  }

  get showEmpty() {
    return !this.loading && !this.errorMsg && this.clusters.length === 0;
  }

  get decoratedClusters() {
    return this.clusters.map((c) => ({
      ...c,
      style: `left:${c.left}%;`,
      wrapClass:
        this.activeKey === c.key
          ? "tl-cluster tl-cluster-active"
          : "tl-cluster",
      isOpen: this.activeKey === c.key
    }));
  }

  get todayStyle() {
    return `left:${this.todayPct}%;`;
  }

  get coverageStyle() {
    return this.coverage
      ? `left:${this.coverage.left}%;width:${this.coverage.width}%;`
      : "";
  }

  handleNodeClick(event) {
    const key = event.currentTarget.dataset.key;
    this.activeKey = this.activeKey === key ? null : key;
  }

  handleClosePopover() {
    this.activeKey = null;
  }

  handleItemClick(event) {
    const { id, sobject } = event.currentTarget.dataset;
    if (!id) {
      return;
    }
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: { recordId: id, objectApiName: sobject, actionName: "view" }
    });
  }
}
