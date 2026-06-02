import { LightningElement, api, track } from "lwc";
import { loadScript } from "lightning/platformResourceLoader";
import CHARTJS from "@salesforce/resourceUrl/chartjs";

const SF_PALETTE = [
  "#0176d3", // blue
  "#2e844a", // green
  "#9050e9", // purple
  "#fe9339", // orange
  "#d62928", // red
  "#16afc5", // teal
  "#dd7a01", // amber
  "#8e44ad", // violet
  "#04844b", // emerald
  "#e74c3c", // coral
  "#2980b9", // sky
  "#f39c12" // gold
];

export default class LnchatChartWidget extends LightningElement {
  @api title = "";
  @api chartType = "bar";
  @api labels = [];
  @api chartSeries = [];

  @track isLoading = true;
  @track hasError = false;

  _chartInstance = null;
  _initialized = false;

  connectedCallback() {
    loadScript(this, CHARTJS)
      .then(() => {
        this._initialized = true;
        this.renderChart();
      })
      .catch((error) => {
        console.error("ChartWidget: failed to load Chart.js", error);
        this.isLoading = false;
        this.hasError = true;
      });
  }

  disconnectedCallback() {
    if (this._chartInstance) {
      this._chartInstance.destroy();
      this._chartInstance = null;
    }
  }

  @api
  set chartConfig(config) {
    if (config) {
      /* eslint-disable @lwc/lwc/no-api-reassignments */
      this.chartType = config.chartType || "bar";
      this.labels = config.labels || [];
      this.chartSeries = config.datasets || [];
      this.title = config.title || "";
      /* eslint-enable @lwc/lwc/no-api-reassignments */
      if (this._initialized) {
        this.renderChart();
      }
    }
  }

  get chartConfig() {
    return {
      chartType: this.chartType,
      labels: this.labels,
      datasets: this.chartSeries,
      title: this.title
    };
  }

  renderChart() {
    if (!window.Chart) {
      this.hasError = true;
      this.isLoading = false;
      return;
    }

    const canvas = this.template.querySelector(".chart-canvas");
    if (!canvas) {
      // eslint-disable-next-line @lwc/lwc/no-async-operation
      setTimeout(() => this.renderChart(), 50);
      return;
    }

    if (this._chartInstance) {
      this._chartInstance.destroy();
      this._chartInstance = null;
    }

    const ctx = canvas.getContext("2d");

    // Clone arrays to break LWC reactive proxy — Chart.js mutates arrays
    // by adding a _chartjs property which throws on read-only LWC proxies.
    const labels = Array.from(this.labels || []);
    const series = Array.from(this.chartSeries || []);

    // Use per-bar colors for bar/donut with a single dataset;
    // multi-dataset bar charts get one solid color per dataset.
    const multiColor =
      this.chartType === "donut" ||
      (this.chartType === "bar" && series.length === 1);

    const mappedDatasets = series.map((ds, idx) => {
      const color = ds.color || SF_PALETTE[idx % SF_PALETTE.length];
      const bgColors = multiColor
        ? labels.map((_, i) =>
            this.hexToRgba(
              SF_PALETTE[i % SF_PALETTE.length],
              this.chartType === "donut" ? 1 : 0.82
            )
          )
        : this.chartType === "line"
          ? this.hexToRgba(color, 0.15)
          : this.hexToRgba(color, 0.82);
      const borderColors = multiColor
        ? labels.map((_, i) => SF_PALETTE[i % SF_PALETTE.length])
        : color;
      return {
        label: ds.label || "",
        data: Array.from(ds.data || []),
        backgroundColor: bgColors,
        borderColor: borderColors,
        borderWidth: this.chartType === "line" ? 2 : 1,
        fill: this.chartType === "line",
        tension: 0.4,
        pointBackgroundColor: color,
        pointRadius: 4,
        pointHoverRadius: 6,
        borderRadius: this.chartType === "bar" ? 4 : 0
      };
    });

    const config = {
      type: this.chartType === "donut" ? "doughnut" : this.chartType,
      data: {
        labels,
        datasets: mappedDatasets
      },
      options: {
        responsive: true,
        maintainAspectRatio: true,
        animation: {
          duration: 600,
          easing: "easeInOutQuart"
        },
        plugins: {
          legend: {
            display: mappedDatasets.length > 1 || this.chartType === "donut",
            position: "bottom",
            labels: {
              font: { family: "Salesforce Sans, Arial, sans-serif", size: 11 },
              color: "#3e3e3c",
              padding: 12,
              boxWidth: 12,
              boxHeight: 12,
              borderRadius: 3
            }
          },
          tooltip: {
            backgroundColor: "#ffffff",
            titleColor: "#032d60",
            bodyColor: "#3e3e3c",
            borderColor: "#dddbda",
            borderWidth: 1,
            padding: 10,
            cornerRadius: 6,
            titleFont: { weight: "bold", size: 12 },
            bodyFont: { size: 11 },
            callbacks: {
              label: (context) => {
                let label = context.dataset.label || "";
                if (label) label += ": ";
                if (
                  context.parsed.y !== null &&
                  context.parsed.y !== undefined
                ) {
                  label += context.parsed.y.toLocaleString();
                } else if (context.parsed !== null) {
                  label += context.parsed.toLocaleString();
                }
                return label;
              }
            }
          }
        },
        scales:
          this.chartType !== "donut"
            ? {
                x: {
                  grid: { display: false },
                  ticks: {
                    font: {
                      size: 10,
                      family: "Salesforce Sans, Arial, sans-serif"
                    },
                    color: "#706e6b",
                    maxRotation: 45
                  }
                },
                y: {
                  grid: { color: "#f3f3f3", borderDash: [3, 3] },
                  ticks: {
                    font: {
                      size: 10,
                      family: "Salesforce Sans, Arial, sans-serif"
                    },
                    color: "#706e6b",
                    callback: (value) => value.toLocaleString()
                  }
                }
              }
            : {}
      }
    };

    try {
      this._chartInstance = new window.Chart(ctx, config);
      this.isLoading = false;
      this.hasError = false;
    } catch (err) {
      console.error("ChartWidget: Chart.js render error", err);
      this.isLoading = false;
      this.hasError = true;
    }
  }

  hexToRgba(hex, alpha) {
    if (!hex || !hex.startsWith("#")) return `rgba(1, 118, 211, ${alpha})`;
    const r = parseInt(hex.slice(1, 3), 16);
    const g = parseInt(hex.slice(3, 5), 16);
    const b = parseInt(hex.slice(5, 7), 16);
    return `rgba(${r}, ${g}, ${b}, ${alpha})`;
  }
}
