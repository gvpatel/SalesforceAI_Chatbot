import { LightningElement, api, track } from "lwc";

export default class LnchatKpiCardGrid extends LightningElement {
  @api rawCards = [];
  @track cards = [];

  connectedCallback() {
    this.processCards();
  }

  @api
  get cardData() {
    return this.rawCards;
  }

  set cardData(value) {
    // eslint-disable-next-line @lwc/lwc/no-api-reassignments
    this.rawCards = value || [];
    this.processCards();
  }

  processCards() {
    if (!this.rawCards || !Array.isArray(this.rawCards)) {
      this.cards = [];
      return;
    }

    this.cards = this.rawCards.map((card) => {
      const numericValue = parseFloat(
        String(card.value).replace(/[^0-9.-]/g, "")
      );
      const isNumeric = !isNaN(numericValue);

      return {
        label: card.label || "",
        value: card.value || "0",
        unit: card.unit || "",
        trend: card.trend || "",
        trendDirection: card.trendDirection || "neutral",
        icon: card.icon || "utility:metrics",
        iconName: this.resolveIcon(card.icon),
        hasTrend: !!card.trend,
        trendClass: this.getTrendClass(card.trendDirection),
        trendIcon: this.getTrendIcon(card.trendDirection),
        numericValue: isNumeric ? numericValue : 0,
        displayValue: card.value || "0",
        isNumeric
      };
    });

    // eslint-disable-next-line @lwc/lwc/no-async-operation
    requestAnimationFrame(() => {
      this.animateNumbers();
    });
  }

  animateNumbers() {
    const valueEls = this.template.querySelectorAll(".kpi-value[data-target]");
    valueEls.forEach((el) => {
      const target = parseFloat(el.dataset.target);
      if (isNaN(target) || target === 0) return;

      const start = 0;
      const duration = 800;
      const startTime = performance.now();
      const originalText = el.textContent;

      const isCurrency =
        originalText.includes("$") ||
        originalText.includes("£") ||
        originalText.includes("€");
      const isPercent = originalText.includes("%");

      const step = (currentTime) => {
        const elapsed = currentTime - startTime;
        const progress = Math.min(elapsed / duration, 1);
        const eased = 1 - Math.pow(1 - progress, 3);
        const current = Math.round(start + (target - start) * eased);

        let display = String(current);
        if (isCurrency) display = "$" + current.toLocaleString();
        else if (isPercent) display = current + "%";
        else if (target > 999) display = current.toLocaleString();

        el.textContent = display;

        if (progress < 1) {
          // eslint-disable-next-line @lwc/lwc/no-async-operation
          requestAnimationFrame(step);
        } else {
          el.textContent = originalText;
        }
      };

      // eslint-disable-next-line @lwc/lwc/no-async-operation
      requestAnimationFrame(step);
    });
  }

  getTrendClass(direction) {
    const classMap = {
      up: "kpi-trend trend-up",
      down: "kpi-trend trend-down",
      neutral: "kpi-trend trend-neutral"
    };
    return classMap[direction] || "kpi-trend trend-neutral";
  }

  getTrendIcon(direction) {
    const iconMap = {
      up: "utility:arrowup",
      down: "utility:arrowdown",
      neutral: "utility:minus"
    };
    return iconMap[direction] || "utility:minus";
  }

  resolveIcon(iconName) {
    const ALIAS = {
      opportunity: "utility:opportunity",
      opportunities: "utility:opportunity",
      revenue: "utility:moneybag",
      moneybag: "utility:moneybag",
      money: "utility:moneybag",
      dollar: "utility:moneybag",
      pipeline: "utility:funnel",
      funnel: "utility:funnel",
      contact: "utility:contact",
      contacts: "utility:people",
      people: "utility:people",
      task: "utility:task",
      tasks: "utility:task",
      case: "utility:case",
      cases: "utility:case",
      account: "utility:account",
      accounts: "utility:account",
      order: "utility:orders",
      orders: "utility:orders",
      contract: "utility:contract",
      contracts: "utility:contract",
      quote: "utility:quote",
      quotes: "utility:quote",
      calendar: "utility:event",
      event: "utility:event",
      warning: "utility:warning",
      alert: "utility:warning",
      error: "utility:error",
      success: "utility:success",
      check: "utility:check",
      info: "utility:info",
      chart: "utility:chart",
      analytics: "utility:chart",
      forecast: "utility:forecast",
      target: "utility:target",
      trophy: "utility:trail",
      crown: "utility:knowledge_base",
      metrics: "utility:metrics",
      metric: "utility:metrics",
      trend: "utility:trending_up",
      lead: "utility:lead",
      leads: "utility:lead"
    };

    if (!iconName) return "utility:metrics";
    if (iconName.includes(":")) return iconName;
    const lower = iconName.toLowerCase();
    return ALIAS[lower] || "utility:metrics";
  }
}
